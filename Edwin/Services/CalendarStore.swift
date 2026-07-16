import Foundation
import EventKit

/// Connects the device calendar (EventKit) and syncs upcoming events to Supabase
/// so Edwin can reason about the owner's availability.
@MainActor
final class CalendarStore: ObservableObject {
    @Published var connected = false
    @Published var syncing = false
    @Published var eventCount = 0
    @Published var lastError: String?
    @Published var availableCalendars: [EKCalendar] = []
    @Published var selectedIds: Set<String> = []

    weak var auth: AuthStore?
    private let store = EKEventStore()

    private let connectedKey = "edwin.calendar.connected"
    private let selectedKey = "edwin.calendar.selected"

    init() {
        connected = UserDefaults.standard.bool(forKey: connectedKey)
        selectedIds = Set(UserDefaults.standard.stringArray(forKey: selectedKey) ?? [])
        if connected { loadCalendars() }
    }

    /// All event calendars on the device. Empty selection = watch everything.
    func loadCalendars() {
        availableCalendars = store.calendars(for: .event)
            .sorted { ($0.source.title, $0.title) < ($1.source.title, $1.title) }
    }

    func isSelected(_ cal: EKCalendar) -> Bool {
        selectedIds.isEmpty || selectedIds.contains(cal.calendarIdentifier)
    }

    /// Toggle one calendar. Selection materializes from "all" on first touch.
    func toggle(_ cal: EKCalendar) {
        if selectedIds.isEmpty {
            selectedIds = Set(availableCalendars.map(\.calendarIdentifier))
        }
        if selectedIds.contains(cal.calendarIdentifier) {
            selectedIds.remove(cal.calendarIdentifier)
        } else {
            selectedIds.insert(cal.calendarIdentifier)
        }
        // selecting everything collapses back to "all" (new calendars auto-include)
        if selectedIds.count == availableCalendars.count { selectedIds = [] }
        UserDefaults.standard.set(Array(selectedIds), forKey: selectedKey)
        Task { await sync() }
    }

    var selectionLabel: String {
        guard connected, !availableCalendars.isEmpty else { return "" }
        return selectedIds.isEmpty
            ? "All \(availableCalendars.count) calendars"
            : "\(selectedIds.count) of \(availableCalendars.count) calendars"
    }

    /// Ask for calendar access, then do a first sync.
    func connect() async {
        lastError = nil
        do {
            let granted: Bool
            if #available(iOS 17.0, *) {
                granted = try await store.requestFullAccessToEvents()
            } else {
                granted = try await store.requestAccess(to: .event)
            }
            guard granted else {
                lastError = "Calendar access was denied. Enable it in Settings › Edwin."
                return
            }
            connected = true
            UserDefaults.standard.set(true, forKey: connectedKey)
            loadCalendars()
            await sync()
        } catch {
            lastError = "Couldn't connect calendar: \(error.localizedDescription)"
        }
    }

    func disconnect() async {
        connected = false
        eventCount = 0
        UserDefaults.standard.set(false, forKey: connectedKey)
        guard let token = auth?.accessToken, let userId = auth?.userId else { return }
        try? await CalendarSync.clear(userId: userId, token: token)
        try? await CalendarSync.setConnection(userId: userId, connected: false, token: token)
    }

    /// Upcoming events grouped by day, for the Calendar tab.
    func upcomingByDay(daysAhead: Int = 30) -> [(date: Date, events: [EKEvent])] {
        guard connected else { return [] }
        let end = Calendar.current.date(byAdding: .day, value: daysAhead, to: Date()) ?? Date()
        if availableCalendars.isEmpty { loadCalendars() }
        let watched: [EKCalendar]? = selectedIds.isEmpty
            ? nil
            : availableCalendars.filter { selectedIds.contains($0.calendarIdentifier) }
        let pred = store.predicateForEvents(withStart: Date(), end: end, calendars: watched)
        let events = store.events(matching: pred).sorted { $0.startDate < $1.startDate }
        let grouped = Dictionary(grouping: events) { Calendar.current.startOfDay(for: $0.startDate) }
        return grouped.keys.sorted().map { (date: $0, events: grouped[$0] ?? []) }
    }

    /// Events Edwin created server-side: write them into the real device
    /// calendar, mark them added, then re-sync so they upload as real events.
    func processPendingEvents() async {
        guard connected, let token = auth?.accessToken, let userId = auth?.userId, !userId.isEmpty else { return }
        guard let rows = try? await CalendarSync.pendingEvents(userId: userId, token: token), !rows.isEmpty else { return }
        var addedAny = false
        for row in rows {
            guard let start = Self.parseISO(row.starts_at) else {
                try? await CalendarSync.markPending(id: row.id, status: "failed", token: token)
                continue
            }
            let ev = EKEvent(eventStore: store)
            ev.title = row.title
            ev.startDate = start
            ev.endDate = row.ends_at.flatMap { Self.parseISO($0) } ?? start.addingTimeInterval(3600)
            ev.isAllDay = row.all_day ?? false
            ev.location = row.location
            ev.calendar = store.defaultCalendarForNewEvents
            do {
                try store.save(ev, span: .thisEvent)
                addedAny = true
                try? await CalendarSync.markPending(id: row.id, status: "added",
                                                    calendarTitle: ev.calendar?.title, token: token)
            } catch {
                try? await CalendarSync.markPending(id: row.id, status: "failed", token: token)
            }
        }
        if addedAny { await sync() }
    }

    static func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    /// Pull the next 12 months of events and push them to Supabase.
    func sync() async {
        guard connected, let token = auth?.accessToken, let userId = auth?.userId, !userId.isEmpty else { return }
        syncing = true
        defer { syncing = false }

        let now = Date()
        let end = Calendar.current.date(byAdding: .month, value: 12, to: now) ?? now
        if availableCalendars.isEmpty { loadCalendars() }
        let watched: [EKCalendar]? = selectedIds.isEmpty
            ? nil  // all calendars
            : availableCalendars.filter { selectedIds.contains($0.calendarIdentifier) }
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: watched)
        let events = store.events(matching: predicate)

        let iso = ISO8601DateFormatter()
        // PostgREST bulk inserts require identical keys on every row, so always
        // send the full column set (NSNull for gaps). Recurring events reuse one
        // eventIdentifier per series — suffix the start time to keep rows unique.
        var seen = Set<String>()
        var rows: [[String: Any]] = []
        for e in events.prefix(1000) {
            let baseId = e.eventIdentifier ?? UUID().uuidString
            let eventId = "\(baseId)@\(Int(e.startDate.timeIntervalSince1970))"
            guard seen.insert(eventId).inserted else { continue }  // batch must be dupe-free
            rows.append([
                "user_id": userId,
                "event_id": eventId,
                "title": e.title ?? "(busy)",
                "starts_at": iso.string(from: e.startDate),
                "ends_at": e.endDate.map { iso.string(from: $0) } ?? NSNull(),
                "location": (e.location?.isEmpty == false ? e.location! : NSNull()) as Any,
                "calendar_title": (e.calendar?.title.isEmpty == false ? e.calendar!.title : NSNull()) as Any,
                "all_day": e.isAllDay,
            ])
        }
        do {
            try await CalendarSync.replace(userId: userId, rows: rows, token: token)
            try await CalendarSync.setConnection(userId: userId, connected: true, token: token)
            eventCount = rows.count
        } catch {
            lastError = "Sync failed: \(error.localizedDescription)"
        }
    }
}

enum CalendarSync {
    private static let rest = "https://cchnsizaeoqhgawkyugs.supabase.co/rest/v1"

    private static func req(_ method: String, _ path: String, token: String, body: Any? = nil, prefer: String? = nil) async throws {
        var r = URLRequest(url: URL(string: rest + path)!)
        r.httpMethod = method
        r.setValue(SupabaseAuthClient.anonKey, forHTTPHeaderField: "apikey")
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { r.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let body { r.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (_, resp) = try await URLSession.shared.data(for: r)
        guard let http = resp as? HTTPURLResponse, http.statusCode < 400 else {
            throw AuthError.server("Calendar sync error \((resp as? HTTPURLResponse)?.statusCode ?? 0).")
        }
    }

    struct PendingEvent: Codable {
        let id: Int
        let title: String
        let starts_at: String
        let ends_at: String?
        let all_day: Bool?
        let location: String?
    }

    /// Events Edwin queued for the device calendar.
    static func pendingEvents(userId: String, token: String) async throws -> [PendingEvent] {
        var r = URLRequest(url: URL(string: rest + "/assistant_calendar_pending?user_id=eq.\(userId)&status=eq.pending&select=id,title,starts_at,ends_at,all_day,location&order=id.asc&limit=20")!)
        r.setValue(SupabaseAuthClient.anonKey, forHTTPHeaderField: "apikey")
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: r)
        guard let http = resp as? HTTPURLResponse, http.statusCode < 400 else { return [] }
        return (try? JSONDecoder().decode([PendingEvent].self, from: data)) ?? []
    }

    static func markPending(id: Int, status: String, calendarTitle: String? = nil, token: String) async throws {
        var body: [String: Any] = ["status": status]
        if let calendarTitle { body["calendar_title"] = calendarTitle }
        try await req("PATCH", "/assistant_calendar_pending?id=eq.\(id)", token: token,
                      body: body, prefer: "return=minimal")
    }

    /// Replace the user's synced window: clear then upsert (tolerates dupes).
    static func replace(userId: String, rows: [[String: Any]], token: String) async throws {
        try await clear(userId: userId, token: token)
        guard !rows.isEmpty else { return }
        for chunk in stride(from: 0, to: rows.count, by: 100).map({ Array(rows[$0..<min($0+100, rows.count)]) }) {
            try await req("POST", "/assistant_calendar?on_conflict=user_id,event_id", token: token,
                          body: chunk, prefer: "resolution=merge-duplicates,return=minimal")
        }
    }

    static func clear(userId: String, token: String) async throws {
        try await req("DELETE", "/assistant_calendar?user_id=eq.\(userId)", token: token, prefer: "return=minimal")
    }

    static func setConnection(userId: String, connected: Bool, token: String) async throws {
        try await req("POST", "/assistant_connections?on_conflict=user_id,provider", token: token,
            body: [["user_id": userId, "provider": "apple_calendar",
                    "status": connected ? "connected" : "disconnected"]],
            prefer: "resolution=merge-duplicates,return=minimal")
    }
}

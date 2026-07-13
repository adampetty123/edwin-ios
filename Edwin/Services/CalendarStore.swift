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

    weak var auth: AuthStore?
    private let store = EKEventStore()

    private let connectedKey = "edwin.calendar.connected"

    init() {
        connected = UserDefaults.standard.bool(forKey: connectedKey)
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

    /// Pull the next 30 days of events and push them to Supabase.
    func sync() async {
        guard connected, let token = auth?.accessToken, let userId = auth?.userId, !userId.isEmpty else { return }
        syncing = true
        defer { syncing = false }

        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: 30, to: now) ?? now
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: nil)
        let events = store.events(matching: predicate)

        let iso = ISO8601DateFormatter()
        let rows: [[String: Any]] = events.prefix(200).map { e in
            var row: [String: Any] = [
                "user_id": userId,
                "event_id": e.eventIdentifier ?? UUID().uuidString,
                "title": e.title ?? "(busy)",
                "starts_at": iso.string(from: e.startDate),
                "all_day": e.isAllDay,
            ]
            if let ed = e.endDate { row["ends_at"] = iso.string(from: ed) }
            if let loc = e.location, !loc.isEmpty { row["location"] = loc }
            return row
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

    /// Replace the user's synced window: clear then insert.
    static func replace(userId: String, rows: [[String: Any]], token: String) async throws {
        try await clear(userId: userId, token: token)
        guard !rows.isEmpty else { return }
        for chunk in stride(from: 0, to: rows.count, by: 100).map({ Array(rows[$0..<min($0+100, rows.count)]) }) {
            try await req("POST", "/assistant_calendar", token: token, body: chunk, prefer: "return=minimal")
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

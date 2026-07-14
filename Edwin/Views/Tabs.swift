import SwiftUI
import EventKit

// MARK: - Root tab bar (liquid glass on iOS 26, classic below)

struct MainTabView: View {
    var body: some View {
        // Base (outline) SF Symbols only — the system fills the selected tab
        // itself; hardcoding .fill variants makes every tab look heavy.
        if #available(iOS 26.0, *) {
            TabView {
                Tab("Edwin", systemImage: "sparkles") { EdwinTab() }
                Tab("Messages", systemImage: "message") { InboxView() }
                Tab("Email", systemImage: "envelope") { EmailTab() }
                Tab("Calendar", systemImage: "calendar") { CalendarTab() }
                Tab(role: .search) { SearchTab() }
            }
        } else {
            TabView {
                EdwinTab().tabItem { Label("Edwin", systemImage: "sparkles") }
                InboxView().tabItem { Label("Messages", systemImage: "message") }
                EmailTab().tabItem { Label("Email", systemImage: "envelope") }
                CalendarTab().tabItem { Label("Calendar", systemImage: "calendar") }
                SearchTab().tabItem { Label("Search", systemImage: "magnifyingglass") }
            }
        }
    }
}

// MARK: - Edwin

struct EdwinTab: View {
    @EnvironmentObject var wa: WAStore

    var body: some View {
        NavigationStack {
            if let edwin = wa.assistantChat {
                AssistantChatView(chat: edwin)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.bg)
                    .task { await wa.ensureAssistant(); await wa.refreshChats() }
            }
        }
    }
}

// MARK: - Email (placeholder until Gmail lands)

struct EmailTab: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Image(systemName: "envelope.badge")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.textFaint)
                Text("Email is coming soon")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text("Edwin will triage your Gmail the same way he handles WhatsApp — junk archived, what matters surfaced.")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Theme.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg)
            .navigationTitle("Email")
        }
    }
}

// MARK: - Calendar

struct CalendarTab: View {
    @EnvironmentObject var cal: CalendarStore
    @State private var days: [(date: Date, events: [EKEvent])] = []

    var body: some View {
        NavigationStack {
            Group {
                if !cal.connected {
                    VStack(spacing: 14) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 44))
                            .foregroundStyle(Theme.textFaint)
                        Text("Connect your calendar")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.text)
                        Button("Connect") { Task { await cal.connect(); load() } }
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if days.isEmpty {
                    Text("Nothing scheduled in the next 30 days")
                        .font(.system(size: 15, design: .rounded))
                        .foregroundStyle(Theme.textMuted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(days, id: \.date) { day in
                            Section(dayLabel(day.date)) {
                                ForEach(day.events, id: \.eventIdentifier) { e in
                                    HStack(spacing: 12) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Theme.accent)
                                            .frame(width: 4, height: 34)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(e.title ?? "(busy)")
                                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                                .foregroundStyle(Theme.text)
                                            Text(timeLabel(e))
                                                .font(.system(size: 12.5, design: .rounded))
                                                .foregroundStyle(Theme.textMuted)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Theme.bg)
            .navigationTitle("Calendar")
            .task { load() }
            .refreshable { await cal.sync(); load() }
        }
    }

    private func load() { days = cal.upcomingByDay(daysAhead: 30) }

    private func dayLabel(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInTomorrow(d) { return "Tomorrow" }
        return d.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }

    private func timeLabel(_ e: EKEvent) -> String {
        if e.isAllDay { return "All day" }
        let start = e.startDate.formatted(date: .omitted, time: .shortened)
        let end = e.endDate?.formatted(date: .omitted, time: .shortened)
        return end != nil ? "\(start) – \(end!)" : start
    }
}

// MARK: - Search

struct SearchTab: View {
    @EnvironmentObject var wa: WAStore
    @State private var search = ""
    @State private var messageHits: [WAMessage] = []
    @State private var searchTask: Task<Void, Never>?

    private var realChats: [WAChat] { wa.chats.filter { !$0.assistant } }
    private var query: String { search.trimmingCharacters(in: .whitespaces) }

    private var chatMatches: [WAChat] {
        guard !query.isEmpty else { return [] }
        let q = query.lowercased()
        return realChats.filter {
            $0.displayName.lowercased().contains(q)
            || ($0.lastMessageText?.lowercased().contains(q) ?? false)
        }
    }

    private var extraMessageHits: [WAMessage] {
        let covered = Set(chatMatches.map(\.jid))
        return messageHits.filter { !covered.contains($0.chatJid) }
    }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    Text("Search every chat and message")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Theme.textMuted)
                        .listRowBackground(Color.clear)
                } else {
                    if !chatMatches.isEmpty {
                        Section("Chats") {
                            ForEach(chatMatches) { chat in
                                NavigationLink(value: chat) { ChatRow(chat: chat) }
                            }
                        }
                    }
                    if !extraMessageHits.isEmpty {
                        Section("Messages") {
                            ForEach(extraMessageHits) { hit in
                                if let c = realChats.first(where: { $0.jid == hit.chatJid }) {
                                    NavigationLink(value: c) {
                                        MessageHitRow(chat: c, hit: hit, query: query)
                                    }
                                }
                            }
                        }
                    }
                    if chatMatches.isEmpty && extraMessageHits.isEmpty {
                        Text("No matches")
                            .font(.system(size: 14, design: .rounded))
                            .foregroundStyle(Theme.textMuted)
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.plain)
            .background(Theme.bg)
            .navigationTitle("Search")
            .searchable(text: $search, prompt: "Search chats and messages")
            .onChange(of: search) {
                let q = search
                searchTask?.cancel()
                guard q.trimmingCharacters(in: .whitespaces).count >= 2 else { messageHits = []; return }
                searchTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    let hits = await wa.searchMessages(q)
                    if !Task.isCancelled { messageHits = hits }
                }
            }
            .navigationDestination(for: WAChat.self) { chat in
                if chat.assistant { AssistantChatView(chat: chat) }
                else { ChatView(chat: chat) }
            }
        }
    }
}

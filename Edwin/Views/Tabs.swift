import SwiftUI
import EventKit

// MARK: - Root: Edwin IS the app. No tab bar — chats top-left, settings top-right.

struct MainTabView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var wa: WAStore
    @EnvironmentObject var cal: CalendarStore

    /// One typed path for every push — mixing isPresented-bindings with
    /// value pushes on the same stack causes the "opens then bounces back"
    /// navigation bug this replaces.
    private enum HomeRoute: Hashable { case chats, settings }
    @State private var path = NavigationPath()
    @StateObject private var emailStore = EmailStore()
    @ObservedObject private var router = NotificationRouter.shared

    private var unreadTotal: Int {
        wa.chats.filter { !$0.assistant }.reduce(0) { $0 + ($1.unread ?? 0) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let edwin = wa.assistantChat {
                    AssistantChatView(chat: edwin)
                } else {
                    LoadingView()
                }
            }
            .toolbar {
                // bare icons — the system wraps toolbar buttons in circular
                // liquid glass itself; our old Theme.surface circle was a grey
                // fill sitting inside that, hence the double-background look
                ToolbarItem(placement: .topBarLeading) {
                    Button { path.append(HomeRoute.chats) } label: {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.text)
                    }
                    .accessibilityLabel(unreadTotal > 0 ? "All chats, \(unreadTotal) unread" : "All chats")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { path.append(HomeRoute.settings) } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.text)
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .chats: InboxView()
                case .settings: SettingsView()
                }
            }
            .navigationDestination(for: WAChat.self) { chat in
                if chat.assistant { AssistantChatView(chat: chat) }
                else { ChatView(chat: chat) }
            }
            .navigationDestination(for: Email.self) { email in
                EmailDetailView(email: email)
            }
        }
        .environmentObject(emailStore)
        .onChange(of: router.pendingChatJid) { openPendingChat() }
        .onChange(of: wa.chats.count) {
            // chats can land after the tap (cold launch) — retry then
            if router.pendingChatJid != nil { openPendingChat() }
        }
        .onAppear {
            // tap set the route before this view existed (cold launch)
            if router.pendingChatJid != nil { openPendingChat() }
        }
        .task {
            // app-wide background work (used to live on the Messages tab)
            emailStore.auth = auth
            await wa.ensureAssistant()
            await wa.refreshChats()
            PushManager.shared.enable()
            while !Task.isCancelled {
                wa.startRealtime()
                await PushManager.shared.syncIfNeeded(userId: auth.userId, accessToken: auth.accessToken)
                await wa.refreshAccount()
                await wa.refreshChats()
                await wa.refreshDrafts()
                await cal.processPendingEvents()
                try? await Task.sleep(nanoseconds: wa.realtime.connected ? 20_000_000_000 : 5_000_000_000)
            }
        }
    }

    /// Notification tap → jump straight into that chat (Edwin chat = home root).
    private func openPendingChat() {
        guard let jid = router.pendingChatJid else { return }
        if jid == WAClient.assistantJid {
            router.pendingChatJid = nil
            path = NavigationPath()   // Edwin chat IS home
            return
        }
        guard let chat = wa.chats.first(where: { $0.jid == jid }) else { return } // retry on next chats refresh
        router.pendingChatJid = nil
        path = NavigationPath()
        path.append(chat)
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

// MARK: - Email (gmail inbox, synced by the bridge into supabase)

struct EmailTab: View {
    var body: some View {
        EmailListView()
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

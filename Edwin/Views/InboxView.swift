import SwiftUI

struct InboxView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var wa: WAStore
    @EnvironmentObject var cal: CalendarStore

    @EnvironmentObject var emailStore: EmailStore

    /// Channel filter behind the toolbar funnel button.
    enum ChannelFilter: String, CaseIterable {
        case all = "All"
        case whatsapp = "WhatsApp"
        case email = "Email"
    }
    @State private var filter: ChannelFilter = .all

    @State private var search = ""
    @State private var messageHits: [WAMessage] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var showSettings = false

    private var realChats: [WAChat] { wa.chats.filter { !$0.assistant } }
    private var searching: Bool { !search.trimmingCharacters(in: .whitespaces).isEmpty }

    /// WhatsApp chats and emails, one stream, newest activity first.
    private enum InboxItem: Identifiable {
        case chat(WAChat)
        case email(Email)
        var id: String {
            switch self {
            case .chat(let c): return "c:\(c.jid)"
            case .email(let e): return "e:\(e.gmailId)"
            }
        }
        var when: Date {
            switch self {
            case .chat(let c): return c.lastMessageAt ?? .distantPast
            case .email(let e): return e.ts ?? .distantPast
            }
        }
    }

    private var unifiedItems: [InboxItem] {
        let chats = filter == .email ? [] : realChats.map(InboxItem.chat)
        let emails = filter == .whatsapp ? [] : emailStore.emails.map(InboxItem.email)
        return (chats + emails).sorted { $0.when > $1.when }
    }

    private var emailMatches: [Email] {
        guard filter != .whatsapp else { return [] }
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return emailStore.emails.filter {
            $0.sender.lowercased().contains(q)
            || ($0.subject?.lowercased().contains(q) ?? false)
            || ($0.snippet?.lowercased().contains(q) ?? false)
        }
    }

    /// Chats whose name or last message matches the query.
    private var chatMatches: [WAChat] {
        guard filter != .email else { return [] }
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return realChats }
        return realChats.filter {
            $0.displayName.lowercased().contains(q)
            || ($0.lastMessageText?.lowercased().contains(q) ?? false)
        }
    }

    /// Message hits whose chat isn't already covered by a name/preview match.
    private var extraMessageHits: [WAMessage] {
        let covered = Set(chatMatches.map(\.jid))
        return messageHits.filter { !covered.contains($0.chatJid) }
    }

    var body: some View {
        // Pushed from the Edwin home screen — lives in the parent NavigationStack.
        list
            .background(Theme.bg)
            .navigationTitle("All Chats")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Search chats, messages and email")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Filter", selection: $filter) {
                            Label("All", systemImage: "tray.full").tag(ChannelFilter.all)
                            Label("WhatsApp", systemImage: "message").tag(ChannelFilter.whatsapp)
                            Label("Email", systemImage: "envelope").tag(ChannelFilter.email)
                        }
                    } label: {
                        Image(systemName: filter == .all
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(filter == .all ? Theme.text : Theme.accent)
                    }
                    .accessibilityLabel("Filter: \(filter.rawValue)")
                }
            }
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
            .task {
                emailStore.auth = auth
                await emailStore.refresh()
                while !Task.isCancelled {
                    await wa.refreshChats()
                    await emailStore.refresh()
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                }
            }
    }

    private func chat(for jid: String) -> WAChat? { wa.chats.first { $0.jid == jid } }

    // Settings lives behind the gear. Connection state stays visible without
    // shouting: a small dot on the gear — green when live, grey when offline.
    private var settingsButton: some View {
        Button { showSettings = true } label: {
            Circle()
                .fill(Theme.surface)
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.textMuted)
                )
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(wa.isConnected ? Theme.success : Theme.textFaint)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Theme.bg, lineWidth: 1.5))
                }
        }
        .accessibilityLabel(wa.isConnected ? "Settings. WhatsApp connected" : "Settings. WhatsApp offline")
    }

    @ViewBuilder
    private var list: some View {
        if searching {
            searchResults
        } else {
            List {
                if unifiedItems.isEmpty {
                    Group {
                        if wa.isConnected { syncingRow } else { notConnectedRow }
                    }
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(unifiedItems) { item in
                        switch item {
                        case .chat(let chat):
                            NavigationLink(value: chat) { ChatRow(chat: chat, senderAvatar: wa.senderAvatars[chat.lastSenderJid ?? ""]) }
                                .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20))
                                .listRowSeparatorTint(Theme.border)
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        Task { await wa.hideChat(chat) }
                                    } label: { Label("Delete", systemImage: "trash") }
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        Task { await wa.hideChat(chat) }
                                    } label: { Label("Delete", systemImage: "trash") }
                                }
                        case .email(let email):
                            NavigationLink(value: email) { UnifiedEmailRow(email: email) }
                                .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20))
                                .listRowSeparatorTint(Theme.border)
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        Task { await emailStore.delete(email) }
                                    } label: { Label("Delete", systemImage: "trash") }
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        Task { await emailStore.delete(email) }
                                    } label: { Label("Delete", systemImage: "trash") }
                                }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .refreshable { await wa.refreshChats(); await emailStore.refresh() }
        }
    }

    private var searchResults: some View {
        List {
            if !chatMatches.isEmpty {
                Section("Chats") {
                    ForEach(chatMatches) { chat in
                        NavigationLink(value: chat) { ChatRow(chat: chat, senderAvatar: wa.senderAvatars[chat.lastSenderJid ?? ""]) }
                            .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20))
                    }
                }
            }
            if !extraMessageHits.isEmpty {
                Section("Messages") {
                    ForEach(extraMessageHits) { hit in
                        if let c = chat(for: hit.chatJid) {
                            NavigationLink(value: c) {
                                MessageHitRow(chat: c, hit: hit, query: search)
                            }
                            .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20))
                        }
                    }
                }
            }
            if !emailMatches.isEmpty {
                Section("Email") {
                    ForEach(emailMatches) { email in
                        NavigationLink(value: email) { UnifiedEmailRow(email: email) }
                            .listRowInsets(EdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20))
                    }
                }
            }
            if chatMatches.isEmpty && extraMessageHits.isEmpty && emailMatches.isEmpty {
                Text(search.trimmingCharacters(in: .whitespaces).count < 2
                     ? "Keep typing to search…"
                     : "No matches for “\(search)”.")
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(Theme.textMuted)
                    .frame(maxWidth: .infinity).padding(.vertical, 30)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
    }

    private var notConnectedRow: some View {
        VStack(spacing: 10) {
            Text("Connect WhatsApp to fill your inbox")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.text)
            Text("Edwin's ready above. Link WhatsApp in Settings and your real chats show up here.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 30).padding(.horizontal, 24)
    }

    private var syncingRow: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Syncing your chats\u{2026} \(wa.account?.messagesSynced ?? 0) messages in")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 30)
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        let base = h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
        let first = auth.userName.components(separatedBy: " ").first ?? ""
        return first.isEmpty ? base : "\(base), \(first)"
    }
}

struct ChatRow: View {
    let chat: WAChat
    var senderAvatar: String? = nil

    private var unread: Bool { (chat.unread ?? 0) > 0 }
    private var isGroup: Bool { chat.isGroup == true }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(chat.displayName)
                        .font(.system(size: 15, weight: unread ? .bold : .semibold, design: .rounded))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Spacer()
                    Text(timeLabel)
                        .font(.system(size: 13, weight: unread ? .semibold : .regular, design: .rounded))
                        .foregroundStyle(unread ? Theme.accent : Theme.textFaint)
                }
                HStack(alignment: .center) {
                    Text(preview)
                        .font(.system(size: 13.5, design: .rounded))
                        .foregroundStyle(unread ? Theme.text : Theme.textMuted)
                        .lineLimit(1)
                    Spacer()
                    if unread {
                        Text("\(chat.unread ?? 0)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Theme.accent))
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var preview: String {
        guard let text = chat.lastMessageText else { return "No messages yet" }
        if chat.isGroup == true, let sender = chat.lastSender, sender != "You" {
            return "\(sender): \(text)"
        }
        return text
    }

    private var timeLabel: String {
        guard let d = chat.lastMessageAt else { return "" }
        let cal = Calendar.current
        if cal.isDateInToday(d) { return d.formatted(date: .omitted, time: .shortened) }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        if let days = cal.dateComponents([.day], from: d, to: Date()).day, days < 7 {
            return d.formatted(.dateTime.weekday(.abbreviated))
        }
        return d.formatted(.dateTime.day().month(.abbreviated))
    }

    private var avatar: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let urlStr = chat.avatarUrl, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFill()
                        } else {
                            fallbackAvatar
                        }
                    }
                } else {
                    fallbackAvatar
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())
            // groups: who sent the latest message (Beeper-style); 1:1: network badge
            if isGroup {
                groupSenderChip
                    .overlay(Circle().stroke(Theme.bg, lineWidth: 2))
                    .offset(x: 3, y: 3)
            } else {
                channelBadge
                    .overlay(Circle().stroke(Theme.bg, lineWidth: 2))
                    .offset(x: 2, y: 2)
            }
        }
    }

    @ViewBuilder
    private var groupSenderChip: some View {
        Group {
            if let urlStr = senderAvatar, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase { img.resizable().scaledToFill() }
                    else { senderInitialChip }
                }
            } else {
                senderInitialChip
            }
        }
        .frame(width: 22, height: 22)
        .clipShape(Circle())
    }

    private var senderInitialChip: some View {
        Circle()
            .fill(senderColor)
            .overlay(
                Text(senderInitials)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            )
    }

    private var senderInitials: String {
        let n = (chat.lastSender == "You" ? "" : chat.lastSender) ?? ""
        let j = n.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
        return j.isEmpty ? "?" : j
    }

    private var senderColor: Color {
        let palette: [UInt32] = [0xA65468, 0x5E67A0, 0x3F8A7E, 0x4A6D9C, 0xA9803F, 0x7E5EA0, 0x5E8AA0]
        let key = chat.lastSenderJid ?? chat.lastSender ?? chat.jid
        return Color(hex: palette[abs(key.hashValue) % palette.count])
    }

    @ViewBuilder
    private var channelBadge: some View {
        switch chat.channel {
        case .whatsapp:
            Image("WhatsAppBadge")
                .resizable()
                .frame(width: 18, height: 18)
                .background(Circle().fill(.white))
        case .imessage:
            Circle()
                .fill(Theme.imessage)
                .frame(width: 18, height: 18)
                .overlay(Image(systemName: "bubble.left.fill").font(.system(size: 8)).foregroundStyle(.white))
        case .assistant:
            EmptyView()
        }
    }

    private var fallbackAvatar: some View {
        Circle()
            .fill(avatarColor)
            .overlay(
                chat.isGroup == true
                ? AnyView(Image(systemName: "person.2.fill").font(.system(size: 16)).foregroundStyle(.white))
                : AnyView(Text(initials).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.white))
            )
    }

    private var initials: String {
        chat.displayName.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    private var avatarColor: Color {
        // stable pastel from the jid
        let palette: [UInt32] = [0xA65468, 0x5E67A0, 0x3F8A7E, 0x4A6D9C, 0xA9803F, 0x7E5EA0, 0x5E8AA0]
        let idx = abs(chat.jid.hashValue) % palette.count
        return Color(hex: palette[idx])
    }
}

extension WAChat: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(jid) }
}

extension View {
    /// iOS 26 liquid glass search (bottom pill that minimizes); no-op earlier.
    @ViewBuilder
    func liquidGlassSearch() -> some View {
        if #available(iOS 26.0, *) {
            self.searchToolbarBehavior(.minimize)
        } else {
            self
        }
    }
}

/// A message-search hit: chat name + the matching line with the term emphasized.
struct MessageHitRow: View {
    let chat: WAChat
    let hit: WAMessage
    let query: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(chat.displayName)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Spacer()
                    Text(hit.ts.formatted(.dateTime.day().month(.abbreviated)))
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Theme.textFaint)
                }
                Text(highlighted)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var highlighted: AttributedString {
        var s = AttributedString((hit.senderName.map { $0 == "You" ? "You: " : "\($0): " } ?? "") + hit.text)
        if let r = s.range(of: query, options: .caseInsensitive) {
            s[r].foregroundColor = Theme.accent
            s[r].font = .system(size: 14, weight: .bold, design: .rounded)
        }
        return s
    }

    private var avatar: some View {
        Circle()
            .fill(Theme.surfaceAlt)
            .frame(width: 40, height: 40)
            .overlay(Text(initials).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(Theme.textMuted))
    }

    private var initials: String {
        chat.displayName.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }
}

/// The pinned Edwin row — visually distinct from real contacts.
struct AssistantRow: View {
    let chat: WAChat
    let draftCount: Int

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image("EdwinAvatar")
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Edwin").font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.text)
                    Text("Your assistant")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.accent.opacity(0.12)))
                    Spacer()
                    Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(Theme.textFaint)
                }
                Text(chat.lastMessageText ?? "ask me anything about your inbox")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
            }
            if draftCount > 0 {
                Text("\(draftCount)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Theme.accent))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Edwin, your assistant. \(draftCount) drafts awaiting approval.")
    }
}


/// Email row in the unified All Chats list — mirrors ChatRow's shape with an
/// envelope avatar so mail is scannable at a glance.
struct UnifiedEmailRow: View {
    let email: Email

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: 0xEA4335).opacity(0.12))
                .frame(width: 46, height: 46)
                .overlay(Image(systemName: "envelope.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Color(hex: 0xEA4335)))
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(email.sender)
                        .font(.system(size: 16, weight: email.unread ? .bold : .semibold, design: .rounded))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Spacer()
                    if let ts = email.ts {
                        Text(rowTime(ts))
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(email.unread ? Theme.accent : Theme.textFaint)
                    }
                }
                HStack(alignment: .top) {
                    Text(email.subject ?? "(no subject)")
                        .font(.system(size: 14, weight: email.unread ? .semibold : .regular, design: .rounded))
                        .foregroundStyle(email.unread ? Theme.text : Theme.textMuted)
                        .lineLimit(1)
                    Spacer()
                    if email.unread {
                        Circle().fill(Theme.accent).frame(width: 9, height: 9).padding(.top, 4)
                    }
                }
            }
        }
    }

    private func rowTime(_ d: Date) -> String {
        if Calendar.current.isDateInToday(d) { return d.formatted(date: .omitted, time: .shortened) }
        if Calendar.current.isDateInYesterday(d) { return "Yesterday" }
        return d.formatted(.dateTime.day().month(.abbreviated))
    }
}

import SwiftUI

struct InboxView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var wa: WAStore

    private var realChats: [WAChat] { wa.chats.filter { !$0.assistant } }

    var body: some View {
        NavigationStack {
            list
            .background(Theme.bg)
            .navigationTitle("Inbox")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text(greeting)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Theme.textMuted)
                }
                ToolbarItem(placement: .topBarTrailing) { statusChip }
            }
            .navigationDestination(for: WAChat.self) { chat in
                if chat.assistant { AssistantChatView(chat: chat) }
                else { ChatView(chat: chat) }
            }
        }
        .task {
            await wa.ensureAssistant()
            while !Task.isCancelled {
                await wa.refreshAccount()
                await wa.refreshChats()
                await wa.refreshDrafts()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    // live connection status — the bridge is always visible, never magic
    private var statusChip: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(wa.isConnected ? Theme.success : Theme.textFaint)
                .frame(width: 7, height: 7)
            Text(wa.isConnected ? "LIVE" : "OFFLINE")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(wa.isConnected ? Theme.success : Theme.textFaint)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(Theme.surface))
        .accessibilityLabel(wa.isConnected ? "WhatsApp connected" : "WhatsApp offline")
    }

    private var list: some View {
        List {
            // Edwin is always pinned at the very top
            if let edwin = wa.assistantChat {
                NavigationLink(value: edwin) {
                    AssistantRow(chat: edwin, draftCount: wa.drafts.count)
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
                .listRowSeparatorTint(Theme.border)
                .listRowBackground(Theme.accentSoft.opacity(0.35))
            }

            if realChats.isEmpty {
                Group {
                    if wa.isConnected { syncingRow } else { notConnectedRow }
                }
                .listRowSeparator(.hidden)
            } else {
                ForEach(realChats) { chat in
                    NavigationLink(value: chat) { ChatRow(chat: chat) }
                        .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                        .listRowSeparatorTint(Theme.border)
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await wa.refreshChats() }
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

    private var unread: Bool { (chat.unread ?? 0) > 0 }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(chat.displayName)
                        .font(.system(size: 16, weight: unread ? .bold : .semibold, design: .rounded))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Spacer()
                    Text(timeLabel)
                        .font(.system(size: 13, weight: unread ? .semibold : .regular, design: .rounded))
                        .foregroundStyle(unread ? Theme.accent : Theme.textFaint)
                }
                HStack(alignment: .center) {
                    Text(preview)
                        .font(.system(size: 15, design: .rounded))
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
            Circle()
                .fill(Theme.whatsapp)
                .frame(width: 18, height: 18)
                .overlay(Image(systemName: "message.fill").font(.system(size: 8)).foregroundStyle(.white))
                .overlay(Circle().stroke(Theme.bg, lineWidth: 2))
                .offset(x: 2, y: 2)
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

/// The pinned Edwin row — visually distinct from real contacts.
struct AssistantRow: View {
    let chat: WAChat
    let draftCount: Int

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(Theme.accent)
                .frame(width: 48, height: 48)
                .overlay(
                    Text("e").font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white).offset(y: -1)
                )
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Edwin").font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.text)
                    Text("YOUR ASSISTANT")
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

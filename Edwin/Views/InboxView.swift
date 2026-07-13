import SwiftUI

struct InboxView: View {
    @EnvironmentObject var auth: AuthStore
    @State private var threads = MockData.threads
    @State private var appearedRows = Set<String>()

    private var anyConnected: Bool { auth.whatsappConnected || auth.imessageConnected }

    var body: some View {
        NavigationStack {
            Group {
                if !anyConnected {
                    emptyNotConnected
                } else if threads.isEmpty {
                    emptyCaughtUp
                } else {
                    list
                }
            }
            .background(Theme.bg)
            .navigationTitle("Inbox")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(greeting)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(Theme.textMuted)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        // search later
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(Theme.textMuted)
                    }
                    .accessibilityLabel("Search messages")
                }
            }
        }
    }

    private var list: some View {
        List {
            ForEach(threads) { thread in
                ThreadRow(thread: thread)
                    .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
                    .listRowSeparatorTint(Theme.border)
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            toggleRead(thread)
                        } label: {
                            Label(thread.unread > 0 ? "Read" : "Unread",
                                  systemImage: thread.unread > 0 ? "envelope.open" : "envelope.badge")
                        }
                        .tint(Theme.accent)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            archive(thread)
                        } label: {
                            Label("Archive", systemImage: "archivebox")
                        }
                        .tint(Theme.textMuted)
                    }
            }
        }
        .listStyle(.plain)
        .refreshable {
            // real sync with the ingest pipeline goes here
            try? await Task.sleep(nanoseconds: 900_000_000)
        }
    }

    private var emptyNotConnected: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 18)
                .fill(Theme.accentSoft)
                .frame(width: 72, height: 72)
                .overlay(Image(systemName: "envelope.open").font(.system(size: 30, design: .rounded)).foregroundStyle(Theme.accent))
            Text("Your inbox is quiet")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.text)
            Text("Connect WhatsApp or iMessage and the chaos starts sorting itself out.")
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyCaughtUp: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(hex: 0xE7F8F0))
                .frame(width: 72, height: 72)
                .overlay(Image(systemName: "checkmark.circle").font(.system(size: 30, design: .rounded)).foregroundStyle(Theme.success))
            Text("You're all caught up")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.text)
            Text("Inbox zero, the easy way. Pull down if something new snuck in.")
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        let base = h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
        let first = auth.userName.components(separatedBy: " ").first ?? ""
        return first.isEmpty ? base : "\(base), \(first)"
    }

    private func toggleRead(_ thread: MessageThread) {
        UISelectionFeedbackGenerator().selectionChanged()
        if let i = threads.firstIndex(where: { $0.id == thread.id }) {
            threads[i].unread = threads[i].unread > 0 ? 0 : 1
        }
    }

    private func archive(_ thread: MessageThread) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation { threads.removeAll { $0.id == thread.id } }
    }
}

struct ThreadRow: View {
    let thread: MessageThread

    private var unread: Bool { thread.unread > 0 }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    if thread.priority == .high {
                        Circle().fill(Theme.danger).frame(width: 7, height: 7)
                    }
                    Text(thread.name)
                        .font(.system(size: 16, weight: unread ? .bold : .semibold, design: .rounded))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Spacer()
                    Text(thread.time)
                        .font(.system(size: 13, weight: unread ? .semibold : .regular, design: .rounded))
                        .foregroundStyle(unread ? Theme.accent : Theme.textFaint)
                }
                HStack(alignment: .center) {
                    Text(thread.preview)
                        .font(.system(size: 15, design: .rounded))
                        .foregroundStyle(unread ? Theme.text : Theme.textMuted)
                        .lineLimit(1)
                    Spacer()
                    if unread {
                        Text("\(thread.unread)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Theme.accent))
                    }
                }
                if let summary = thread.summary, thread.priority == .high {
                    HStack(spacing: 7) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Theme.accent.opacity(0.5))
                            .frame(width: 2)
                        Text(summary)
                            .font(.system(size: 12.5, design: .rounded))
                            .italic()
                            .foregroundStyle(Theme.textMuted)
                            .lineLimit(1)
                    }
                    .padding(.top, 2)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11yLabel)
    }

    private var avatar: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(thread.avatarColor)
                .frame(width: 48, height: 48)
                .overlay(
                    Text(initials)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                )
            Circle()
                .fill(thread.channel == .whatsapp ? Theme.whatsapp : Theme.imessage)
                .frame(width: 18, height: 18)
                .overlay(
                    Image(systemName: thread.channel == .whatsapp ? "message.fill" : "bubble.left.fill")
                        .font(.system(size: 8, design: .rounded))
                        .foregroundStyle(.white)
                )
                .overlay(Circle().stroke(Theme.bg, lineWidth: 2))
                .offset(x: 2, y: 2)
        }
    }

    private var initials: String {
        thread.name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    private var a11yLabel: String {
        var parts = ["\(thread.name), \(thread.channel == .whatsapp ? "WhatsApp" : "iMessage")."]
        if unread { parts.append("\(thread.unread) unread.") }
        if thread.priority == .high { parts.append("High priority.") }
        parts.append(thread.preview)
        if let s = thread.summary { parts.append("Summary: \(s)") }
        return parts.joined(separator: " ")
    }
}

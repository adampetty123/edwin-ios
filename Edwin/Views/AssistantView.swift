import SwiftUI

/// The pinned chat with Edwin, your assistant. Same bubble language as a real
/// chat, but replies stay internal and Edwin's drafts surface as approve cards.
struct AssistantChatView: View {
    @EnvironmentObject var wa: WAStore
    let chat: WAChat

    @State private var draft = ""
    @State private var thinking = false

    private var msgs: [WAMessage] { wa.messages[WAClient.assistantJid] ?? [] }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(Array(msgs.enumerated()), id: \.element.id) { i, m in
                        if showDay(at: i) { DaySeparator(date: m.ts) }
                        MessageBubble(message: m, isGroup: false)
                            .id(m.id)
                    }
                    if thinking {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("edwin is thinking\u{2026}")
                                .font(.system(size: 13, design: .rounded))
                                .foregroundStyle(Theme.textMuted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                        .id("thinking")
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: msgs.count) {
                thinking = false
                if let last = msgs.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
        .background(Theme.bg)
        .navigationTitle("Edwin")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if !wa.drafts.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(wa.drafts) { d in DraftCard(draft: d) }
                        }
                        .padding(.horizontal, 12)
                    }
                }
                composer
            }
            .background(Theme.bg)
        }
        .task {
            await wa.markRead(chatJid: chat.jid)
            while !Task.isCancelled {
                await wa.refreshMessages(chatJid: WAClient.assistantJid)
                await wa.refreshDrafts()
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
        }
    }

    private func showDay(at i: Int) -> Bool {
        guard i > 0 else { return true }
        return !Calendar.current.isDate(msgs[i].ts, inSameDayAs: msgs[i - 1].ts)
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Message Edwin", text: $draft, axis: .vertical)
                .font(.system(size: 16, design: .rounded))
                .lineLimit(1...4)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 20).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.border, lineWidth: 1))
            Button { send() } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(draft.trimmingCharacters(in: .whitespaces).isEmpty ? Theme.border : Theme.accent))
            }
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 12).padding(.bottom, 8)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        thinking = true
        Task {
            try? await wa.sendToAssistant(text: text)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            await wa.refreshMessages(chatJid: WAClient.assistantJid)
        }
    }
}

/// An approve/edit/dismiss card for a reply Edwin drafted to a real contact.
struct DraftCard: View {
    @EnvironmentObject var wa: WAStore
    let draft: AssistantDraft

    @State private var editing = false
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "paperplane.fill").font(.system(size: 11)).foregroundStyle(Theme.accent)
                Text("DRAFT TO \(draft.chatName?.uppercased() ?? "CONTACT")")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
            }
            if let reason = draft.reason, !reason.isEmpty {
                Text(reason)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(2)
            }
            if editing {
                TextField("Edit", text: $text, axis: .vertical)
                    .font(.system(size: 15, design: .rounded))
                    .lineLimit(2...5)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.bg))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
            } else {
                Text(draft.text)
                    .font(.system(size: 15, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button {
                    Task { await wa.approveDraft(draft, editedText: editing ? text : nil) }
                } label: {
                    Text(editing ? "Send edit" : "Approve & send")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(Theme.accent))
                }
                Button { editing.toggle(); text = draft.text } label: {
                    Image(systemName: editing ? "xmark" : "pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textMuted)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Theme.surface))
                }
                Button { Task { await wa.dismissDraft(draft) } } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textFaint)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Theme.surface))
                }
            }
        }
        .padding(12)
        .frame(width: 270, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.accent.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
    }
}

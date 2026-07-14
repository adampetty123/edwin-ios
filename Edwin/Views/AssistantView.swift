import SwiftUI
import PhotosUI

/// The pinned chat with Edwin, your assistant. Same bubble language as a real
/// chat, but replies stay internal and Edwin's drafts surface as approve cards.
struct AssistantChatView: View {
    @EnvironmentObject var wa: WAStore
    let chat: WAChat

    @State private var draft = ""
    @State private var thinking = false
    @State private var pickedItem: PhotosPickerItem?
    @State private var pickedImage: Data?

    private var msgs: [WAMessage] { wa.messages[WAClient.assistantJid] ?? [] }

    /// Typing shows for a queued/in-flight backend job (covers jobs started
    /// anywhere) OR the optimistic local flag right after hitting send.
    private var showTyping: Bool { thinking || wa.assistantBusy }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(Array(msgs.enumerated()), id: \.element.id) { i, m in
                        if showDay(at: i) { DaySeparator(date: m.ts) }
                        MessageBubble(message: m, isGroup: false)
                            .id(m.id)
                    }
                    if showTyping {
                        TypingBubble()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 2)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                            .id("thinking")
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: msgs.count) {
                // only Edwin's reply ends the typing state — our own echoed
                // message must NOT kill the indicator (the old bug)
                if msgs.last?.fromMe == false { withAnimation { thinking = false } }
                if let last = msgs.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
            .onChange(of: wa.assistantBusy) {
                // backend job finished — clear the local optimistic flag too
                if !wa.assistantBusy { withAnimation { thinking = false } }
            }
            .onChange(of: showTyping) {
                if showTyping { withAnimation { proxy.scrollTo("thinking", anchor: .bottom) } }
            }
        }
        .background(Theme.bg)
        .navigationTitle("Edwin")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
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
            .background(.ultraThinMaterial)
        }
        .task {
            await wa.markRead(chatJid: chat.jid)
            while !Task.isCancelled {
                await wa.refreshMessages(chatJid: WAClient.assistantJid)
                await wa.refreshDrafts()
                await wa.refreshAssistantBusy()
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
        }
    }

    private func showDay(at i: Int) -> Bool {
        guard i > 0 else { return true }
        return !Calendar.current.isDate(msgs[i].ts, inSameDayAs: msgs[i - 1].ts)
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if let data = pickedImage, let ui = UIImage(data: data) {
                HStack {
                    Image(uiImage: ui)
                        .resizable().scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Text("Attached").font(.system(size: 13, design: .rounded)).foregroundStyle(Theme.textMuted)
                    Spacer()
                    Button { pickedImage = nil; pickedItem = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textFaint)
                    }
                }
                .padding(.horizontal, 12)
            }
            composerBar
        }
    }

    private var composerBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            PhotosPicker(selection: $pickedItem, matching: .images) {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 44, height: 44)
                    .liquidGlassCircle()
            }
            .onChange(of: pickedItem) {
                Task {
                    if let item = pickedItem,
                       let data = try? await item.loadTransferable(type: Data.self),
                       let ui = UIImage(data: data) {
                        // recompress to keep uploads light
                        pickedImage = ui.jpegData(compressionQuality: 0.75)
                    }
                }
            }
            TextField("Message Edwin", text: $draft, axis: .vertical)
                .font(.system(size: 16, design: .rounded))
                .lineLimit(1...4)
                .padding(.horizontal, 16).padding(.vertical, 13)
                .liquidGlassField()
            Button { send() } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(draft.trimmingCharacters(in: .whitespaces).isEmpty && pickedImage == nil ? Theme.border : Theme.accent))
            }
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty && pickedImage == nil)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let image = pickedImage
        guard !text.isEmpty || image != nil else { return }
        draft = ""
        pickedImage = nil
        pickedItem = nil
        withAnimation { thinking = true }
        Task {
            do {
                try await wa.sendToAssistant(text: text, imageData: image)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                await wa.refreshMessages(chatJid: WAClient.assistantJid)
                await wa.refreshAssistantBusy()
            } catch {
                withAnimation { thinking = false }
            }
        }
    }
}

/// iMessage-style typing indicator: three dots bouncing inside Edwin's bubble.
struct TypingBubble: View {
    @State private var phase = 0
    private let timer = Timer.publish(every: 0.28, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Theme.textMuted)
                    .frame(width: 8, height: 8)
                    .scaleEffect(phase == i ? 1.0 : 0.55)
                    .opacity(phase == i ? 1.0 : 0.45)
                    .animation(.easeInOut(duration: 0.28), value: phase)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.bubbleThem))
        .onReceive(timer) { _ in phase = (phase + 1) % 3 }
        .accessibilityLabel("Edwin is typing")
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

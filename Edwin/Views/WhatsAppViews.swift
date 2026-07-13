import SwiftUI

// MARK: - Connect WhatsApp (real pairing, Beeper-style)

struct ConnectWhatsAppView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var wa: WAStore

    let stepIndex: Int
    let onDone: () -> Void
    let onSkip: () -> Void

    @State private var phone = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var phoneFocused: Bool

    private var status: String { wa.account?.status ?? "" }
    private var showCode: Bool { status == "pairing" && wa.account?.pairingCode != nil }
    private var connected: Bool { status == "connected" }
    private var starting: Bool { status == "pending_pair" || status == "starting" || (status == "pairing" && wa.account?.pairingCode == nil) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    iconTile.padding(.top, 20).padding(.bottom, 20)

                    Text("CONNECT WHATSAPP")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .kerning(0.5)
                        .foregroundStyle(Theme.accent)
                        .padding(.bottom, 8)

                    if connected {
                        connectedBlock
                    } else if showCode {
                        codeBlock
                    } else {
                        phoneBlock
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, 24)
        .background(Theme.bg)
        .task {
            while !Task.isCancelled {
                await wa.refreshAccount()
                if wa.isConnected { break }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    // MARK: sections

    private var phoneBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Link your WhatsApp.")
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.text)
            Text("Enter the number your WhatsApp is registered to. Edwin gives you a code — you type it into WhatsApp, and your chats start flowing in.")
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(Theme.textMuted)
                .lineSpacing(4)

            LabeledField(label: "WhatsApp phone number", text: $phone, placeholder: "+1 555 123 4567", error: error)
                .keyboardType(.phonePad)
                .focused($phoneFocused)
                .padding(.top, 14)

            trustRow.padding(.top, 12)
        }
    }

    private var codeBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your pairing code.")
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.text)

            // the code — big, monospace, tappable to copy
            Button {
                UIPasteboard.general.string = wa.account?.pairingCode?.replacingOccurrences(of: "-", with: "")
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } label: {
                HStack {
                    Spacer()
                    Text(wa.account?.pairingCode ?? "")
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .kerning(2)
                        .foregroundStyle(Theme.text)
                    Spacer()
                }
                .padding(.vertical, 18)
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border, lineWidth: 1))
            }
            .accessibilityLabel("Pairing code \(wa.account?.pairingCode ?? ""). Tap to copy.")

            VStack(alignment: .leading, spacing: 12) {
                stepRow(n: "1", text: "Open WhatsApp on this phone", done: true)
                stepRow(n: "2", text: "Settings → Linked Devices → Link a Device", done: false)
                stepRow(n: "3", text: "Tap \"Link with phone number instead\" and enter the code", done: false)
            }
            .padding(.top, 4)

            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("WAITING FOR LINK")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(.top, 6)
        }
    }

    private var connectedBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connected.")
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.text)
            if let name = wa.account?.waName, !name.isEmpty {
                Text("Linked as \(name).")
                    .font(.system(size: 16, design: .rounded))
                    .foregroundStyle(Theme.textMuted)
            }
            HStack(spacing: 14) {
                syncStat(value: wa.account?.chatsSynced ?? 0, label: "chats")
                syncStat(value: wa.account?.messagesSynced ?? 0, label: "messages")
            }
            Text("History is still streaming in — your inbox fills up over the next minute or two.")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(Theme.textFaint)
        }
    }

    private func syncStat(value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.accent)
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textMuted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
    }

    private func stepRow(n: String, text: String, done: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(done ? Theme.success : Theme.accentSoft)
                .frame(width: 22, height: 22)
                .overlay(
                    done
                    ? AnyView(Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white))
                    : AnyView(Text(n).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(Theme.accent))
                )
            Text(text)
                .font(.system(size: 15, design: .rounded))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var trustRow: some View {
        Text("Your WhatsApp · Your data · Nothing sends without your ok")
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.textFaint)
    }

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(0..<2) { i in
                    Capsule()
                        .fill(i <= stepIndex ? Theme.accent : Theme.border)
                        .frame(width: i <= stepIndex ? 22 : 8, height: 8)
                }
            }
            Spacer()
            if !connected {
                Button("Skip", action: onSkip)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .padding(.top, 12)
    }

    private var iconTile: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 18)
                .fill(Theme.whatsapp.opacity(0.1))
                .frame(width: 80, height: 80)
                .overlay(Image(systemName: "message.fill").font(.system(size: 36)).foregroundStyle(Theme.whatsapp))
            if connected {
                Circle()
                    .fill(Theme.success)
                    .frame(width: 28, height: 28)
                    .overlay(Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white))
                    .overlay(Circle().stroke(Theme.bg, lineWidth: 3))
                    .offset(x: 6, y: 6)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            if let err = wa.account?.error, status == "error" || status == "disconnected" {
                Text(err)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Theme.danger)
            }
            if connected {
                Button { onDone() } label: { Text("Continue") }
                    .buttonStyle(PrimaryButtonStyle())
            } else if showCode || starting {
                Button {} label: {
                    HStack(spacing: 8) {
                        if starting { ProgressView().tint(.white) }
                        Text(starting ? "Generating code…" : "Enter the code in WhatsApp")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(true)
                .opacity(0.8)
            } else {
                Button { submit() } label: {
                    if busy { ProgressView().tint(.white) } else { Text("Get pairing code") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy || phone.trimmingCharacters(in: .whitespaces).count < 7)
            }
        }
        .padding(.bottom, 16)
    }

    private func submit() {
        error = nil
        let digits = phone.filter(\.isNumber)
        guard digits.count >= 7 else { error = "That number looks short — include your country code."; return }
        busy = true
        Task {
            do { try await wa.requestPairing(phone: digits) }
            catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}

// MARK: - Chat view (real messages + approve-to-send composer)

struct ChatView: View {
    @EnvironmentObject var wa: WAStore
    let chat: WAChat

    @State private var draft = ""
    @State private var sendState: SendState = .idle
    enum SendState: Equatable { case idle, queued, failed(String) }

    private var msgs: [WAMessage] { wa.messages[chat.jid] ?? [] }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(msgs) { m in
                        MessageBubble(message: m, isGroup: chat.isGroup ?? false)
                            .id(m.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: msgs.count) {
                if let last = msgs.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
        .background(Theme.bg)
        .navigationTitle(chat.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { composer }
        .task {
            while !Task.isCancelled {
                await wa.refreshMessages(chatJid: chat.jid)
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if case .failed(let why) = sendState {
                Text(why)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Theme.danger)
            } else if sendState == .queued {
                Text("Queued — sending via your WhatsApp…")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
            }
            HStack(spacing: 10) {
                TextField("Message", text: $draft, axis: .vertical)
                    .font(.system(size: 16, design: .rounded))
                    .lineLimit(1...4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 20).fill(Theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.border, lineWidth: 1))
                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(draft.trimmingCharacters(in: .whitespaces).isEmpty ? Theme.border : Theme.accent))
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Send")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.bg)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        sendState = .queued
        Task {
            do {
                try await wa.send(chatJid: chat.jid, text: text)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                await wa.refreshMessages(chatJid: chat.jid)
                sendState = .idle
            } catch {
                sendState = .failed("Didn't send — \(error.localizedDescription)")
            }
        }
    }
}

struct MessageBubble: View {
    let message: WAMessage
    let isGroup: Bool

    var body: some View {
        HStack {
            if message.fromMe { Spacer(minLength: 48) }
            VStack(alignment: .leading, spacing: 3) {
                if isGroup, !message.fromMe, let sender = message.senderName {
                    Text(sender)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.accent)
                }
                Text(message.text)
                    .font(.system(size: 16, design: .rounded))
                    .foregroundStyle(message.fromMe ? .white : Theme.text)
                Text(message.ts.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundStyle(message.fromMe ? .white.opacity(0.7) : Theme.textFaint)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(message.fromMe ? Theme.accent : Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(message.fromMe ? .clear : Theme.border, lineWidth: 1)
            )
            if !message.fromMe { Spacer(minLength: 48) }
        }
        .frame(maxWidth: .infinity, alignment: message.fromMe ? .trailing : .leading)
    }
}

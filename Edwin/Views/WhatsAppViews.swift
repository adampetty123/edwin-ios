import SwiftUI
import AVKit

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

                    Text("Connect WhatsApp")
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
                Text("Waiting for link")
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
            Text(label)
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

// MARK: - Chat view: media, replies, reactions, receipts — the full experience

struct ChatView: View {
    @EnvironmentObject var wa: WAStore
    let chat: WAChat

    @State private var draft = ""
    @State private var replyingTo: WAMessage?
    @State private var sendState: SendState = .idle
    @State private var openedAtBottom = false
    @StateObject private var memo = VoiceMemo()
    enum SendState: Equatable { case idle, queued, failed(String) }

    private var msgs: [WAMessage] { wa.messages[chat.jid] ?? [] }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(Array(msgs.enumerated()), id: \.element.id) { i, m in
                        if showDay(at: i) {
                            DaySeparator(date: m.ts)
                        }
                        MessageBubble(
                            message: m,
                            isGroup: chat.isGroup ?? false,
                            showSender: showSender(at: i),
                            senderAvatarUrl: senderAvatar(m),
                            isLastOutgoing: m.fromMe && m.id == msgs.last(where: { $0.fromMe })?.id
                        )
                            .id(m.id)
                            // order matters: double-tap and swipe INSIDE, context
                            // menu OUTERMOST — a tap gesture registered after
                            // .contextMenu starves the system long-press, which
                            // is why the hold menu never appeared on device.
                            .onTapGesture(count: 2) { quickHeart(m) }
                            .swipeToReply { withAnimation(.snappy) { replyingTo = m } }
                            .contextMenu { contextMenu(for: m) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                // cached messages: count never "changes" on open, so jump here too
                if !openedAtBottom { openAtLatest(proxy) }
            }
            .onChange(of: msgs.count) {
                if !openedAtBottom {
                    openAtLatest(proxy)
                } else if let last = msgs.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
                // messages that arrive while the chat is open are read too
                Task { await wa.markRead(chatJid: chat.jid) }
            }
        }
        .background(Theme.bg)
        .navigationTitle(chat.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // pfp + name in the chat header, like WhatsApp / iMessage
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    PfpAvatar(name: chat.displayName, jid: chat.jid,
                              urlString: chat.avatarUrl, isGroup: chat.isGroup ?? false, size: 30)
                    Text(chat.displayName)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .onDisappear {
            // leaving the chat clears the pill instantly, no waiting on the poll
            Task { await wa.markRead(chatJid: chat.jid) }
        }
        .safeAreaInset(edge: .bottom) { composer }
        .task {
            await wa.markRead(chatJid: chat.jid)
            if chat.isGroup == true { await wa.refreshSenderAvatars() }
            while !Task.isCancelled {
                await wa.refreshMessages(chatJid: chat.jid)
                try? await Task.sleep(nanoseconds: wa.realtime.connected ? 15_000_000_000 : 3_000_000_000)
            }
        }
    }

    /// Open the chat pinned to the newest message — never to the first unread.
    /// Lazy rows and media size in after first layout and drift the offset
    /// (this is what dropped you mid-chat at your last read position), so we
    /// re-pin a couple of times right after opening. No animation: the chat
    /// should just BE at the bottom.
    private func openAtLatest(_ proxy: ScrollViewProxy) {
        guard let last = msgs.last else { return }
        openedAtBottom = true
        proxy.scrollTo(last.id, anchor: .bottom)
        for delay in [0.05, 0.3] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private func showDay(at i: Int) -> Bool {
        guard i > 0 else { return true }
        return !Calendar.current.isDate(msgs[i].ts, inSameDayAs: msgs[i - 1].ts)
    }

    /// First message of a same-sender run (or after a day break) carries the
    /// sender pfp + name; the rest of the run stays clean.
    private func showSender(at i: Int) -> Bool {
        guard i > 0 else { return true }
        let prev = msgs[i - 1], m = msgs[i]
        if prev.fromMe != m.fromMe { return true }
        if (prev.senderJid ?? prev.senderName) != (m.senderJid ?? m.senderName) { return true }
        return !Calendar.current.isDate(m.ts, inSameDayAs: prev.ts)
    }

    /// Group senders: dedicated sender-avatar store first (covers lid ids and
    /// people with no DM chat), then their DM chat row as fallback.
    private func senderAvatar(_ m: WAMessage) -> String? {
        guard let sj = m.senderJid, sj != "me" else { return nil }
        return wa.senderAvatars[sj] ?? wa.chats.first(where: { $0.jid == sj })?.avatarUrl
    }

    @ViewBuilder
    private func contextMenu(for m: WAMessage) -> some View {
        Button { replyingTo = m } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
        Button { UIPasteboard.general.string = m.text } label: { Label("Copy", systemImage: "doc.on.doc") }
        Menu {
            ForEach(["\u{2764}\u{FE0F}", "\u{1F44D}", "\u{1F602}", "\u{1F62E}", "\u{1F622}", "\u{1F64F}"], id: \.self) { e in
                Button(e) { react(m, emoji: e) }
            }
            Button("Remove reaction") { react(m, emoji: "") }
        } label: { Label("React", systemImage: "face.smiling") }
    }

    private func quickHeart(_ m: WAMessage) {
        guard !m.fromMe else { return }
        react(m, emoji: "\u{2764}\u{FE0F}")
    }

    private func react(_ m: WAMessage, emoji: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            await wa.react(chatJid: chat.jid, msgId: m.msgId, emoji: emoji)
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await wa.refreshMessages(chatJid: chat.jid)
        }
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if let r = replyingTo {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1.5).fill(Theme.accent).frame(width: 3, height: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.fromMe ? "You" : (r.senderName ?? chat.displayName))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.accent)
                        Text(r.text).font(.system(size: 13, design: .rounded))
                            .foregroundStyle(Theme.textMuted).lineLimit(1)
                    }
                    Spacer()
                    Button { replyingTo = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textFaint)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
            }
            if case .failed(let why) = sendState {
                Text(why).font(.system(size: 12, design: .rounded)).foregroundStyle(Theme.danger)
            } else if sendState == .queued {
                Text("Sending via your WhatsApp\u{2026}")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
            }
            if memo.recording {
                HStack(spacing: 8) {
                    Circle().fill(Theme.danger).frame(width: 8, height: 8)
                    Text("recording \(Int(memo.elapsed))s — tap ■ when you're done")
                        .font(.system(size: 12.5, design: .rounded))
                        .foregroundStyle(Theme.textMuted)
                    Spacer()
                    Button("cancel") { memo.cancel() }
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textFaint)
                }
                .padding(.horizontal, 4)
            }
            if let err = memo.error {
                Text(err)
                    .font(.system(size: 12.5, design: .rounded))
                    .foregroundStyle(Theme.danger)
                    .padding(.horizontal, 4)
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField(memo.recording ? "recording… tap ■ when done" : (memo.transcribing ? "transcribing…" : "Message"),
                          text: $draft, axis: .vertical)
                    .font(.system(size: 16, design: .rounded))
                    .lineLimit(1...4)
                    .padding(.horizontal, 16).padding(.vertical, 13)
                    .liquidGlassField()
                    .disabled(memo.recording || memo.transcribing)
                if draft.trimmingCharacters(in: .whitespaces).isEmpty {
                    // voice: tap to record, tap ■ to transcribe into the draft
                    // (transcript lands in the field so you can check it before sending)
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        Task {
                            if memo.recording {
                                if let transcript = await memo.stopAndTranscribe() {
                                    draft = transcript
                                }
                            } else {
                                _ = await memo.start()
                            }
                        }
                    } label: {
                        Group {
                            if memo.transcribing {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: memo.recording ? "stop.fill" : "mic.fill")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(memo.recording ? Theme.danger : Theme.bubbleMe))
                    }
                    .disabled(memo.transcribing)
                    .accessibilityLabel(memo.recording ? "Stop recording" : "Record voice message")
                } else {
                    Button { send() } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Theme.accent))
                    }
                    .accessibilityLabel("Send")
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let reply = replyingTo?.msgId
        draft = ""
        replyingTo = nil
        sendState = .queued
        Task {
            do {
                try await wa.send(chatJid: chat.jid, text: text, replyTo: reply)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                await wa.refreshMessages(chatJid: chat.jid)
                sendState = .idle
            } catch {
                sendState = .failed("Didn't send \u{2014} \(error.localizedDescription)")
            }
        }
    }
}

/// WhatsApp-style swipe-to-reply. A SwiftUI DragGesture — even
/// simultaneousGesture — loses reliably to the ScrollView's own pan on device,
/// so this drives the offset from a real UIPanGestureRecognizer whose delegate
/// (a) recognizes simultaneously with the scroll view and (b) only begins when
/// the drag is mostly horizontal and rightward. That combination actually fires.
private struct SwipeToReply: ViewModifier {
    let onReply: () -> Void

    @State private var offsetX: CGFloat = 0
    @State private var armed = false

    private let trigger: CGFloat = 52
    private let maxDrag: CGFloat = 74

    func body(content: Content) -> some View {
        content
            .offset(x: offsetX)
            .background(alignment: .leading) {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(armed ? Theme.accent : Theme.textFaint)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Theme.surface))
                    .opacity(min(1, Double(offsetX / trigger)))
                    .scaleEffect(armed ? 1.0 : 0.75)
                    .animation(.snappy(duration: 0.18), value: armed)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 18, coordinateSpace: .local)
                    .onChanged { v in
                        guard v.translation.width > 0,
                              abs(v.translation.width) > abs(v.translation.height) * 1.2 else {
                            if offsetX != 0 { offsetX = 0; armed = false }
                            return
                        }
                        let x = v.translation.width
                        offsetX = x < trigger ? x : trigger + (x - trigger) * 0.25
                        if offsetX > maxDrag { offsetX = maxDrag }
                        let nowArmed = offsetX >= trigger
                        if nowArmed != armed {
                            armed = nowArmed
                            if nowArmed { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
                        }
                    }
                    .onEnded { _ in
                        let fire = armed
                        withAnimation(.snappy(duration: 0.25)) { offsetX = 0 }
                        armed = false
                        if fire { onReply() }
                    }
            )
    }
}

extension View {
    func swipeToReply(_ onReply: @escaping () -> Void) -> some View {
        modifier(SwipeToReply(onReply: onReply))
    }
}

/// Inline video bubble: real thumbnail (generated on-device from the remote
/// file — the server stores no separate thumb) with a play button. Tapping
/// plays right there in the chat, no fullscreen bounce; scrolling away stops
/// it and puts the preview back.
struct InlineVideoView: View {
    let url: URL
    var fromMe: Bool = false
    @State private var thumb: UIImage?
    @State private var videoSize: CGSize?
    @State private var durationText: String?
    @State private var playing = false
    @State private var player = AVPlayer()

    private var size: CGSize {
        let w: CGFloat = 230
        guard let s = videoSize, s.width > 0 else { return CGSize(width: w, height: 150) }
        let h = w * s.height / s.width
        return CGSize(width: w, height: min(max(h, 110), 300))
    }

    var body: some View {
        ZStack {
            if playing {
                VideoPlayer(player: player)
            } else {
                if let thumb {
                    Image(uiImage: thumb).resizable().scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(fromMe ? Color.white.opacity(0.2) : Theme.surfaceAlt)
                }
                Button {
                    player.replaceCurrentItem(with: AVPlayerItem(url: url))
                    player.play()
                    withAnimation(.snappy) { playing = true }
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(15)
                        .background(Circle().fill(.black.opacity(0.55)))
                }
                if let durationText {
                    Text(durationText)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(.black.opacity(0.55)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(6)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .task { await loadMeta() }
        .onDisappear { player.pause(); playing = false }
    }

    private func loadMeta() async {
        let asset = AVURLAsset(url: url)
        if let tracks = try? await asset.loadTracks(withMediaType: .video),
           let track = tracks.first,
           let s = try? await track.load(.naturalSize) {
            videoSize = s
        }
        if let d = try? await asset.load(.duration), d.seconds.isFinite, d.seconds > 0 {
            let total = Int(d.seconds.rounded())
            durationText = String(format: "%d:%02d", total / 60, total % 60)
        }
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 460, height: 600)
        if let (cg, _) = try? await gen.image(at: .zero) {
            thumb = UIImage(cgImage: cg)
        }
    }
}

/// In-app playback for videos and voice notes — no more bouncing to Safari.
struct MediaPlayerScreen: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var player = AVPlayer()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: player)
                .ignoresSafeArea()
            Button {
                player.pause()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(Circle().fill(.black.opacity(0.55)))
            }
            .padding(.top, 8).padding(.trailing, 16)
        }
        .onAppear {
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            player.play()
        }
        .onDisappear { player.pause() }
    }
}

struct DaySeparator: View {
    let date: Date

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.textMuted)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(Capsule().fill(Theme.surface))
            .padding(.vertical, 8)
    }

    private var label: String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }
}

/// Small circular profile picture with a stable-colored initials fallback.
struct PfpAvatar: View {
    let name: String
    let jid: String
    let urlString: String?
    var isGroup: Bool = false
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                    } else {
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var fallback: some View {
        Circle()
            .fill(color)
            .overlay(
                isGroup
                ? AnyView(Image(systemName: "person.2.fill")
                    .font(.system(size: size * 0.4)).foregroundStyle(.white))
                : AnyView(Text(initials)
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white))
            )
    }

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }
        let joined = parts.joined().uppercased()
        return joined.isEmpty ? "#" : joined
    }

    private var color: Color {
        // stable across launches (hashValue is seed-randomized; unicode sum is not)
        let palette: [UInt32] = [0xA65468, 0x5E67A0, 0x3F8A7E, 0x4A6D9C, 0xA9803F, 0x7E5EA0, 0x5E8AA0]
        let sum = jid.unicodeScalars.reduce(0) { $0 &+ UInt32($1.value) }
        return Color(hex: palette[Int(sum % UInt32(palette.count))])
    }
}

struct MessageBubble: View {
    let message: WAMessage
    let isGroup: Bool
    var showSender: Bool = true
    var senderAvatarUrl: String? = nil
    var isLastOutgoing: Bool = false

    @State private var playingMedia: PlayableMedia?

    struct PlayableMedia: Identifiable {
        let id = UUID()
        let url: URL
    }

    /// Incoming group messages get a pfp gutter; first-of-run shows the pfp,
    /// the rest keep a clear spacer so bubbles stay aligned.
    private var showsAvatarGutter: Bool { isGroup && !message.fromMe }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.fromMe { Spacer(minLength: 48) }
            if showsAvatarGutter {
                if showSender {
                    PfpAvatar(name: message.senderName ?? "?",
                              jid: message.senderJid ?? (message.senderName ?? "?"),
                              urlString: senderAvatarUrl, size: 28)
                        .padding(.top, 2)
                } else {
                    Color.clear.frame(width: 28, height: 1)
                }
            }
            VStack(alignment: message.fromMe ? .trailing : .leading, spacing: 2) {
                bubble
                if let reactions = message.reactions, !reactions.isEmpty {
                    reactionPills(reactions)
                        .offset(y: -6)
                        .padding(.bottom, -6)
                }
                meta
            }
            if !message.fromMe { Spacer(minLength: 48) }
        }
        .frame(maxWidth: .infinity, alignment: message.fromMe ? .trailing : .leading)
    }

    /// Time under the bubble; the last outgoing message carries the receipt
    /// spelled out — "Seen at 14:32" / "Delivered at 14:32" — like iMessage.
    private var meta: some View {
        HStack(spacing: 3) {
            Text(message.ts.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 10.5, design: .rounded))
            if message.fromMe, let label = receiptLabel {
                Text("· \(label)")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(message.status == "read" ? Theme.accent : Theme.textFaint)
            } else if message.fromMe {
                Image(systemName: ticksIcon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(message.status == "read" ? Theme.bubbleMe : Theme.textFaint)
            }
        }
        .foregroundStyle(Theme.textFaint)
        .padding(.horizontal, 4)
    }

    /// Spelled-out receipt for the newest outgoing message only.
    private var receiptLabel: String? {
        guard isLastOutgoing else { return nil }
        let when = message.statusAt.map { " at " + $0.formatted(date: .omitted, time: .shortened) } ?? ""
        switch message.status {
        case "read": return "Seen\(when)"
        case "delivered": return "Delivered\(when)"
        default: return nil
        }
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isGroup, !message.fromMe, showSender, let sender = message.senderName {
                Text(sender)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.accent)
            }
            if let qt = message.quotedText, !qt.isEmpty {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(message.fromMe ? .white.opacity(0.6) : Theme.accent)
                        .frame(width: 3)
                    VStack(alignment: .leading, spacing: 1) {
                        if let qs = message.quotedSender {
                            Text(qs).font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(message.fromMe ? .white.opacity(0.9) : Theme.accent)
                        }
                        Text(qt).font(.system(size: 12.5, design: .rounded))
                            .foregroundStyle(message.fromMe ? .white.opacity(0.75) : Theme.textMuted)
                            .lineLimit(2)
                    }
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(message.fromMe ? .white.opacity(0.14) : Theme.surfaceAlt))
            }
            mediaView
            if showText {
                Text(message.text)
                    .font(.system(size: 16, design: .rounded))
                    .foregroundStyle(message.fromMe ? .white : Theme.text)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 18).fill(message.fromMe ? Theme.bubbleMe : Theme.bubbleThem))
    }

    private var showText: Bool {
        // hide the "[photo]" placeholder once real media renders
        if message.mediaUrl != nil, message.text.hasPrefix("["), message.text.hasSuffix("]") { return false }
        return !message.text.isEmpty
    }

    private var ticksIcon: String {
        switch message.status {
        case "read", "delivered": return "checkmark.circle.fill"
        default: return "checkmark.circle"
        }
    }

    @ViewBuilder
    private var mediaView: some View {
        if let urlStr = message.mediaUrl, let url = URL(string: urlStr) {
            switch message.mediaType {
            case "image", "sticker":
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                            .frame(maxWidth: 230, maxHeight: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    case .failure:
                        mediaChip(icon: "photo", label: "Photo")
                    default:
                        RoundedRectangle(cornerRadius: 12)
                            .fill(message.fromMe ? .white.opacity(0.2) : Theme.surfaceAlt)
                            .frame(width: 200, height: 140)
                            .overlay(ProgressView())
                    }
                }
            case "video":
                InlineVideoView(url: url, fromMe: message.fromMe)
            case "audio":
                Button { playingMedia = PlayableMedia(url: url) } label: {
                    mediaChip(icon: "waveform", label: "Voice message")
                }
                .fullScreenCover(item: $playingMedia) { m in MediaPlayerScreen(url: m.url) }
            case "document":
                Link(destination: url) { mediaChip(icon: "doc.fill", label: "Document") }
            default:
                EmptyView()
            }
        }
    }

    private func mediaChip(icon: String, label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 18))
            Text(label).font(.system(size: 15, weight: .medium, design: .rounded))
        }
        .foregroundStyle(message.fromMe ? .white : Theme.accent)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(message.fromMe ? .white.opacity(0.14) : Theme.surfaceAlt))
    }

    private func reactionPills(_ reactions: [WAReaction]) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(Set(reactions.map(\.emoji))).sorted(), id: \.self) { e in
                let n = reactions.filter { $0.emoji == e }.count
                Text(n > 1 ? "\(e)\(n)" : e)
                    .font(.system(size: 12, design: .rounded))
            }
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(Theme.bg))
        .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
    }
}

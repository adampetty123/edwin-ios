import SwiftUI

struct OnboardingFlow: View {
    @State private var step = 0

    var body: some View {
        NavigationStack {
            Group {
                if step == 0 {
                    ConnectWhatsAppView(
                        stepIndex: 0,
                        onDone: { step = 1 },
                        onSkip: { step = 1 }
                    )
                } else {
                    ConnectIMessageStep()
                }
            }
            .animation(.easeInOut(duration: 0.25), value: step)
        }
    }
}

private struct ConnectIMessageStep: View {
    @EnvironmentObject var auth: AuthStore

    var body: some View {
        ConnectChannelView(
            channel: .imessage,
            icon: "bubble.left.and.bubble.right.fill",
            tint: Theme.imessage,
            name: "iMessage",
            headline: "Your blue bubbles, finally sorted.",
            benefit: "Pull iMessage into the same calm feed, so the texts from people who matter never get buried.",
            bullets: [
                "Family and friends, never buried",
                "A nudge when you leave someone on read",
                "Drafts that actually sound like you",
            ],
            stepIndex: 1,
            onDone: { auth.completeOnboarding() },
            onSkip: { auth.completeOnboarding() }
        )
    }
}

/// One permission-earning screen per channel: show the value, then ask.
struct ConnectChannelView: View {
    @EnvironmentObject var auth: AuthStore

    let channel: Channel
    let icon: String
    let tint: Color
    let name: String
    let headline: String
    let benefit: String
    let bullets: [String]
    let stepIndex: Int
    let onDone: () -> Void
    let onSkip: () -> Void

    @State private var status: Status = .idle

    enum Status { case idle, connecting, done, error }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Spacer()

            iconTile
                .padding(.bottom, 24)

            Text("Connect \(name)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .kerning(0.5)
                .foregroundStyle(Theme.accent)
                .padding(.bottom, 8)
            Text(headline)
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.text)
                .padding(.bottom, 10)
            Text(benefit)
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(Theme.textMuted)
                .lineSpacing(4)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(bullets, id: \.self) { b in
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(tint)
                        Text(b)
                            .font(.system(size: 16, design: .rounded))
                            .foregroundStyle(Theme.text)
                    }
                }
            }
            .padding(.top, 24)

            Spacer()

            footer
        }
        .padding(.horizontal, 24)
        .background(Theme.bg)
    }

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(0..<2) { i in
                    Capsule()
                        .fill(i <= stepIndex ? Theme.accent : Theme.border)
                        .frame(width: i <= stepIndex ? 22 : 8, height: 8)
                        .animation(.spring(response: 0.3), value: stepIndex)
                }
            }
            .accessibilityLabel("Step \(stepIndex + 1) of 2")
            Spacer()
            if status != .done {
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
                .fill(tint.opacity(0.1))
                .frame(width: 80, height: 80)
                .overlay(Image(systemName: icon).font(.system(size: 36, design: .rounded)).foregroundStyle(tint))
            if status == .done {
                Circle()
                    .fill(Theme.success)
                    .frame(width: 28, height: 28)
                    .overlay(Image(systemName: "checkmark").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white))
                    .overlay(Circle().stroke(Theme.bg, lineWidth: 3))
                    .offset(x: 6, y: 6)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            if status == .error {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.danger)
                    Text("That one didn't land. Give it another go?")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Theme.danger)
                }
            }
            Button {
                connect()
            } label: {
                if status == .connecting {
                    HStack(spacing: 8) {
                        ProgressView().tint(.white)
                        Text("Connecting…")
                    }
                } else if status == .done {
                    Text("\(name) connected")
                } else if status == .error {
                    Text("Try again")
                } else {
                    Text("Connect \(name)")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(status == .connecting || status == .done)

            Text("Edwin only reads to sort. Nothing sends without your say-so.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Theme.textFaint)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.bottom, 16)
    }

    private func connect() {
        status = .connecting
        Task {
            // real channel link handshake goes here later
            try? await Task.sleep(nanoseconds: 650_000_000)
            auth.setChannel(channel, connected: true)
            let gen = UINotificationFeedbackGenerator()
            gen.notificationOccurred(.success)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) { status = .done }
            try? await Task.sleep(nanoseconds: 750_000_000)
            onDone()
        }
    }
}

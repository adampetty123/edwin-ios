import SwiftUI

struct WelcomeView: View {
    @State private var showSignUp = false
    @State private var showSignIn = false
    @State private var appeared = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                Spacer()

                HeroFlow()
                    .padding(.bottom, 28)

                VStack(alignment: .leading, spacing: 12) {
                    Text("YOUR MESSAGES, HANDLED")
                        .font(.system(size: 13, weight: .semibold))
                        .kerning(0.5)
                        .foregroundStyle(Theme.accent)
                    Text("Read less.\nMiss nothing.")
                        .font(.system(size: 38, weight: .heavy))
                        .foregroundStyle(Theme.text)
                        .lineSpacing(2)
                    Text("Edwin reads every WhatsApp and iMessage thread, surfaces what needs you, and drafts the rest. Nothing sends without you.")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.textMuted)
                        .lineSpacing(4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 14)

                Spacer()

                VStack(spacing: 10) {
                    Button {
                        showSignUp = true
                    } label: {
                        Text("Create account")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button("I already have an account") {
                        showSignIn = true
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.vertical, 10)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 14)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
            .background(Theme.bg)
            .navigationDestination(isPresented: $showSignUp) { SignUpView() }
            .navigationDestination(isPresented: $showSignIn) { SignInView() }
            .onAppear {
                withAnimation(.easeOut(duration: 0.5).delay(0.15)) { appeared = true }
            }
        }
    }

    private var header: some View {
        HStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Theme.accent)
                .frame(width: 44, height: 44)
                .overlay(
                    Text("e")
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundStyle(.white)
                        .offset(y: -1)
                )
            Spacer()
            HStack(spacing: 8) {
                channelChip(icon: "message.fill", label: "WhatsApp", color: Theme.whatsapp, bg: Color(hex: 0xE9FBF0))
                channelChip(icon: "bubble.left.fill", label: "iMessage", color: Theme.imessage, bg: Color(hex: 0xE8F2FF))
            }
        }
        .padding(.top, 8)
    }

    private func channelChip(icon: String, label: String, color: Color, bg: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11))
            Text(label).font(.system(size: 11, weight: .bold)).kerning(0.3)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(bg))
    }
}

/// Animated hero: incoming messages settle into one inbox. Entrance-only, calm.
struct HeroFlow: View {
    @State private var shown = [false, false, false]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let cards: [(name: String, text: String, color: Color, icon: String)] = [
        ("Mom", "Dinner Sunday?", Theme.whatsapp, "message.fill"),
        ("Daniel", "Sounds good 👍", Theme.imessage, "bubble.left.fill"),
        ("Design team", "shipped it", Theme.whatsapp, "message.fill"),
    ]

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Theme.accentSoft.opacity(0.5))
                    .frame(width: 230, height: 230)
                VStack(spacing: 8) {
                    ForEach(cards.indices, id: \.self) { i in
                        card(cards[i])
                            .opacity(shown[i] ? 1 : 0)
                            .offset(y: shown[i] ? 0 : 16)
                            .scaleEffect(shown[i] ? 1 : 0.94)
                    }
                }
                .frame(width: 250)
            }
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(.white)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Text("e")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(Theme.accent)
                    )
                Text("One inbox")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Capsule().fill(Theme.accent))
            .shadow(color: Theme.accent.opacity(0.3), radius: 12, y: 6)
        }
        .accessibilityLabel("WhatsApp and iMessage messages flowing into one Edwin inbox")
        .onAppear {
            for i in shown.indices {
                if reduceMotion {
                    shown[i] = true
                } else {
                    withAnimation(.easeOut(duration: 0.5).delay(0.25 + Double(i) * 0.22)) {
                        shown[i] = true
                    }
                }
            }
        }
    }

    private func card(_ c: (name: String, text: String, color: Color, icon: String)) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(c.color)
                .frame(width: 26, height: 26)
                .overlay(Image(systemName: c.icon).font(.system(size: 11)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 1) {
                Text(c.name).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.text)
                Text(c.text).font(.system(size: 12.5)).foregroundStyle(Theme.textMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white)
                .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
        )
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var loading = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(height: 52)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accent))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

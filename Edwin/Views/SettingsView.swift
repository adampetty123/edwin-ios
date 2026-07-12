import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var auth: AuthStore
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 52, height: 52)
                            .overlay(
                                Text(String(auth.userName.prefix(1)).uppercased())
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(.white)
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(auth.userName.isEmpty ? "You" : auth.userName)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(Theme.text)
                            Text(auth.userEmail)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Channels") {
                    channelRow(
                        icon: "message.fill", tint: Theme.whatsapp, name: "WhatsApp",
                        connected: auth.whatsappConnected
                    ) {
                        toggle(.whatsapp, current: auth.whatsappConnected)
                    }
                    channelRow(
                        icon: "bubble.left.and.bubble.right.fill", tint: Theme.imessage, name: "iMessage",
                        connected: auth.imessageConnected
                    ) {
                        toggle(.imessage, current: auth.imessageConnected)
                    }
                }

                Section("Preferences") {
                    Label("Notifications", systemImage: "bell")
                    Label("Privacy & data", systemImage: "checkmark.shield")
                    HStack {
                        Label("Assistant", systemImage: "wand.and.stars")
                        Spacer()
                        Text("Approve sends")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textMuted)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        confirmSignOut = true
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } footer: {
                    Text("Edwin v1.0.0")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog("You can sign back in anytime.", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {
                    Task { await auth.signOut() }
                }
            }
        }
    }

    private func channelRow(icon: String, tint: Color, name: String, connected: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(tint.opacity(0.12))
                .frame(width: 40, height: 40)
                .overlay(Image(systemName: icon).font(.system(size: 17)).foregroundStyle(tint))
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(connected ? "Connected" : "Not connected")
                    .font(.system(size: 13))
                    .foregroundStyle(connected ? Theme.success : Theme.textMuted)
                    .contentTransition(.numericText())
            }
            Spacer()
            Button(connected ? "Disconnect" : "Connect", action: action)
                .font(.system(size: 13, weight: .bold))
                .buttonStyle(.borderless)
                .foregroundStyle(connected ? Theme.textMuted : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(connected ? Theme.surfaceAlt : Theme.accent))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(connected ? "connected" : "not connected")")
    }

    private func toggle(_ channel: Channel, current: Bool) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation { auth.setChannel(channel, connected: !current) }
    }
}

import SwiftUI
import EventKit

private let settingsAccent = Color(hex: 0x2F6BFF)

struct SettingsView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var wa: WAStore
    @EnvironmentObject var cal: CalendarStore
    @EnvironmentObject var storeKit: Store
    @State private var showPaywall = false

    // Settings is pushed onto the home stack; NavigationLinks here push further.
    var body: some View {
        List {
            Section { profileCard }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)

            Section("User settings") {
                NavigationLink { AccountsSettings() } label: {
                    settingRow(icon: "person.crop.circle.fill", tint: settingsAccent, title: "Accounts")
                }
                NavigationLink { IntegrationsSettings() } label: {
                    settingRow(icon: "square.grid.2x2.fill", tint: Color(hex: 0xE8519B), title: "Integrations")
                }
            }

            Section("App settings") {
                NavigationLink { AppearanceSettings() } label: {
                    settingRow(icon: "paintbrush.fill", tint: Color(hex: 0x34C759), title: "Appearance")
                }
                NavigationLink { CalendarsSettings() } label: {
                    settingRow(icon: "calendar", tint: Color(hex: 0xF5B900), title: "Calendars")
                }
                NavigationLink { EventsSettings() } label: {
                    settingRow(icon: "ticket.fill", tint: Color(hex: 0xA25CFF), title: "Events")
                }
                NavigationLink { TodosSettings() } label: {
                    settingRow(icon: "checkmark.circle.fill", tint: Color(hex: 0x8E8E93), title: "Todos")
                }
                NavigationLink { NotificationsSettings() } label: {
                    settingRow(icon: "bell.fill", tint: Color(hex: 0xFF9500), title: "Notifications")
                }
            }

            Section {
                Button { sendFeedback() } label: {
                    settingRow(icon: "paperplane.fill", tint: settingsAccent, title: "Send feedback", chevron: false)
                }
                Button(role: .destructive) { Task { await auth.signOut() } } label: {
                    settingRow(icon: "rectangle.portrait.and.arrow.right", tint: Color(hex: 0xFF3B30), title: "Log out", chevron: false)
                }
            } footer: {
                Text("Edwin v1.0.0")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Theme.textFaint)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showPaywall) { PaywallView(onClose: { showPaywall = false }) }
        .task { if cal.connected { await cal.sync() } }
    }

    // MARK: profile card

    private var profileCard: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Theme.accent)
                .frame(width: 52, height: 52)
                .overlay(
                    Text(String(auth.userName.prefix(1)).uppercased())
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(auth.userName.isEmpty ? "You" : auth.userName)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.text)
                    Button { showPaywall = true } label: {
                        Text(storeKit.isPro ? "Pro" : "Free")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(storeKit.isPro ? Theme.accent : Theme.textMuted)
                            .padding(.horizontal, 9).padding(.vertical, 2)
                            .overlay(Capsule().stroke(storeKit.isPro ? Theme.accent : Theme.border, lineWidth: 1))
                    }
                }
                Text(auth.userEmail)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    // MARK: row helper

    @ViewBuilder
    private func settingRow(icon: String, tint: Color, title: String, chevron: Bool = true) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(tint)
                .frame(width: 30, height: 30)
                .overlay(Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white))
            Text(title)
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(Theme.text)
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func sendFeedback() {
        let subject = "Edwin feedback".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "mailto:hello@flowjam.com?subject=\(subject)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Accounts (connections)

struct AccountsSettings: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var wa: WAStore
    @State private var googleEmail: String?
    @State private var googleBusy = false
    @State private var googleError: String?
    @State private var showWASetup = false

    var body: some View {
        List {
            Section {
                connectionRow(icon: "message.fill", tint: Theme.whatsapp, name: "WhatsApp",
                              subtitle: wa.isConnected ? "Connected" : "Not connected",
                              connected: wa.isConnected, busy: false,
                              actionTitle: wa.isConnected ? "Connected" : "Set up",
                              disabled: wa.isConnected) { showWASetup = true }
                connectionRow(icon: "envelope.fill", tint: Color(hex: 0xEA4335), name: "Google",
                              subtitle: googleEmail.map { $0.isEmpty ? "Connected" : $0 } ?? "Gmail + Calendar",
                              connected: googleEmail != nil, busy: googleBusy,
                              actionTitle: googleEmail != nil ? "Connected" : "Connect",
                              disabled: googleEmail != nil) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    connectGoogle()
                }
            } footer: {
                if let err = googleError {
                    Text(err).foregroundStyle(Theme.danger)
                } else {
                    Text("Edwin reads these to triage what matters and answer for you. Nothing sends without your ok.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("Accounts")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showWASetup) {
            ConnectWhatsAppView(stepIndex: 0,
                                onDone: { showWASetup = false },
                                onSkip: { showWASetup = false })
        }
        .task { await refreshGoogle() }
    }

    private func refreshGoogle() async {
        guard let token = auth.accessToken else { return }
        googleEmail = await GoogleAuth.status(userId: auth.userId, accessToken: token)
    }
    private func connectGoogle() {
        guard let token = auth.accessToken, !googleBusy else { return }
        googleBusy = true; googleError = nil
        Task {
            do { try await GoogleAuth.connect(accessToken: token); await refreshGoogle()
                 UINotificationFeedbackGenerator().notificationOccurred(.success) }
            catch { let m = error.localizedDescription; if m != "Cancelled." { googleError = m } }
            googleBusy = false
        }
    }
}

/// Shared connection row (icon tile, name, subtitle, pill action).
func connectionRow(icon: String, tint: Color, name: String, subtitle: String, connected: Bool, busy: Bool, actionTitle: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
    HStack(spacing: 12) {
        RoundedRectangle(cornerRadius: 10)
            .fill(tint.opacity(0.12))
            .frame(width: 40, height: 40)
            .overlay(Image(systemName: icon).font(.system(size: 17, design: .rounded)).foregroundStyle(tint))
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(Theme.text)
            Text(subtitle).font(.system(size: 13, design: .rounded)).foregroundStyle(connected ? Theme.success : Theme.textMuted)
        }
        Spacer()
        if busy { ProgressView() }
        else {
            Button(actionTitle, action: action)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .buttonStyle(.borderless)
                .foregroundStyle(connected || disabled ? Theme.textMuted : .white)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(connected || disabled ? Theme.surfaceAlt : Theme.accent))
                .disabled(disabled)
        }
    }
}

// MARK: - Integrations (Edwin Pro + behaviour)

struct IntegrationsSettings: View {
    @EnvironmentObject var storeKit: Store
    @State private var showPaywall = false

    var body: some View {
        List {
            Section {
                Button { showPaywall = true } label: {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 10).fill(Theme.accent.opacity(0.12)).frame(width: 40, height: 40)
                            .overlay(Image(systemName: "sparkles").font(.system(size: 17)).foregroundStyle(Theme.accent))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Edwin Pro").font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(Theme.text)
                            Text(storeKit.isPro ? "Active" : "7 days free, then from \(storeKit.quarterlyPerMonth ?? "£4.98")/mo")
                                .font(.system(size: 13, design: .rounded))
                                .foregroundStyle(storeKit.isPro ? Theme.success : Theme.textMuted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textFaint)
                    }
                }
            } header: { Text("Subscription") }

            Section {
                HStack {
                    Label("Sending", systemImage: "paperplane")
                        .font(.system(size: 15, design: .rounded)).foregroundStyle(Theme.text)
                    Spacer()
                    Text("Approve first").font(.system(size: 13, design: .rounded)).foregroundStyle(Theme.textMuted)
                }
            } header: {
                Text("Assistant")
            } footer: {
                Text("Edwin drafts replies and waits for your ok before anything is sent.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("Integrations")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) { PaywallView(onClose: { showPaywall = false }) }
    }
}

// MARK: - Calendars

struct CalendarsSettings: View {
    @EnvironmentObject var cal: CalendarStore
    @State private var showPicker = false

    var body: some View {
        List {
            Section {
                connectionRow(icon: "calendar", tint: Color(hex: 0xF5B900), name: "Calendar",
                              subtitle: cal.connected ? (cal.syncing ? "Syncing…" : "\(cal.eventCount) events · \(cal.selectionLabel)") : "Let Edwin see when you're free",
                              connected: cal.connected, busy: cal.syncing,
                              actionTitle: cal.connected ? "Disconnect" : "Connect") {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    Task { cal.connected ? await cal.disconnect() : await cal.connect() }
                }
                if cal.connected {
                    Button { cal.loadCalendars(); showPicker = true } label: {
                        HStack {
                            Label("Choose calendars", systemImage: "checklist")
                                .font(.system(size: 15, design: .rounded)).foregroundStyle(Theme.text)
                            Spacer()
                            Text(cal.selectionLabel).font(.system(size: 13, design: .rounded)).foregroundStyle(Theme.textMuted)
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textFaint)
                        }
                    }
                }
            } footer: {
                if let err = cal.lastError { Text(err).foregroundStyle(Theme.danger) }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("Calendars")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPicker) { CalendarPickerSheet() }
        .task { if cal.connected { await cal.sync() } }
    }
}

// MARK: - lightweight app-settings screens

struct AppearanceSettings: View {
    @AppStorage("appearance.mode") private var mode = "system"
    var body: some View {
        List {
            Section {
                ForEach([("system", "Match device"), ("light", "Light"), ("dark", "Dark")], id: \.0) { key, label in
                    Button { mode = key } label: {
                        HStack {
                            Text(label).font(.system(size: 16, design: .rounded)).foregroundStyle(Theme.text)
                            Spacer()
                            if mode == key { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                        }
                    }
                }
            } header: {
                Text("Theme")
            } footer: { Text("Match device follows your iPhone's light and dark schedule; light and dark pin Edwin to one look.") }
        }
        .listStyle(.insetGrouped).scrollContentBackground(.hidden).background(Theme.bg)
        .navigationTitle("Appearance").navigationBarTitleDisplayMode(.inline)
    }
}

struct EventsSettings: View {
    @EnvironmentObject var cal: CalendarStore
    var body: some View {
        List {
            Section {
                Toggle("Add plans to my calendar", isOn: .constant(true)).disabled(true)
                    .font(.system(size: 16, design: .rounded))
            } footer: {
                Text("When you confirm a plan, Edwin puts it on your calendar automatically and tells you.")
            }
        }
        .listStyle(.insetGrouped).scrollContentBackground(.hidden).background(Theme.bg)
        .navigationTitle("Events").navigationBarTitleDisplayMode(.inline)
    }
}

struct TodosSettings: View {
    var body: some View {
        List {
            Section {
                Text("Edwin keeps a private to-do list of what you owe people and what you've asked him to track. Ask him \u{201c}what's on my list?\u{201d} in the chat any time.")
                    .font(.system(size: 15, design: .rounded)).foregroundStyle(Theme.textMuted)
            }
        }
        .listStyle(.insetGrouped).scrollContentBackground(.hidden).background(Theme.bg)
        .navigationTitle("Todos").navigationBarTitleDisplayMode(.inline)
    }
}

struct NotificationsSettings: View {
    var body: some View {
        List {
            Section {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                } label: {
                    HStack {
                        Text("Open notification settings").font(.system(size: 16, design: .rounded)).foregroundStyle(Theme.text)
                        Spacer()
                        Image(systemName: "arrow.up.forward.app").foregroundStyle(Theme.textFaint)
                    }
                }
            } footer: {
                Text("Edwin pings you when something needs you — an important message, a reply waiting for your ok. Manage the details in iOS Settings.")
            }
        }
        .listStyle(.insetGrouped).scrollContentBackground(.hidden).background(Theme.bg)
        .navigationTitle("Notifications").navigationBarTitleDisplayMode(.inline)
    }
}

/// Gmail connect flow. The Google OAuth handshake lights up the moment the
/// provider is configured; until then we set the expectation honestly.
struct EmailConnectSheet: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Theme.border).frame(width: 40, height: 5).padding(.top, 10)
            Spacer()
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(hex: 0xEA4335).opacity(0.1))
                .frame(width: 84, height: 84)
                .overlay(Image(systemName: "envelope.fill").font(.system(size: 38)).foregroundStyle(Color(hex: 0xEA4335)))
            Text("Connect your email")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.text)
                .padding(.top, 20)
            Text("Link Gmail and Edwin summarizes what matters, drafts replies for your approval, and keeps the junk out of your way.")
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 10)

            VStack(alignment: .leading, spacing: 12) {
                proof("Read-only to start — nothing sent without you")
                proof("Junk auto-filed, real mail summarized")
                proof("Reply drafts land in your Edwin chat")
            }
            .padding(.top, 24)

            Spacer()

            Button {
                // TODO: launches Google OAuth once the client is configured
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "g.circle.fill")
                    Text("Continue with Google")
                }
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity).frame(height: 54)
                .foregroundStyle(.white)
                .background(RoundedRectangle(cornerRadius: 50).fill(Theme.accent))
            }
            .disabled(true)
            .opacity(0.55)
            .padding(.horizontal, 24)

            Text("Google sign-in is being finalized — you'll be able to connect here shortly.")
                .font(.system(size: 12.5, design: .rounded))
                .foregroundStyle(Theme.textFaint)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.top, 10)
                .padding(.bottom, 24)
        }
        .background(Theme.bg)
        .presentationDetents([.medium, .large])
    }

    private func proof(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
            Text(text).font(.system(size: 15, design: .rounded)).foregroundStyle(Theme.text)
        }
    }
}


/// Pick exactly which device calendars Edwin watches.
struct CalendarPickerSheet: View {
    @EnvironmentObject var cal: CalendarStore
    @Environment(\.dismiss) var dismiss

    private var grouped: [(source: String, items: [EKCalendar])] {
        Dictionary(grouping: cal.availableCalendars, by: { $0.source.title })
            .map { (source: $0.key, items: $0.value.sorted { $0.title < $1.title }) }
            .sorted { $0.source < $1.source }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Edwin only reads events from the calendars you pick. Changes re-sync straight away.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Theme.textMuted)
                        .listRowBackground(Color.clear)
                }
                ForEach(grouped, id: \.source) { group in
                    Section(group.source) {
                        ForEach(group.items, id: \.calendarIdentifier) { c in
                            Button {
                                UISelectionFeedbackGenerator().selectionChanged()
                                cal.toggle(c)
                            } label: {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(Color(cgColor: c.cgColor ?? UIColor.systemBlue.cgColor))
                                        .frame(width: 12, height: 12)
                                    Text(c.title)
                                        .font(.system(size: 16, design: .rounded))
                                        .foregroundStyle(Theme.text)
                                    Spacer()
                                    Image(systemName: cal.isSelected(c) ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 20))
                                        .foregroundStyle(cal.isSelected(c) ? Theme.accent : Theme.border)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Calendars")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

import SwiftUI
import EventKit

struct SettingsView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var wa: WAStore
    @EnvironmentObject var cal: CalendarStore
    @State private var confirmSignOut = false
    @State private var showEmailSheet = false
    @State private var showCalendarPicker = false

    // NOTE: no NavigationStack here — Settings is pushed onto the Inbox stack
    // from the gear button in the top-right corner.
    var body: some View {
            List {
                Section {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 52, height: 52)
                            .overlay(
                                Text(String(auth.userName.prefix(1)).uppercased())
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(auth.userName.isEmpty ? "You" : auth.userName)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.text)
                            Text(auth.userEmail)
                                .font(.system(size: 13, design: .rounded))
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Messaging") {
                    connectionRow(
                        icon: "message.fill", tint: Theme.whatsapp, name: "WhatsApp",
                        subtitle: wa.isConnected ? "Connected" : "Not connected",
                        connected: wa.isConnected,
                        busy: false,
                        actionTitle: wa.isConnected ? "Connected" : "Set up",
                        disabled: wa.isConnected
                    ) {}
                }

                Section {
                    connectionRow(
                        icon: "calendar", tint: Theme.accent, name: "Calendar",
                        subtitle: cal.connected
                            ? (cal.syncing ? "Syncing…" : "\(cal.eventCount) events · \(cal.selectionLabel)")
                            : "Let Edwin see when you're free",
                        connected: cal.connected,
                        busy: cal.syncing,
                        actionTitle: cal.connected ? "Disconnect" : "Connect"
                    ) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        Task { cal.connected ? await cal.disconnect() : await cal.connect() }
                    }

                    if cal.connected {
                        Button {
                            cal.loadCalendars()
                            showCalendarPicker = true
                        } label: {
                            HStack {
                                Label("Choose calendars", systemImage: "checklist")
                                    .font(.system(size: 15, design: .rounded))
                                    .foregroundStyle(Theme.text)
                                Spacer()
                                Text(cal.selectionLabel)
                                    .font(.system(size: 13, design: .rounded))
                                    .foregroundStyle(Theme.textMuted)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.textFaint)
                            }
                        }
                    }

                    connectionRow(
                        icon: "envelope.fill", tint: Color(hex: 0xEA4335), name: "Email",
                        subtitle: "Gmail — summaries + smart replies",
                        connected: false,
                        busy: false,
                        actionTitle: "Connect"
                    ) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showEmailSheet = true
                    }
                } header: {
                    Text("Connections")
                } footer: {
                    if let err = cal.lastError {
                        Text(err).foregroundStyle(Theme.danger)
                    } else {
                        Text("Edwin uses these to answer availability and surface what needs you. Nothing is shared without your say-so.")
                    }
                }

                Section("Preferences") {
                    Label("Notifications", systemImage: "bell")
                    Label("Privacy & data", systemImage: "checkmark.shield")
                    HStack {
                        Label("Assistant", systemImage: "wand.and.stars")
                        Spacer()
                        Text("Approve sends")
                            .font(.system(size: 13, design: .rounded))
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
            .sheet(isPresented: $showEmailSheet) { EmailConnectSheet() }
            .sheet(isPresented: $showCalendarPicker) { CalendarPickerSheet() }
        .background(Theme.bg)
        .toolbar(.hidden, for: .tabBar)
        .task {
            // keep the calendar fresh whenever settings opens
            if cal.connected { await cal.sync() }
        }
    }

    private func connectionRow(icon: String, tint: Color, name: String, subtitle: String, connected: Bool, busy: Bool, actionTitle: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(tint.opacity(0.12))
                .frame(width: 40, height: 40)
                .overlay(Image(systemName: icon).font(.system(size: 17, design: .rounded)).foregroundStyle(tint))
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(connected ? Theme.success : Theme.textMuted)
            }
            Spacer()
            if busy {
                ProgressView()
            } else {
                Button(actionTitle, action: action)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .buttonStyle(.borderless)
                    .foregroundStyle(connected || disabled ? Theme.textMuted : .white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(connected || disabled ? Theme.surfaceAlt : Theme.accent))
                    .disabled(disabled)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(subtitle)")
    }

    private func channelRow(icon: String, tint: Color, name: String, connected: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(tint.opacity(0.12))
                .frame(width: 40, height: 40)
                .overlay(Image(systemName: icon).font(.system(size: 17, design: .rounded)).foregroundStyle(tint))
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text(connected ? "Connected" : "Not connected")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(connected ? Theme.success : Theme.textMuted)
                    .contentTransition(.numericText())
            }
            Spacer()
            Button(connected ? "Disconnect" : "Connect", action: action)
                .font(.system(size: 13, weight: .bold, design: .rounded))
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

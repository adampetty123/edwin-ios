import SwiftUI

@main
struct EdwinApp: App {
    @StateObject private var auth = AuthStore()
    @StateObject private var wa = WAStore()
    @StateObject private var cal = CalendarStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(wa)
                .environmentObject(cal)
                .tint(Theme.accent)
                .fontDesign(.rounded)
                .onAppear { wa.auth = auth; cal.auth = auth }
        }
    }
}

/// Routes to the right surface based on auth + onboarding state.
struct RootView: View {
    @EnvironmentObject var auth: AuthStore

    var body: some View {
        Group {
            if auth.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.bg)
            } else if !auth.isAuthed {
                WelcomeView()
            } else if !auth.onboarded {
                OnboardingFlow()
            } else {
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: auth.isAuthed)
        .animation(.easeInOut(duration: 0.25), value: auth.onboarded)
        .task { await auth.restoreSession() }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            InboxView()
                .tabItem { Label("Inbox", systemImage: "envelope.fill") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

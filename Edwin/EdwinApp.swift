import SwiftUI

@main
struct EdwinApp: App {
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) var pushDelegate
    @StateObject private var auth = AuthStore()
    @StateObject private var wa = WAStore()
    @StateObject private var cal = CalendarStore()
    @StateObject private var store = Store()
    @AppStorage("appearance.mode") private var appearanceMode = "system"

    private var scheme: ColorScheme? {
        switch appearanceMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(wa)
                .environmentObject(cal)
                .environmentObject(store)
                .tint(Theme.accent)
                .fontDesign(.rounded)
                .preferredColorScheme(scheme)
                .onAppear { wa.auth = auth; cal.auth = auth }
        }
    }
}

/// Routes to the right surface based on auth + onboarding state.
struct RootView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var store: Store
    @AppStorage("paywall.seen.v1") private var paywallSeen = false

    var body: some View {
        Group {
            if auth.isLoading {
                LoadingView()
            } else if !auth.isAuthed {
                WelcomeView()
            } else if !auth.onboarded {
                OnboardingFlow()
            } else if store.checked && !store.isPro && !paywallSeen {
                PaywallView(onClose: { paywallSeen = true })
            } else {
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: auth.isAuthed)
        .animation(.easeInOut(duration: 0.25), value: auth.onboarded)
        .animation(.easeInOut(duration: 0.25), value: store.isPro)
        .task { await auth.restoreSession() }
        .task { await store.start() }
    }
}

import Foundation
import SwiftUI

/// App-wide auth + onboarding state. Session tokens live in the keychain,
/// channel/onboarding flags in UserDefaults.
@MainActor
final class AuthStore: ObservableObject {
    @Published var isLoading = true
    @Published var isAuthed = false
    @Published var userName: String = ""
    @Published var userEmail: String = ""
    @Published var whatsappConnected = false
    @Published var imessageConnected = false
    @Published var onboardingDone = false

    private var accessToken: String?

    var onboarded: Bool { onboardingDone || whatsappConnected || imessageConnected }

    private enum Keys {
        static let refresh = "edwin.refreshToken"
        static let name = "edwin.userName"
        static let email = "edwin.userEmail"
        static let whatsapp = "edwin.channel.whatsapp"
        static let imessage = "edwin.channel.imessage"
        static let onboarded = "edwin.onboardingDone"
    }

    // MARK: session lifecycle

    func restoreSession() async {
        defer { isLoading = false }
        guard !isAuthed else { return }
        let d = UserDefaults.standard
        whatsappConnected = d.bool(forKey: Keys.whatsapp)
        imessageConnected = d.bool(forKey: Keys.imessage)
        onboardingDone = d.bool(forKey: Keys.onboarded)

        guard let refresh = Keychain.get(Keys.refresh) else { return }
        do {
            let session = try await SupabaseAuthClient.refresh(refreshToken: refresh)
            apply(session)
        } catch {
            // stale token — stay signed out quietly
            Keychain.delete(Keys.refresh)
        }
    }

    func signUp(name: String, email: String, password: String) async throws {
        let session = try await SupabaseAuthClient.signUp(name: name, email: email, password: password)
        resetOnboarding()
        apply(session)
    }

    func signIn(email: String, password: String) async throws {
        let session = try await SupabaseAuthClient.signIn(email: email, password: password)
        apply(session)
    }

    func signOut() async {
        if let token = accessToken {
            await SupabaseAuthClient.signOut(accessToken: token)
        }
        accessToken = nil
        isAuthed = false
        userName = ""
        userEmail = ""
        Keychain.delete(Keys.refresh)
        resetOnboarding()
    }

    private func apply(_ session: AuthSession) {
        accessToken = session.accessToken
        userName = session.user.displayName
        userEmail = session.user.email ?? ""
        isAuthed = true
        Keychain.set(session.refreshToken, for: Keys.refresh)
        let d = UserDefaults.standard
        d.set(userName, forKey: Keys.name)
        d.set(userEmail, forKey: Keys.email)
    }

    // MARK: channels + onboarding

    func setChannel(_ channel: Channel, connected: Bool) {
        let d = UserDefaults.standard
        switch channel {
        case .whatsapp:
            whatsappConnected = connected
            d.set(connected, forKey: Keys.whatsapp)
        case .imessage:
            imessageConnected = connected
            d.set(connected, forKey: Keys.imessage)
        }
    }

    func completeOnboarding() {
        onboardingDone = true
        UserDefaults.standard.set(true, forKey: Keys.onboarded)
    }

    private func resetOnboarding() {
        whatsappConnected = false
        imessageConnected = false
        onboardingDone = false
        let d = UserDefaults.standard
        d.set(false, forKey: Keys.whatsapp)
        d.set(false, forKey: Keys.imessage)
        d.set(false, forKey: Keys.onboarded)
    }
}

enum Channel {
    case whatsapp, imessage
}

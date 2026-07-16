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

    private(set) var accessToken: String?
    @Published var userId: String = ""

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
        // fast path: cached identity + last access token render the app
        // instantly; the token refresh happens behind the UI instead of
        // blocking cold launch on a network round-trip.
        if let uid = d.string(forKey: "edwin.cache.userId"), !uid.isEmpty,
           let cachedAccess = Keychain.get("edwin.cache.access") {
            userId = uid
            userName = d.string(forKey: "edwin.cache.name") ?? ""
            userEmail = d.string(forKey: "edwin.cache.email") ?? ""
            accessToken = cachedAccess
            isAuthed = true
            isLoading = false
        }
        do {
            let session = try await SupabaseAuthClient.refresh(refreshToken: refresh)
            apply(session)
        } catch {
            // refresh failed: if we never got a cached session, the token is
            // stale — sign out quietly. if we're optimistically authed it was
            // likely a network blip; the next refresh cycle sorts it.
            if !isAuthed { Keychain.delete(Keys.refresh) }
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

    func signInWithApple(idToken: String, nonce: String, fullName: String?) async throws {
        let session = try await SupabaseAuthClient.signInWithApple(idToken: idToken, nonce: nonce)
        apply(session)
        // Apple only shares the name on the very first authorization — persist it.
        let existing = (session.user.userMetadata?["name"]?.value as? String) ?? ""
        if let fullName, !fullName.isEmpty, existing.isEmpty {
            await SupabaseAuthClient.updateName(fullName, accessToken: session.accessToken)
            userName = fullName
            UserDefaults.standard.set(fullName, forKey: Keys.name)
        }
    }

    /// Google sign-in: hosted OAuth hands back a refresh token; exchanging it
    /// through the normal refresh path lands a full session.
    func signInWithGoogle() async throws {
        let refreshToken = try await GoogleAuth.signIn()
        let session = try await SupabaseAuthClient.refresh(refreshToken: refreshToken)
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
        Keychain.delete("edwin.cache.access")
        UserDefaults.standard.removeObject(forKey: "edwin.cache.userId")
        try? FileManager.default.removeItem(
            at: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("edwin_state.json"))
        resetOnboarding()
    }

    private func apply(_ session: AuthSession) {
        accessToken = session.accessToken
        userId = session.user.id
        UserDefaults.standard.set(session.user.id, forKey: "edwin.cache.userId")
        UserDefaults.standard.set(session.user.displayName, forKey: "edwin.cache.name")
        UserDefaults.standard.set(session.user.email ?? "", forKey: "edwin.cache.email")
        Keychain.set(session.accessToken, for: "edwin.cache.access")
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

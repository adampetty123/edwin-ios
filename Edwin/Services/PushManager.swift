import Foundation
import UIKit
import UserNotifications

/// Registers for APNs and syncs the device token to Supabase so the bridge
/// can push new-message notifications.
@MainActor
final class PushManager: NSObject, ObservableObject {
    static let shared = PushManager()

    private let tokenKey = "edwin.push.token"
    private let syncedKey = "edwin.push.synced"

    /// Ask for permission (first time) and register with APNs.
    func enable() {
        Task {
            let center = UNUserNotificationCenter.current()
            let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
            guard granted else { return }
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// Called from the app delegate with the raw APNs token.
    func didRegister(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        let old = UserDefaults.standard.string(forKey: tokenKey)
        UserDefaults.standard.set(token, forKey: tokenKey)
        if token != old { UserDefaults.standard.set(false, forKey: syncedKey) }
    }

    /// Idempotent: uploads the token once per change, once auth is available.
    func syncIfNeeded(userId: String?, accessToken: String?) async {
        guard let userId, let accessToken,
              let token = UserDefaults.standard.string(forKey: tokenKey),
              !UserDefaults.standard.bool(forKey: syncedKey) else { return }
        var r = URLRequest(url: URL(string: "https://cchnsizaeoqhgawkyugs.supabase.co/rest/v1/wa_push_tokens?on_conflict=user_id,token")!)
        r.httpMethod = "POST"
        r.setValue(SupabaseAuthClient.anonKey, forHTTPHeaderField: "apikey")
        r.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        r.httpBody = try? JSONSerialization.data(withJSONObject: [[
            "user_id": userId, "token": token, "platform": "ios",
            "updated_at": ISO8601DateFormatter().string(from: Date()),
        ]])
        if let (_, resp) = try? await URLSession.shared.data(for: r),
           let http = resp as? HTTPURLResponse, http.statusCode < 400 {
            UserDefaults.standard.set(true, forKey: syncedKey)
        }
    }
}

/// Minimal app delegate to receive the APNs registration callbacks.
final class PushAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in PushManager.shared.didRegister(deviceToken: deviceToken) }
    }
    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // no-op: simulator / entitlement issues land here
    }
}

import AuthenticationServices
import Foundation
import SwiftUI

/// Google OAuth, both flavors:
/// 1. Sign in with Google — Supabase-hosted OAuth, lands a Supabase session.
/// 2. Connect Google — gmail + calendar scopes with offline access; tokens are
///    stored server-side (google_accounts) so Edwin's brain can read mail and
///    manage the calendar. Both use ASWebAuthenticationSession, so the
///    edwin:// callback needs no Info.plist registration.
enum GoogleAuth {
    static let projectURL = "https://cchnsizaeoqhgawkyugs.supabase.co"

    /// Presents Google sign-in and returns a Supabase refresh token.
    @MainActor
    static func signIn() async throws -> String {
        let authorize = "\(projectURL)/auth/v1/authorize?provider=google&redirect_to=edwin://auth-callback"
        let callback = try await present(url: URL(string: authorize)!, scheme: "edwin")
        // Supabase returns tokens in the URL fragment
        guard let fragment = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.fragment else {
            throw AuthError.server("Google sign-in didn't complete. Give it another go?")
        }
        var params: [String: String] = [:]
        for pair in fragment.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 { params[String(kv[0])] = String(kv[1]).removingPercentEncoding }
        }
        guard let refresh = params["refresh_token"] else {
            throw AuthError.server(params["error_description"]?.replacingOccurrences(of: "+", with: " ")
                ?? "Google sign-in didn't complete. Give it another go?")
        }
        return refresh
    }

    /// Presents the gmail + calendar consent flow for the signed-in user.
    @MainActor
    static func connect(accessToken: String) async throws {
        // ask the edge function for a consent URL tied to this user
        var req = URLRequest(url: URL(string: "\(projectURL)/functions/v1/google-oauth-start")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let urlStr = obj["url"] as? String, let url = URL(string: urlStr) else {
            throw AuthError.server("Couldn't start the Google connection. Give it another go?")
        }
        _ = try await present(url: url, scheme: "edwin") // resolves on edwin://google-connected
    }

    /// The connected Google account's email, if any (RLS: own row only).
    static func status(userId: String, accessToken: String) async -> String? {
        var req = URLRequest(url: URL(string:
            "\(projectURL)/rest/v1/google_accounts?user_id=eq.\(userId)&select=email")!)
        req.setValue(SupabaseAuthClient.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = rows.first else { return nil }
        return (first["email"] as? String) ?? ""
    }

    // MARK: web auth plumbing

    @MainActor
    private static func present(url: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { cb, err in
                if let cb { cont.resume(returning: cb) }
                else if let err, (err as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                    cont.resume(throwing: AuthError.server("Cancelled."))
                } else {
                    cont.resume(throwing: AuthError.server("Google didn't complete. Give it another go?"))
                }
            }
            session.presentationContextProvider = PresentationAnchor.shared
            session.prefersEphemeralWebBrowserSession = false
            if !session.start() {
                cont.resume(throwing: AuthError.server("Couldn't open the sign-in window."))
            }
        }
    }

    private final class PresentationAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
        static let shared = PresentationAnchor()
        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first ?? ASPresentationAnchor()
        }
    }
}

/// "Continue with Google" button, styled to sit beside the Apple one.
struct GoogleSignInButton: View {
    @EnvironmentObject var auth: AuthStore
    @Binding var error: String?
    @State private var busy = false

    var body: some View {
        Button {
            guard !busy else { return }
            busy = true
            Task {
                do { try await auth.signInWithGoogle() }
                catch {
                    let msg = error.localizedDescription
                    if msg != "Cancelled." { self.error = msg }
                }
                busy = false
            }
        } label: {
            HStack(spacing: 10) {
                if busy {
                    ProgressView()
                } else {
                    Text("G")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: 0x4285F4))
                }
                Text("Continue with Google")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
            }
            .frame(height: 56)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(Theme.surface))
            .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
        }
        .disabled(busy)
        .accessibilityLabel("Continue with Google")
    }
}

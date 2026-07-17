import AuthenticationServices
import CryptoKit
import Foundation
import SwiftUI

/// Sign in with Apple → Supabase id_token grant.
enum AppleSignIn {
    /// Raw nonce sent to Supabase; its SHA256 goes into the Apple request.
    static func randomNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            // extremely unlikely fallback: UUID-based entropy
            return (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "")
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Drop-in Apple button wired to AuthStore. Owns its nonce per attempt.
struct AppleSignInButton: View {
    @EnvironmentObject var auth: AuthStore
    @Environment(\.colorScheme) private var colorScheme
    @Binding var error: String?
    var label: SignInWithAppleButton.Label = .continue
    @State private var nonce = ""

    var body: some View {
        SignInWithAppleButton(label) { request in
            nonce = AppleSignIn.randomNonce()
            request.requestedScopes = [.fullName, .email]
            request.nonce = AppleSignIn.sha256(nonce)
        } onCompletion: { result in
            switch result {
            case .success(let authorization):
                guard let cred = authorization.credential as? ASAuthorizationAppleIDCredential,
                      let tokenData = cred.identityToken,
                      let idToken = String(data: tokenData, encoding: .utf8) else {
                    error = "Apple sign-in didn't hand back a credential. Give it another go?"
                    return
                }
                // Apple only provides the name on the FIRST authorization — capture it.
                let name = [cred.fullName?.givenName, cred.fullName?.familyName]
                    .compactMap { $0 }
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespaces)
                let rawNonce = nonce
                Task {
                    do {
                        try await auth.signInWithApple(
                            idToken: idToken,
                            nonce: rawNonce,
                            fullName: name.isEmpty ? nil : name
                        )
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
            case .failure(let err):
                // user tapping cancel is not an error worth showing
                if (err as NSError).code != ASAuthorizationError.canceled.rawValue {
                    error = "Apple sign-in failed. Give it another go?"
                }
            }
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 56)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 50))
        .accessibilityLabel("Continue with Apple")
    }
}

/// "or" divider used between Apple and email auth.
struct OrDivider: View {
    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Theme.border).frame(height: 1)
            Text("or")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textMuted)
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }
}

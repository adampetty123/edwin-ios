import Foundation

/// Minimal Supabase Auth client over URLSession — no external dependencies.
/// Talks to the GoTrue REST endpoints directly.
struct AuthSession: Codable {
    let accessToken: String
    let refreshToken: String
    let user: AuthUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case user
    }
}

struct AuthUser: Codable {
    let id: String
    let email: String?
    let userMetadata: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case id, email
        case userMetadata = "user_metadata"
    }

    var displayName: String {
        if let name = userMetadata?["name"]?.value as? String, !name.isEmpty { return name }
        return email?.components(separatedBy: "@").first ?? "You"
    }
}

/// Tiny type-erased Codable for user_metadata.
struct AnyCodable: Codable {
    let value: Any

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { value = s }
        else if let b = try? c.decode(Bool.self) { value = b }
        else if let i = try? c.decode(Int.self) { value = i }
        else if let d = try? c.decode(Double.self) { value = d }
        else { value = "" }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if let s = value as? String { try c.encode(s) }
        else if let b = value as? Bool { try c.encode(b) }
        else if let i = value as? Int { try c.encode(i) }
        else if let d = value as? Double { try c.encode(d) }
        else { try c.encode("") }
    }
}

enum AuthError: LocalizedError {
    case server(String)

    var errorDescription: String? {
        switch self {
        case .server(let m): return m
        }
    }
}

enum SupabaseAuthClient {
    static let baseURL = URL(string: "https://cchnsizaeoqhgawkyugs.supabase.co/auth/v1")!
    // anon (publishable) key — safe to ship; RLS governs what it can do.
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNjaG5zaXphZW9xaGdhd2t5dWdzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODM4NjIxNTksImV4cCI6MjA5OTQzODE1OX0.EcoUW4P9Q8gs6p7dzyMABu6dypDo-yNRshutlFzT4Rw"

    static func signUp(name: String, email: String, password: String) async throws -> AuthSession {
        try await post("signup", body: [
            "email": email.trimmingCharacters(in: .whitespaces).lowercased(),
            "password": password,
            "data": ["name": name.trimmingCharacters(in: .whitespaces)],
        ])
    }

    static func signIn(email: String, password: String) async throws -> AuthSession {
        try await post("token?grant_type=password", body: [
            "email": email.trimmingCharacters(in: .whitespaces).lowercased(),
            "password": password,
        ])
    }

    /// Native Sign in with Apple: exchange Apple's identity token for a Supabase session.
    static func signInWithApple(idToken: String, nonce: String) async throws -> AuthSession {
        try await post("token?grant_type=id_token", body: [
            "provider": "apple",
            "id_token": idToken,
            "nonce": nonce,
        ])
    }

    /// Set user_metadata.name (Apple only shares the name on first sign-in).
    static func updateName(_ name: String, accessToken: String) async {
        var req = URLRequest(url: URL(string: baseURL.absoluteString + "/user")!)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["data": ["name": name]])
        _ = try? await URLSession.shared.data(for: req)
    }

    static func refresh(refreshToken: String) async throws -> AuthSession {
        try await post("token?grant_type=refresh_token", body: ["refresh_token": refreshToken])
    }

    static func signOut(accessToken: String) async {
        var req = URLRequest(url: baseURL.appendingPathComponent("logout"))
        req.httpMethod = "POST"
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: req)
    }

    private static func post(_ path: String, body: [String: Any]) async throws -> AuthSession {
        let url = URL(string: path, relativeTo: baseURL.appendingPathComponent(""))
            ?? baseURL.appendingPathComponent(path)
        var req = URLRequest(url: URL(string: baseURL.absoluteString + "/" + path)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = url // silence unused

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw AuthError.server("No response.") }
        if http.statusCode >= 400 {
            throw AuthError.server(friendlyError(from: data))
        }
        do {
            return try JSONDecoder().decode(AuthSession.self, from: data)
        } catch {
            throw AuthError.server("Unexpected response. Give it another go?")
        }
    }

    /// Map GoTrue error payloads to Edwin's warm voice.
    private static func friendlyError(from data: Data) -> String {
        let raw = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let msg = (raw["msg"] as? String)
            ?? (raw["message"] as? String)
            ?? (raw["error_description"] as? String)
            ?? "Something went wrong."
        let m = msg.lowercased()
        if m.contains("already registered") || m.contains("already exists") {
            return "An account with this email already exists."
        }
        if m.contains("invalid login") { return "Wrong email or password." }
        if m.contains("at least 6") || m.contains("password") && m.contains("short") {
            return "Password must be at least 6 characters."
        }
        if m.contains("email not confirmed") { return "Confirm your email first, then sign in." }
        return msg
    }
}

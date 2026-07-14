import SwiftUI

// MARK: - Model

struct Email: Codable, Identifiable, Hashable {
    let gmailId: String
    let threadId: String?
    let fromName: String?
    let fromEmail: String?
    let subject: String?
    let snippet: String?
    let bodyText: String?
    let ts: Date?
    var unread: Bool

    var id: String { gmailId }
    var sender: String { fromName?.isEmpty == false ? fromName! : (fromEmail ?? "Unknown") }

    enum CodingKeys: String, CodingKey {
        case gmailId = "gmail_id", threadId = "thread_id", fromName = "from_name"
        case fromEmail = "from_email", subject, snippet, bodyText = "body_text", ts, unread
    }
}

// MARK: - Store

@MainActor
final class EmailStore: ObservableObject {
    @Published var emails: [Email] = []
    @Published var loaded = false
    weak var auth: AuthStore?

    private static let rest = "https://cchnsizaeoqhgawkyugs.supabase.co/rest/v1"

    func refresh() async {
        guard let token = auth?.accessToken else { return }
        var req = URLRequest(url: URL(string:
            "\(Self.rest)/emails?select=gmail_id,thread_id,from_name,from_email,subject,snippet,body_text,ts,unread&order=ts.desc&limit=100")!)
        req.setValue(SupabaseAuthClient.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { loaded = true; return }
        let decoder = JSONDecoder()
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fmtNoFrac = ISO8601DateFormatter()
        decoder.dateDecodingStrategy = .custom { d in
            let s = try d.singleValueContainer().decode(String.self)
            return fmt.date(from: s) ?? fmtNoFrac.date(from: s) ?? Date()
        }
        if let rows = try? decoder.decode([Email].self, from: data) {
            emails = rows
        }
        loaded = true
    }

    /// Optimistically mark read in the app (gmail-side read state comes later).
    func markRead(_ email: Email) async {
        guard email.unread, let token = auth?.accessToken else { return }
        if let i = emails.firstIndex(where: { $0.id == email.id }) { emails[i].unread = false }
        var req = URLRequest(url: URL(string:
            "\(Self.rest)/emails?gmail_id=eq.\(email.gmailId)")!)
        req.httpMethod = "PATCH"
        req.setValue(SupabaseAuthClient.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["unread": false])
        _ = try? await URLSession.shared.data(for: req)
    }
}

// MARK: - Views

struct EmailListView: View {
    @EnvironmentObject var auth: AuthStore
    @StateObject private var store = EmailStore()
    @State private var googleConnected: Bool? = nil

    var body: some View {
        NavigationStack {
            Group {
                if googleConnected == false {
                    connectPrompt
                } else if !store.loaded {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if store.emails.isEmpty {
                    emptyState
                } else {
                    List(store.emails) { email in
                        NavigationLink(value: email) { EmailRow(email: email) }
                            .listRowBackground(Theme.bg)
                    }
                    .listStyle(.plain)
                    .refreshable { await store.refresh() }
                }
            }
            .background(Theme.bg)
            .navigationTitle("Email")
            .navigationDestination(for: Email.self) { email in
                EmailDetailView(email: email)
                    .environmentObject(store)
            }
            .task {
                store.auth = auth
                if let token = auth.accessToken {
                    googleConnected = await GoogleAuth.status(userId: auth.userId, accessToken: token) != nil
                }
                await store.refresh()
                // keep fresh while the tab is open (bridge syncs every 3 min)
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 60_000_000_000)
                    await store.refresh()
                }
            }
        }
    }

    private var connectPrompt: some View {
        VStack(spacing: 14) {
            Image(systemName: "envelope.badge")
                .font(.system(size: 44))
                .foregroundStyle(Theme.textFaint)
            Text("Connect Google to see your mail")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.text)
            Text("Settings → Google → Connect. Your inbox shows up here and Edwin can read and send email for you.")
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(Theme.textFaint)
            Text("Syncing your inbox…")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.text)
            Text("First sync takes a minute or two. Pull to refresh.")
                .font(.system(size: 13.5, design: .rounded))
                .foregroundStyle(Theme.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmailRow: View {
    let email: Email

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(email.unread ? Theme.accent : .clear)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(email.sender)
                        .font(.system(size: 15.5, weight: email.unread ? .bold : .semibold, design: .rounded))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Spacer()
                    if let ts = email.ts {
                        Text(timeLabel(ts))
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(Theme.textFaint)
                    }
                }
                Text(email.subject ?? "(no subject)")
                    .font(.system(size: 14, weight: email.unread ? .semibold : .regular, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(email.snippet ?? "")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 3)
    }

    private func timeLabel(_ d: Date) -> String {
        if Calendar.current.isDateInToday(d) { return d.formatted(date: .omitted, time: .shortened) }
        if Calendar.current.isDateInYesterday(d) { return "Yesterday" }
        return d.formatted(.dateTime.day().month(.abbreviated))
    }
}

struct EmailDetailView: View {
    let email: Email
    @EnvironmentObject var store: EmailStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(email.subject ?? "(no subject)")
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                HStack(spacing: 10) {
                    PfpAvatar(name: email.sender, jid: email.fromEmail ?? email.sender, urlString: nil, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(email.sender)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.text)
                        Text(email.fromEmail ?? "")
                            .font(.system(size: 12.5, design: .rounded))
                            .foregroundStyle(Theme.textMuted)
                    }
                    Spacer()
                    if let ts = email.ts {
                        Text(ts.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(Theme.textFaint)
                    }
                }
                Divider()
                Text(email.bodyText?.isEmpty == false ? email.bodyText! : (email.snippet ?? ""))
                    .font(.system(size: 15.5, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .lineSpacing(3)
                    .textSelection(.enabled)
            }
            .padding(20)
        }
        .background(Theme.bg)
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.markRead(email) }
    }
}

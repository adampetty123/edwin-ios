import Foundation

/// Live updates over Supabase Realtime (Phoenix channels on a websocket).
/// Instead of decoding rows, an event just triggers the matching refresh —
/// the REST layer stays the single source of truth, the socket kills the lag.
@MainActor
final class RealtimeClient: NSObject, ObservableObject {
    @Published var connected = false

    /// Called with the chat_jid of an inserted message (or nil for chat-level changes).
    var onChange: ((String?) -> Void)?

    private var task: URLSessionWebSocketTask?
    private var heartbeat: Timer?
    private var ref = 0
    private var accessToken: String?
    private var reconnectDelay: TimeInterval = 1

    private static let url = URL(string:
        "wss://cchnsizaeoqhgawkyugs.supabase.co/realtime/v1/websocket?apikey=\(SupabaseAuthClient.anonKey)&vsn=1.0.0")!

    func start(accessToken: String) {
        guard task == nil || self.accessToken != accessToken else { return }
        self.accessToken = accessToken
        connect()
    }

    func stop() {
        heartbeat?.invalidate(); heartbeat = nil
        task?.cancel(with: .goingAway, reason: nil); task = nil
        connected = false
    }

    private func connect() {
        stop()
        guard let accessToken else { return }
        let t = URLSession.shared.webSocketTask(with: Self.url)
        task = t
        t.resume()
        receive()
        // one channel, three postgres_changes listeners; RLS scopes rows to this user
        send([
            "topic": "realtime:edwin",
            "event": "phx_join",
            "ref": nextRef(),
            "payload": [
                "config": ["postgres_changes": [
                    ["event": "INSERT", "schema": "public", "table": "wa_messages"],
                    ["event": "UPDATE", "schema": "public", "table": "wa_chats"],
                    ["event": "*", "schema": "public", "table": "assistant_drafts"],
                ]],
                "access_token": accessToken,
            ],
        ])
        heartbeat?.invalidate()
        heartbeat = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.send(["topic": "phoenix", "event": "heartbeat", "ref": self?.nextRef() ?? "0", "payload": [:]])
            }
        }
    }

    private func nextRef() -> String { ref += 1; return String(ref) }

    private func send(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let s = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(s)) { _ in }
    }

    private func receive() {
        task?.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .failure:
                    self.connected = false
                    self.scheduleReconnect()
                case .success(let msg):
                    self.reconnectDelay = 1
                    if case .string(let s) = msg { self.handle(s) }
                    self.receive()
                }
            }
        }
    }

    private func handle(_ raw: String) {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = obj["event"] as? String else { return }
        switch event {
        case "phx_reply":
            if let status = (obj["payload"] as? [String: Any])?["status"] as? String, status == "ok",
               (obj["topic"] as? String) == "realtime:edwin" {
                connected = true
            }
        case "postgres_changes":
            let payload = obj["payload"] as? [String: Any]
            let inner = payload?["data"] as? [String: Any]
            let table = inner?["table"] as? String
            let record = inner?["record"] as? [String: Any]
            let jid = (table == "wa_messages") ? record?["chat_jid"] as? String : nil
            onChange?(jid)
        case "phx_error", "phx_close":
            connected = false
            scheduleReconnect()
        default:
            break
        }
    }

    private func scheduleReconnect() {
        let delay = reconnectDelay
        reconnectDelay = min(30, reconnectDelay * 2)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            Task { @MainActor in self?.connect() }
        }
    }
}

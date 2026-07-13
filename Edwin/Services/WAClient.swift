import Foundation

// MARK: models (rows in Supabase, RLS-scoped to the signed-in user)

struct WAAccount: Codable {
    let userId: String
    let phone: String
    let status: String        // pending_pair | starting | pairing | connected | disconnected | error
    let pairingCode: String?
    let waName: String?
    let error: String?
    let chatsSynced: Int?
    let messagesSynced: Int?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id", phone, status
        case pairingCode = "pairing_code", waName = "wa_name", error
        case chatsSynced = "chats_synced", messagesSynced = "messages_synced"
    }
}

struct WAChat: Codable, Identifiable, Equatable {
    let jid: String
    let name: String?
    let lastMessageText: String?
    let lastMessageAt: Date?
    let lastSender: String?
    var unread: Int?
    let isGroup: Bool?
    let avatarUrl: String?
    let isAssistant: Bool?
    let pinned: Bool?

    var id: String { jid }
    var displayName: String { (name?.isEmpty == false ? name! : jid.components(separatedBy: "@").first) ?? jid }
    var assistant: Bool { isAssistant == true || jid == "assistant@edwin" }

    enum CodingKeys: String, CodingKey {
        case jid, name, unread, pinned
        case lastMessageText = "last_message_text"
        case lastMessageAt = "last_message_at"
        case lastSender = "last_sender"
        case isGroup = "is_group"
        case avatarUrl = "avatar_url"
        case isAssistant = "is_assistant"
    }
}

struct AssistantDraft: Codable, Identifiable, Equatable {
    let id: Int
    let chatJid: String
    let chatName: String?
    let reason: String?
    let text: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case id, reason, text, status
        case chatJid = "chat_jid", chatName = "chat_name"
    }
}

struct WAReaction: Codable, Equatable {
    let by: String
    let emoji: String
}

struct WAMessage: Codable, Identifiable, Equatable {
    let id: Int
    let chatJid: String
    let msgId: String
    let senderName: String?
    let fromMe: Bool
    let text: String
    let ts: Date
    let mediaType: String?
    let mediaUrl: String?
    let reactions: [WAReaction]?
    let status: String?          // sent | delivered | read (from_me only)
    let quotedMsgId: String?
    let quotedText: String?
    let quotedSender: String?

    enum CodingKeys: String, CodingKey {
        case id, text, ts, reactions, status
        case chatJid = "chat_jid", msgId = "msg_id"
        case senderName = "sender_name", fromMe = "from_me"
        case mediaType = "media_type", mediaUrl = "media_url"
        case quotedMsgId = "quoted_msg_id", quotedText = "quoted_text", quotedSender = "quoted_sender"
    }
}

// MARK: client

enum WAClient {
    static let rest = "https://cchnsizaeoqhgawkyugs.supabase.co/rest/v1"

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            if let date = withFrac.date(from: s) ?? plain.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "bad date \(s)"))
        }
        return d
    }()

    private static func request(_ method: String, _ path: String, token: String, body: Any? = nil, prefer: String? = nil) async throws -> Data {
        var req = URLRequest(url: URL(string: rest + path)!)
        req.httpMethod = method
        req.setValue(SupabaseAuthClient.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { req.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode < 400 else {
            throw AuthError.server("Sync hiccup (\((resp as? HTTPURLResponse)?.statusCode ?? 0)). Pull to retry.")
        }
        return data
    }

    static func account(token: String) async throws -> WAAccount? {
        let data = try await request("GET", "/wa_accounts?select=*&limit=1", token: token)
        return try decoder.decode([WAAccount].self, from: data).first
    }

    /// Kick off (or retry) pairing for this phone number.
    static func requestPairing(userId: String, phone: String, token: String) async throws {
        _ = try await request(
            "POST", "/wa_accounts?on_conflict=user_id", token: token,
            body: [["user_id": userId, "phone": phone, "status": "pending_pair", "pairing_code": NSNull(), "error": NSNull()]],
            prefer: "resolution=merge-duplicates,return=minimal"
        )
    }

    static func chats(token: String) async throws -> [WAChat] {
        let data = try await request("GET", "/wa_chats?select=*&order=last_message_at.desc.nullslast&limit=200", token: token)
        return try decoder.decode([WAChat].self, from: data)
    }

    static func messages(chatJid: String, token: String) async throws -> [WAMessage] {
        let jid = chatJid.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? chatJid
        let data = try await request("GET", "/wa_messages?select=*&chat_jid=eq.\(jid)&order=ts.desc&limit=200", token: token)
        return Array(try decoder.decode([WAMessage].self, from: data).reversed())
    }

    /// Queue an outbound message — the bridge picks it up and sends.
    static func send(userId: String, chatJid: String, text: String, replyTo: String? = nil, token: String) async throws {
        var row: [String: Any] = ["user_id": userId, "chat_jid": chatJid, "text": text]
        if let replyTo { row["reply_to_msg_id"] = replyTo }
        _ = try await request("POST", "/wa_outbox", token: token, body: [row], prefer: "return=minimal")
    }

    /// Queue a reaction (empty emoji removes it).
    static func react(userId: String, chatJid: String, msgId: String, emoji: String, token: String) async throws {
        _ = try await request(
            "POST", "/wa_outbox", token: token,
            body: [["user_id": userId, "chat_jid": chatJid, "text": "", "kind": "reaction",
                    "react_to_msg_id": msgId, "react_emoji": emoji]],
            prefer: "return=minimal"
        )
    }

    /// Tell the bridge to mark a chat read (syncs blue ticks to WhatsApp).
    static func markRead(userId: String, chatJid: String, token: String) async throws {
        _ = try await request(
            "POST", "/wa_commands", token: token,
            body: [["user_id": userId, "kind": "mark_read", "chat_jid": chatJid]],
            prefer: "return=minimal"
        )
    }

    // MARK: assistant (Edwin)

    static let assistantJid = "assistant@edwin"

    /// Make sure the pinned Edwin chat exists, with a welcome on first run.
    static func ensureAssistant(userId: String, token: String) async throws {
        let existing = try await messages(chatJid: assistantJid, token: token)
        _ = try await request("POST", "/wa_chats?on_conflict=user_id,jid", token: token,
            body: [["user_id": userId, "jid": assistantJid, "name": "Edwin",
                    "is_assistant": true, "pinned": true]],
            prefer: "resolution=merge-duplicates,return=minimal")
        guard existing.isEmpty else { return }
        let welcome = "hey, i'm edwin — your assistant. once your whatsapp is linked i'll watch your inbox, flag what actually needs you, and draft replies for you to approve. ask me anything, or tell me what to keep track of."
        _ = try await request("POST", "/wa_messages", token: token,
            body: [["user_id": userId, "chat_jid": assistantJid, "msg_id": "edwin-welcome",
                    "sender_jid": "edwin", "sender_name": "Edwin", "from_me": false,
                    "text": welcome, "ts": iso(Date())]],
            prefer: "resolution=ignore-duplicates,return=minimal")
        _ = try await request("POST", "/wa_chats?on_conflict=user_id,jid", token: token,
            body: [["user_id": userId, "jid": assistantJid, "name": "Edwin", "is_assistant": true,
                    "pinned": true, "last_message_text": welcome, "last_message_at": iso(Date()),
                    "last_sender": "Edwin"]],
            prefer: "resolution=merge-duplicates,return=minimal")
    }

    /// Owner speaks to Edwin: echo their message instantly, then queue the job.
    static func sendToAssistant(userId: String, text: String, mediaUrl: String? = nil, mediaType: String? = nil, token: String) async throws {
        let mid = "user-\(Int(Date().timeIntervalSince1970 * 1000))"
        var msg: [String: Any] = ["user_id": userId, "chat_jid": assistantJid, "msg_id": mid,
                                  "sender_jid": "me", "sender_name": "You", "from_me": true,
                                  "text": text.isEmpty ? "[photo]" : text, "ts": iso(Date())]
        if let mediaUrl { msg["media_url"] = mediaUrl; msg["media_type"] = mediaType ?? "image" }
        _ = try await request("POST", "/wa_messages", token: token,
            body: [msg], prefer: "resolution=ignore-duplicates,return=minimal")
        let jobText = mediaUrl != nil ? "\(text)\n[attached image: \(mediaUrl!)]" : text
        _ = try await request("POST", "/wa_outbox", token: token,
            body: [["user_id": userId, "chat_jid": assistantJid, "text": jobText, "kind": "assistant"]],
            prefer: "return=minimal")
    }

    /// Upload an attachment to storage; returns its public URL.
    static func uploadAttachment(userId: String, data: Data, ext: String, mime: String, token: String) async throws -> String {
        let path = "\(userId)/assistant/\(Int(Date().timeIntervalSince1970 * 1000)).\(ext)"
        var req = URLRequest(url: URL(string: "https://cchnsizaeoqhgawkyugs.supabase.co/storage/v1/object/wa-media/\(path)")!)
        req.httpMethod = "POST"
        req.setValue(SupabaseAuthClient.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(mime, forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode < 400 else {
            throw AuthError.server("Upload failed (\((resp as? HTTPURLResponse)?.statusCode ?? 0)).")
        }
        return "https://cchnsizaeoqhgawkyugs.supabase.co/storage/v1/object/public/wa-media/\(path)"
    }

    static func clearAssistantUnread(userId: String, token: String) async throws {
        _ = try await request("PATCH", "/wa_chats?user_id=eq.\(userId)&jid=eq.assistant@edwin", token: token,
            body: ["unread": 0], prefer: "return=minimal")
    }

    static func drafts(token: String) async throws -> [AssistantDraft] {
        let data = try await request("GET", "/assistant_drafts?status=eq.pending&select=*&order=created_at.desc", token: token)
        return try decoder.decode([AssistantDraft].self, from: data)
    }

    /// Approve a draft → queue it to the real chat and mark it approved.
    static func approveDraft(_ draft: AssistantDraft, userId: String, editedText: String? = nil, token: String) async throws {
        try await send(userId: userId, chatJid: draft.chatJid, text: editedText ?? draft.text, token: token)
        _ = try await request("PATCH", "/assistant_drafts?id=eq.\(draft.id)", token: token,
            body: ["status": editedText == nil ? "approved" : "edited"], prefer: "return=minimal")
    }

    static func dismissDraft(_ draft: AssistantDraft, token: String) async throws {
        _ = try await request("PATCH", "/assistant_drafts?id=eq.\(draft.id)", token: token,
            body: ["status": "dismissed"], prefer: "return=minimal")
    }

    private static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }
}

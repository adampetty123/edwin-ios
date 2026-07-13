import Foundation
import SwiftUI

/// Live WhatsApp state: account/pairing status, chats, per-chat messages.
/// Views drive polling via the refresh methods; this store holds the truth.
@MainActor
final class WAStore: ObservableObject {
    @Published var account: WAAccount?
    @Published var chats: [WAChat] = []
    @Published var messages: [String: [WAMessage]] = [:]

    weak var auth: AuthStore?

    var isConnected: Bool { account?.status == "connected" }

    private var token: String? { auth?.accessToken }

    func refreshAccount() async {
        guard let token else { return }
        if let a = try? await WAClient.account(token: token) {
            account = a
            if a.status == "connected" { auth?.setChannel(.whatsapp, connected: true) }
        }
    }

    func requestPairing(phone: String) async throws {
        guard let token, let userId = auth?.userId, !userId.isEmpty else {
            throw AuthError.server("Not signed in.")
        }
        try await WAClient.requestPairing(userId: userId, phone: phone, token: token)
        await refreshAccount()
    }

    func refreshChats() async {
        guard let token else { return }
        if let c = try? await WAClient.chats(token: token), c != chats {
            chats = c
        }
    }

    func refreshMessages(chatJid: String) async {
        guard let token else { return }
        if let m = try? await WAClient.messages(chatJid: chatJid, token: token), m != messages[chatJid] {
            messages[chatJid] = m
        }
    }

    func send(chatJid: String, text: String, replyTo: String? = nil) async throws {
        guard let token, let userId = auth?.userId, !userId.isEmpty else {
            throw AuthError.server("Not signed in.")
        }
        try await WAClient.send(userId: userId, chatJid: chatJid, text: text, replyTo: replyTo, token: token)
    }

    func react(chatJid: String, msgId: String, emoji: String) async {
        guard let token, let userId = auth?.userId, !userId.isEmpty else { return }
        try? await WAClient.react(userId: userId, chatJid: chatJid, msgId: msgId, emoji: emoji, token: token)
    }

    /// Optimistically zero the badge, then sync read state to WhatsApp itself.
    func markRead(chatJid: String) async {
        if let i = chats.firstIndex(where: { $0.jid == chatJid }), (chats[i].unread ?? 0) > 0 {
            chats[i].unread = 0
        }
        guard let token, let userId = auth?.userId, !userId.isEmpty else { return }
        try? await WAClient.markRead(userId: userId, chatJid: chatJid, token: token)
    }
}

import Intents
import UserNotifications

/// Turns WhatsApp pushes into communication notifications: the chat's photo is
/// the big avatar (where the app icon normally sits) and the Edwin icon shows
/// as the small corner badge — the iMessage layout. Falls back to a plain
/// image attachment when the intent path fails.
final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttempt: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        bestAttempt = (request.content.mutableCopy() as? UNMutableNotificationContent)
        guard let content = bestAttempt else { return contentHandler(request.content) }

        guard let urlString = request.content.userInfo["image_url"] as? String,
              let url = URL(string: urlString) else {
            return contentHandler(content)
        }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data else { return contentHandler(content) }
            let chatJid = (request.content.userInfo["chat_jid"] as? String) ?? "chat"
            let senderName = content.title

            // communication notification: sender identity carries the photo
            let sender = INPerson(
                personHandle: INPersonHandle(value: chatJid, type: .unknown),
                nameComponents: nil,
                displayName: senderName,
                image: INImage(imageData: data),
                contactIdentifier: nil,
                customIdentifier: chatJid
            )
            let intent = INSendMessageIntent(
                recipients: nil,
                outgoingMessageType: .outgoingMessageText,
                content: content.body,
                speakableGroupName: INSpeakableString(spokenPhrase: senderName),
                conversationIdentifier: chatJid,
                serviceName: "WhatsApp",
                sender: sender,
                attachments: nil
            )
            intent.setImage(INImage(imageData: data), forParameterNamed: \.sender)

            let interaction = INInteraction(intent: intent, response: nil)
            interaction.direction = .incoming
            interaction.donate { _ in }

            if let updated = try? request.content.updating(from: intent) {
                contentHandler(updated)
                return
            }

            // fallback: attach the photo the plain way
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".jpg")
            try? data.write(to: dest)
            if let attachment = try? UNNotificationAttachment(identifier: "chat-image", url: dest) {
                content.attachments = [attachment]
            }
            contentHandler(content)
        }.resume()
    }

    override func serviceExtensionTimeWillExpire() {
        if let content = bestAttempt { contentHandler?(content) }
    }
}

import UserNotifications

/// Downloads the chat's profile image (image_url in the push payload) and
/// attaches it, so WhatsApp notifications show the sender's photo.
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

        URLSession.shared.downloadTask(with: url) { tmpUrl, _, _ in
            defer { contentHandler(content) }
            guard let tmpUrl else { return }
            // attachment needs a proper extension to be recognised as an image
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".jpg")
            try? FileManager.default.moveItem(at: tmpUrl, to: dest)
            if let attachment = try? UNNotificationAttachment(identifier: "chat-image", url: dest) {
                content.attachments = [attachment]
            }
        }.resume()
    }

    override func serviceExtensionTimeWillExpire() {
        if let content = bestAttempt { contentHandler?(content) }
    }
}

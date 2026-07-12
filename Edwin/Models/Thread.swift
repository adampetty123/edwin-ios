import SwiftUI

struct MessageThread: Identifiable {
    let id: String
    let name: String
    let channel: Channel
    let preview: String
    let time: String
    var unread: Int
    let priority: Priority
    let avatarColor: Color
    let summary: String?

    enum Priority {
        case low, normal, high
    }
}

/// Placeholder inbox data — replaced by the ingest pipeline later.
enum MockData {
    static let threads: [MessageThread] = [
        MessageThread(
            id: "t1", name: "Mom", channel: .imessage,
            preview: "Are you still coming for dinner on Sunday?",
            time: "9:41 AM", unread: 2, priority: .high,
            avatarColor: Color(hex: 0xA65468),
            summary: "Wants to confirm Sunday dinner and asked you to bring dessert."
        ),
        MessageThread(
            id: "t2", name: "Design team", channel: .whatsapp,
            preview: "Priya: shipped the new onboarding, take a look when you're free",
            time: "9:12 AM", unread: 5, priority: .normal,
            avatarColor: Color(hex: 0x5E67A0),
            summary: nil
        ),
        MessageThread(
            id: "t3", name: "Daniel Reyes", channel: .whatsapp,
            preview: "Sounds good, let me check and get back to you",
            time: "Yesterday", unread: 0, priority: .normal,
            avatarColor: Color(hex: 0x3F8A7E),
            summary: nil
        ),
        MessageThread(
            id: "t4", name: "Landlord", channel: .imessage,
            preview: "The plumber can come Thursday between 2 and 4",
            time: "Yesterday", unread: 1, priority: .high,
            avatarColor: Color(hex: 0x4A6D9C),
            summary: "Needs a yes/no on the Thursday 2-4pm plumber slot."
        ),
        MessageThread(
            id: "t5", name: "Book club", channel: .whatsapp,
            preview: "Sam: next pick is 'Tomorrow, and Tomorrow, and Tomorrow'",
            time: "Mon", unread: 0, priority: .low,
            avatarColor: Color(hex: 0xA9803F),
            summary: nil
        ),
    ]
}

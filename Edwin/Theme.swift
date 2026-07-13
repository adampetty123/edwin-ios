import SwiftUI

/// Edwin design tokens. Monochrome + one violet accent, calm and message-first.
enum Theme {
    // structural
    static let bg = Color.white
    static let surface = Color(hex: 0xF7F7F8)
    static let surfaceAlt = Color(hex: 0xF0F0F2)
    static let border = Color(hex: 0xEAEAEC)

    // text
    static let text = Color(hex: 0x0B0B0F)
    static let textMuted = Color(hex: 0x6B6B73)
    static let textFaint = Color(hex: 0x9A9AA2)

    // one accent
    static let accent = Color(hex: 0x5B5BF0)
    static let accentSoft = Color(hex: 0xEEEEFE)

    // channels (functional wayfinding)
    static let whatsapp = Color(hex: 0x25D366)

    // chat bubbles — iMessage language
    static let bubbleMe = Color(hex: 0x007AFF)
    static let bubbleThem = Color(hex: 0xE9E9EB)
    static let imessage = Color(hex: 0x0A84FF)

    // status
    static let success = Color(hex: 0x1FB877)
    static let danger = Color(hex: 0xF0453A)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

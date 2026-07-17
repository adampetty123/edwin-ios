import SwiftUI

/// Edwin design tokens. Monochrome + one violet accent, calm and message-first.
/// Every color is adaptive: light value by day, dark value after sunset.
enum Theme {
    // structural
    static let bg = Color(light: 0xFFFFFF, dark: 0x000000)
    static let surface = Color(light: 0xF7F7F8, dark: 0x1C1C1E)
    static let surfaceAlt = Color(light: 0xF0F0F2, dark: 0x2C2C2E)
    static let border = Color(light: 0xEAEAEC, dark: 0x38383A)

    // text
    static let text = Color(light: 0x0B0B0F, dark: 0xF5F5F7)
    static let textMuted = Color(light: 0x6B6B73, dark: 0x98989F)
    static let textFaint = Color(light: 0x9A9AA2, dark: 0x63636B)

    // one accent
    static let accent = Color(light: 0x5B5BF0, dark: 0x8484F7)
    static let accentSoft = Color(light: 0xEEEEFE, dark: 0x23233C)

    // channels (functional wayfinding)
    static let whatsapp = Color(light: 0x25D366, dark: 0x25D366)

    // chat bubbles — iMessage language
    static let bubbleMe = Color(light: 0x007AFF, dark: 0x0A84FF)
    static let bubbleThem = Color(light: 0xE9E9EB, dark: 0x2C2C2E)
    static let imessage = Color(light: 0x0A84FF, dark: 0x0A84FF)

    // status
    static let success = Color(light: 0x1FB877, dark: 0x30D158)
    static let danger = Color(light: 0xF0453A, dark: 0xFF6961)
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

    /// Adaptive pair: resolves light or dark from the live interface style,
    /// so it also honors an in-app .preferredColorScheme override.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}


// MARK: liquid glass helpers
extension View {
    /// Liquid-glass capsule field: real glassEffect on iOS 26, material fallback earlier.
    @ViewBuilder
    func liquidGlassField() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .capsule)
        } else {
            self
                .background(Capsule().fill(.ultraThinMaterial))
                .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 0.5))
        }
    }

    /// Liquid-glass circle (for round composer buttons).
    @ViewBuilder
    func liquidGlassCircle() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .circle)
        } else {
            self
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 0.5))
        }
    }
}

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

// MARK: - Edwin's icon, drawn natively so its color is user-editable
// (Settings > Assistant > Assistant Settings). Mirrors the original asset:
// two pill eyes with dark pupils + glints on a colored square-ish field.

extension Color {
    /// "RRGGBB" → Color (nil on garbage input).
    init?(hexString: String) {
        let s = hexString.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(hex: v)
    }

    /// Color → "RRGGBB" for persistence.
    var hexString: String? {
        guard let c = UIColor(self).cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)?.components, c.count >= 3 else { return nil }
        let r = Int(round(c[0] * 255)), g = Int(round(c[1] * 255)), b = Int(round(c[2] * 255))
        return String(format: "%02X%02X%02X", r, g, b)
    }
}

struct EdwinIcon: View {
    var size: CGFloat = 48
    @AppStorage("assistant.iconColor") private var iconColorHex = EdwinIcon.defaultHex

    static let defaultHex = "2FD87E"   // the original green

    var body: some View {
        ZStack {
            Circle().fill(Color(hexString: iconColorHex) ?? Color(hex: 0x2FD87E))
            HStack(spacing: size * 0.09) {
                eye
                eye
            }
            .offset(y: -size * 0.01)
        }
        .frame(width: size, height: size)
    }

    private var eye: some View {
        let w = size * 0.26
        let h = size * 0.60
        return RoundedRectangle(cornerRadius: w / 2, style: .continuous)
            .fill(Color(hex: 0xFCE9F1))
            .frame(width: w, height: h)
            .overlay(alignment: .bottom) {
                RoundedRectangle(cornerRadius: w * 0.30, style: .continuous)
                    .fill(Color(hex: 0x532040))
                    .frame(width: w * 0.64, height: h * 0.56)
                    .overlay(alignment: .topTrailing) {
                        Circle()
                            .fill(.white)
                            .frame(width: w * 0.20, height: w * 0.20)
                            .padding(w * 0.10)
                    }
                    .padding(.bottom, h * 0.10)
            }
    }
}

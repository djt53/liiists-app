import SwiftUI

// MARK: - Nothing Design Color Tokens

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Adaptive color that switches between dark and light mode values.
struct AdaptiveColor {
    let dark: Color
    let light: Color

    func resolve(for scheme: ColorScheme) -> Color {
        scheme == .dark ? dark : light
    }
}

// MARK: - Theme

enum Theme {

    // MARK: - Colors (Dark Mode Defaults)

    static let ndBlack = AdaptiveColor(dark: Color(hex: 0x000000), light: Color(hex: 0xF5F5F5))
    static let ndSurface = AdaptiveColor(dark: Color(hex: 0x111111), light: Color(hex: 0xFFFFFF))
    static let ndSurfaceRaised = AdaptiveColor(dark: Color(hex: 0x1A1A1A), light: Color(hex: 0xF0F0F0))
    static let ndBorder = AdaptiveColor(dark: Color(hex: 0x222222), light: Color(hex: 0xE8E8E8))
    static let ndBorderVisible = AdaptiveColor(dark: Color(hex: 0x333333), light: Color(hex: 0xCCCCCC))
    static let ndTextDisabled = AdaptiveColor(dark: Color(hex: 0x666666), light: Color(hex: 0x999999))
    static let ndTextSecondary = AdaptiveColor(dark: Color(hex: 0x999999), light: Color(hex: 0x666666))
    static let ndTextPrimary = AdaptiveColor(dark: Color(hex: 0xE8E8E8), light: Color(hex: 0x1A1A1A))
    static let ndTextDisplay = AdaptiveColor(dark: .white, light: .black)

    // Accent — signal red, one per screen, never decorative
    static let ndAccent = Color(hex: 0xD71921)
    static let ndAccentSubtle = Color(hex: 0xD71921).opacity(0.15)

    // Status
    static let ndSuccess = Color(hex: 0x4A9E5C)
    static let ndWarning = Color(hex: 0xD4A843)
    static let ndInteractive = AdaptiveColor(dark: Color(hex: 0x5B9BF6), light: Color(hex: 0x007AFF))

    // Legacy bridge
    static let accent = Color("AccentColor")

    // MARK: - Typography

    /// Display — Doto, 36px+ only, tight tracking
    static func displayFont(size: CGFloat) -> Font {
        .custom("Doto-Black_Regular", size: max(size, 36))
    }

    /// Heading — Space Grotesk
    static func headingFont(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "SpaceGrotesk-Light_Bold"
        case .medium, .semibold: name = "SpaceGrotesk-Light_Medium"
        default: name = "SpaceGrotesk-Light_Regular"
        }
        return .custom(name, size: size)
    }

    /// Body — Space Grotesk
    static func bodyFont(size: CGFloat = 16, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "SpaceGrotesk-Light_Bold"
        case .medium, .semibold: name = "SpaceGrotesk-Light_Medium"
        default: name = "SpaceGrotesk-Light_Regular"
        }
        return .custom(name, size: size)
    }

    /// Label — Space Mono, ALL CAPS, wide tracking
    static func labelFont(size: CGFloat = 11) -> Font {
        .custom("SpaceMono-Regular", size: size)
    }

    /// Data / monospace — Space Mono
    static func monoFont(size: CGFloat = 16, weight: Font.Weight = .regular) -> Font {
        let name = (weight == .bold || weight == .heavy || weight == .black)
            ? "SpaceMono-Bold" : "SpaceMono-Regular"
        return .custom(name, size: size)
    }

    // MARK: - Type Scale

    static let displayXL: CGFloat = 72
    static let displayLG: CGFloat = 48
    static let displayMD: CGFloat = 36
    static let headingSize: CGFloat = 24
    static let subheadingSize: CGFloat = 18
    static let bodySize: CGFloat = 16
    static let bodySM: CGFloat = 14
    static let captionSize: CGFloat = 12
    static let labelSize: CGFloat = 11

    // MARK: - Spacing (8px base)

    static let space2XS: CGFloat = 2
    static let spaceXS: CGFloat = 4
    static let spaceSM: CGFloat = 8
    static let spaceMD: CGFloat = 16
    static let spaceLG: CGFloat = 24
    static let spaceXL: CGFloat = 32
    static let space2XL: CGFloat = 48
    static let space3XL: CGFloat = 64
    static let space4XL: CGFloat = 96

    // MARK: - Sizing

    static let checkboxSize: CGFloat = 24
    static let checkboxStroke: CGFloat = 2
    static let cornerRadius: CGFloat = 8
    static let cardCornerRadius: CGFloat = 16
    static let rowMinHeight: CGFloat = 44
    static let buttonMinHeight: CGFloat = 44
    static let pillRadius: CGFloat = 999

    // MARK: - Motion

    static let microDuration: Double = 0.2
    static let transitionDuration: Double = 0.35
    static let nothingEasing = Animation.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.2)

}

// MARK: - Nothing Label Style (ALL CAPS + tracking)

struct NothingLabelStyle: ViewModifier {
    var size: CGFloat = Theme.labelSize
    var color: Color = Color(hex: 0x999999)

    func body(content: Content) -> some View {
        content
            .font(Theme.labelFont(size: size))
            .textCase(.uppercase)
            .tracking(size * 0.08)
            .foregroundStyle(color)
    }
}

extension View {
    func nothingLabel(size: CGFloat = Theme.labelSize, color: Color = Color(hex: 0x999999)) -> some View {
        modifier(NothingLabelStyle(size: size, color: color))
    }
}

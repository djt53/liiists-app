import SwiftUI
import UIKit

enum Theme {
    // MARK: - Accent

    /// Single accent color used for all interactive elements.
    static let accent = Color("AccentColor")

    // MARK: - Sizing

    static let checkboxSize: CGFloat = 24
    static let checkboxStroke: CGFloat = 2
    static let cornerRadius: CGFloat = 10
    static let cardCornerRadius: CGFloat = 12
    static let rowMinHeight: CGFloat = 44

    // MARK: - Haptics

    static func lightHaptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func mediumHaptic() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

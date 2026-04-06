import UIKit

extension Theme {
    static func lightHaptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func mediumHaptic() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

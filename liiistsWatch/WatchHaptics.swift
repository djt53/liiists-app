import WatchKit

extension Theme {
    /// Light tap — for affirmative micro-actions (item toggled, dictation
    /// recognized). Watch uses haptic feedback, not the iOS UIImpactGenerator.
    static func lightHaptic() {
        WKInterfaceDevice.current().play(.click)
    }

    /// Medium tap — for state changes that deserve emphasis (entry sent,
    /// payload queued, complication refreshed).
    static func mediumHaptic() {
        WKInterfaceDevice.current().play(.success)
    }

    /// Warning tap — when a send fails or a queue overflows.
    static func warningHaptic() {
        WKInterfaceDevice.current().play(.failure)
    }
}

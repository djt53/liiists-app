import Foundation

/// Content policy + acceptance gate for publishing to Discover.
///
/// Apple guideline 1.2 (UGC): apps must have (1) a method to filter
/// objectionable content, (2) a way for users to flag, (3) a way to block,
/// and (4) the developer must act on flagged content within 24 hours.
///
/// The EULA covers (1) — users agree to a no-tolerance policy. T-51i
/// (Report) and T-51j (Block) cover (2) and (3). Decision 007.
///
/// Acceptance is persisted in Keychain — key tracks the *version* the user
/// agreed to. Bumping `currentVersion` invalidates prior acceptances and
/// requires a re-prompt. Acceptance gates publish actions only; the rest
/// of the app remains usable without it.
enum EULA {
    /// Bump when the policy text materially changes. All users will
    /// re-prompt on their next publish action.
    static let currentVersion: Int = 1

    static let lastUpdated: String = "May 3, 2026"

    /// Policy text shown in the EULASheet. Plain markdown-flavored prose.
    /// The bullet list mirrors the hard requirements of guideline 1.2.
    static let policyText: String = """
By publishing lists to Discover, you agree to the following.

Don't publish content that:
• Contains hate speech, harassment, threats, or targeted abuse
• Is sexually explicit, gratuitously violent, or graphic
• Promotes illegal activity
• Is spam, scams, or intentionally deceptive
• Reveals private information about others without consent
• Infringes copyright, trademark, or other rights

You are responsible for everything you publish. Lists go live immediately. liiists does not pre-review them.

Reported content will be reviewed within 24 hours. Lists that violate this policy will be removed. Repeat violations lead to a ban from publishing.

This policy may change. Continued publishing after changes means you accept the updated policy.
"""

    private enum Keys {
        static let acceptedVersion = "liiists.eulaAcceptedVersion"
        static let acceptedAt = "liiists.eulaAcceptedAt"
    }

    /// Whether the user has accepted the *current* version.
    static var isAccepted: Bool {
        guard let raw = EULAKeychain.get(Keys.acceptedVersion),
              let v = Int(raw) else { return false }
        return v >= currentVersion
    }

    /// ISO8601 timestamp of acceptance, if accepted.
    static var acceptedAt: Date? {
        guard let raw = EULAKeychain.get(Keys.acceptedAt) else { return nil }
        return ISO8601DateFormatter().date(from: raw)
    }

    /// Record acceptance of the current version.
    static func accept() {
        EULAKeychain.set(String(currentVersion), for: Keys.acceptedVersion)
        EULAKeychain.set(ISO8601DateFormatter().string(from: Date()), for: Keys.acceptedAt)
    }

    /// Clear acceptance — used only for sign-out / debug.
    static func revoke() {
        EULAKeychain.delete(Keys.acceptedVersion)
        EULAKeychain.delete(Keys.acceptedAt)
    }
}

/// Minimal Keychain wrapper scoped to EULA storage. Mirrors the pattern
/// used in AccountStore but kept private here so EULA stays self-contained.
private enum EULAKeychain {
    static func set(_ value: String?, for key: String) {
        guard let value, let data = value.data(using: .utf8) else {
            delete(key)
            return
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

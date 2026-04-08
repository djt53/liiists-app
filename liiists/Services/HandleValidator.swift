import Foundation

/// Validation rules for user-chosen handles shown on published lists.
/// Decision 008: lowercase letters, digits, underscores, 3–20 chars.
enum HandleValidator {
    static let minLength = 3
    static let maxLength = 20

    enum Result: Equatable {
        case valid
        case empty
        case tooShort
        case tooLong
        case invalidCharacters

        var message: String? {
            switch self {
            case .valid, .empty: return nil
            case .tooShort: return "At least \(HandleValidator.minLength) characters."
            case .tooLong: return "Up to \(HandleValidator.maxLength) characters."
            case .invalidCharacters: return "Only lowercase letters, digits, and underscores."
            }
        }
    }

    static func validate(_ raw: String) -> Result {
        if raw.isEmpty { return .empty }
        if raw.count < minLength { return .tooShort }
        if raw.count > maxLength { return .tooLong }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_")
        if raw.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            return .invalidCharacters
        }
        return .valid
    }
}

import Foundation
import SwiftUI

#if canImport(FoundationModels)
import FoundationModels
#endif

/// On-device AI augmentation for lists. See decision 011.
///
/// Uses Apple Foundation Models (iOS 26+, Apple Intelligence-capable devices).
/// Free for the first `freeUseLimit` successful generations per device, then
/// the view presents the paywall instead of generating.
@MainActor
final class IntelligenceStore: ObservableObject {
    /// Whether the on-device model is currently usable. Drives menu visibility
    /// in `ListView`. Re-checked at init and on every `requestSuggestions` call
    /// so device-state changes (Apple Intelligence toggling, model download
    /// completing) flow through without a relaunch.
    @Published private(set) var aiAvailable: Bool = false

    /// Successful generation count, persisted per-device. Increments only when
    /// generation returns at least one usable suggestion — failures, cancels,
    /// and empty results are free.
    @AppStorage("intelligence_usage_count") private var usageCount: Int = 0

    /// Hardcoded paywall threshold from decision 011.
    static let freeUseLimit = 5

    enum Outcome {
        case suggestions([String])
        case paywallRequired
        case unavailable(String)
    }

    init() {
        refreshAvailability()
    }

    var remainingFreeUses: Int {
        max(0, Self.freeUseLimit - usageCount)
    }

    /// Re-evaluate `aiAvailable` against the system language model. Cheap to
    /// call repeatedly.
    func refreshAvailability() {
        if #available(iOS 26.0, *) {
            aiAvailable = checkAvailableOniOS26()
        } else {
            aiAvailable = false
        }
    }

    /// Whether the next `requestSuggestions` call would hit the paywall.
    /// View layer reads this BEFORE presenting `SuggestMoreSheet` so it can
    /// route directly to `PaywallSheet` instead.
    var shouldPresentPaywall: Bool {
        !Paywall.shared.isPro && usageCount >= Self.freeUseLimit
    }

    /// Generate 5–8 suggestions for the given list. Returns `.paywallRequired`
    /// when the user has exhausted their free uses (the view layer should
    /// present `PaywallSheet` instead of the result sheet — T-156).
    func requestSuggestions(for list: ItemList) async -> Outcome {
        refreshAvailability()
        guard aiAvailable else {
            return .unavailable("Suggest More needs Apple Intelligence on iOS 26 or later.")
        }
        if shouldPresentPaywall {
            return .paywallRequired
        }

        if #available(iOS 26.0, *) {
            return await generateOniOS26(for: list)
        } else {
            return .unavailable("Suggest More needs Apple Intelligence on iOS 26 or later.")
        }
    }

    // MARK: - iOS 26 Foundation Models

    @available(iOS 26.0, *)
    private func checkAvailableOniOS26() -> Bool {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            return true
        default:
            return false
        }
        #else
        return false
        #endif
    }

    @available(iOS 26.0, *)
    private func generateOniOS26(for list: ItemList) async -> Outcome {
        #if canImport(FoundationModels)
        let prompt = Self.buildPrompt(for: list)
        let session = LanguageModelSession()
        do {
            let response = try await session.respond(
                to: prompt,
                generating: SuggestionResponse.self
            )
            let cleaned = response.content.suggestions
                .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .filter { candidate in
                    !Self.isLikelyDuplicate(candidate: candidate, of: list.items)
                }
            guard !cleaned.isEmpty else {
                return .unavailable("No new suggestions came back. Try again with a few more items on the list.")
            }
            usageCount += 1
            return .suggestions(cleaned)
        } catch {
            return .unavailable(error.localizedDescription)
        }
        #else
        return .unavailable("FoundationModels framework is not available in this build.")
        #endif
    }

    private static func buildPrompt(for list: ItemList) -> String {
        // Keep this prompt tight — Apple's on-device model has a small context
        // window, and the @Generable schema + completion budget eat into it.
        // Earlier longer prompts hit "Exceeded model context window size".
        let existing = list.items.map { "- \($0.text)" }.joined(separator: "\n")
        return """
        List: "\(list.title)"
        Items:
        \(existing)

        Suggest 5 new items that fit this list. Match the existing format (if items include artist/author/year, yours should too). Each suggestion must be different from every existing item — no rewording or stripping details. Items only, no commentary.
        """
    }

    /// True if `candidate` is likely the same entry as one of `existing` —
    /// catches both exact matches and the common LLM failure mode of returning
    /// an existing item with extra context stripped (e.g. "Kind of Blue" vs.
    /// "Kind of Blue — Miles Davis"). We compare normalized prefixes so
    /// "Mingus Ah Um" matches "Mingus Ah Um — Charles Mingus".
    static func isLikelyDuplicate(candidate: String, of existing: [ListItem]) -> Bool {
        let normalizedCandidate = normalize(candidate)
        guard !normalizedCandidate.isEmpty else { return true }
        for item in existing {
            let normalizedExisting = normalize(item.text)
            if normalizedCandidate == normalizedExisting { return true }
            // Substring-style match: either is contained in the other after
            // stripping the suffix at the first separator (— – : - |).
            let candidateHead = headBeforeSeparator(normalizedCandidate)
            let existingHead = headBeforeSeparator(normalizedExisting)
            if !candidateHead.isEmpty && candidateHead == existingHead { return true }
            if !candidateHead.isEmpty && normalizedExisting.hasPrefix(candidateHead) { return true }
            if !existingHead.isEmpty && normalizedCandidate.hasPrefix(existingHead) { return true }
        }
        return false
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: .diacriticInsensitive, locale: .current)
    }

    private static func headBeforeSeparator(_ text: String) -> String {
        let separators: [Character] = ["—", "–", ":", "-", "|", "·"]
        guard let idx = text.firstIndex(where: { separators.contains($0) }) else {
            return ""
        }
        return String(text[..<idx]).trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Generable schema (iOS 26+)

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct Suggestion {
    @Guide(description: "A new list entry.")
    let text: String
}

@available(iOS 26.0, *)
@Generable
struct SuggestionResponse {
    @Guide(description: "5 new items.")
    let suggestions: [Suggestion]
}
#endif

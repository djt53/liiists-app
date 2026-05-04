import SwiftUI

/// Result-review sheet for the "Suggest More" feature. Shows generated items
/// with per-row toggles so the user can curate before commit. See decision 011.
struct SuggestMoreSheet: View {
    @EnvironmentObject private var intelligence: IntelligenceStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    let list: ItemList
    /// Called with the user's selected suggestions. The parent appends these
    /// to the list and animates them in.
    let onAccept: ([String]) -> Void

    enum Phase: Equatable {
        case loading
        case loaded([Suggestion])
        case error(String)
        case empty
    }

    struct Suggestion: Identifiable, Equatable {
        let id = UUID()
        let text: String
        var selected: Bool = true
    }

    @State private var phase: Phase = .loading

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, Theme.spaceLG)

            switch phase {
            case .loading:
                loadingState
            case .loaded(let suggestions):
                loadedState(suggestions)
            case .error(let message):
                errorState(message)
            case .empty:
                emptyState
            }
        }
        .padding(.horizontal, Theme.spaceLG)
        .padding(.top, Theme.spaceXL)
        .padding(.bottom, Theme.spaceLG)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.ndBlack.resolve(for: colorScheme))
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            await generate()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.spaceXS) {
            Text("SUGGEST MORE")
                .font(Theme.labelFont(size: Theme.labelSize))
                .tracking(Theme.labelSize * 0.1)
                .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
            Text(list.title)
                .font(Theme.headingFont(size: Theme.headingSize, weight: .medium))
                .foregroundStyle(Theme.ndTextDisplay.resolve(for: colorScheme))
                .tracking(-0.01 * Theme.headingSize)
        }
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: Theme.spaceMD) {
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .fill(Theme.ndSurfaceRaised.resolve(for: colorScheme))
                    .frame(height: 44)
                    .opacity(0.6)
            }
            Spacer(minLength: 0)
            Text("Thinking…")
                .font(Theme.labelFont(size: Theme.labelSize))
                .tracking(Theme.labelSize * 0.1)
                .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, Theme.spaceMD)
        }
    }

    private func loadedState(_ suggestions: [Suggestion]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(suggestions) { suggestion in
                        suggestionRow(suggestion)
                            .overlay(alignment: .bottom) {
                                Rectangle()
                                    .frame(height: 1)
                                    .foregroundStyle(Theme.ndBorder.resolve(for: colorScheme))
                            }
                    }
                }
            }
            .scrollIndicators(.hidden)

            Spacer(minLength: Theme.spaceMD)

            primaryButton(
                title: addButtonTitle(suggestions),
                enabled: suggestions.contains(where: \.selected)
            ) {
                let chosen = suggestions.filter(\.selected).map(\.text)
                Analytics.suggestMoreAdded(
                    listTitle: list.title,
                    selectedCount: chosen.count,
                    totalCount: suggestions.count
                )
                onAccept(chosen)
                Theme.lightHaptic()
                dismiss()
            }

            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .font(Theme.bodyFont(weight: .medium))
                    .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                    .frame(maxWidth: .infinity, minHeight: Theme.buttonMinHeight)
            }
        }
    }

    private func suggestionRow(_ suggestion: Suggestion) -> some View {
        Button {
            withAnimation(Theme.nothingEasing) {
                toggle(suggestion)
            }
            Theme.lightHaptic()
        } label: {
            HStack(spacing: Theme.spaceSM) {
                checkboxIcon(checked: suggestion.selected)
                Text(suggestion.text)
                    .font(Theme.bodyFont())
                    .foregroundStyle(
                        suggestion.selected
                            ? Theme.ndTextPrimary.resolve(for: colorScheme)
                            : Theme.ndTextDisabled.resolve(for: colorScheme)
                    )
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .frame(minHeight: Theme.rowMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func checkboxIcon(checked: Bool) -> some View {
        if checked {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: Theme.checkboxSize))
                .foregroundStyle(Theme.ndSuccess)
        } else {
            Circle()
                .strokeBorder(
                    Theme.ndBorderVisible.resolve(for: colorScheme),
                    lineWidth: Theme.checkboxStroke
                )
                .frame(width: Theme.checkboxSize, height: Theme.checkboxSize)
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.spaceMD) {
            Text(message)
                .font(Theme.bodyFont())
                .foregroundStyle(Theme.ndTextPrimary.resolve(for: colorScheme))

            Spacer(minLength: 0)

            primaryButton(title: "Try Again", enabled: true) {
                Task { await generate() }
            }

            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .font(Theme.bodyFont(weight: .medium))
                    .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                    .frame(maxWidth: .infinity, minHeight: Theme.buttonMinHeight)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.spaceMD) {
            Text("Couldn't find new items that fit. The AI sometimes gets stuck on what's already there — give it another try.")
                .font(Theme.bodyFont())
                .foregroundStyle(Theme.ndTextPrimary.resolve(for: colorScheme))

            Spacer(minLength: 0)

            primaryButton(title: "Try Again", enabled: true) {
                Task { await generate() }
            }

            Button {
                dismiss()
            } label: {
                Text("Close")
                    .font(Theme.bodyFont(weight: .medium))
                    .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                    .frame(maxWidth: .infinity, minHeight: Theme.buttonMinHeight)
            }
        }
    }

    // MARK: - Helpers

    private func primaryButton(title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.bodyFont(weight: .medium))
                .frame(maxWidth: .infinity, minHeight: Theme.buttonMinHeight)
                .foregroundStyle(Theme.ndBlack.resolve(for: colorScheme))
                .background(
                    enabled
                        ? Theme.ndTextDisplay.resolve(for: colorScheme)
                        : Theme.ndTextDisabled.resolve(for: colorScheme)
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        }
        .disabled(!enabled)
    }

    private func addButtonTitle(_ suggestions: [Suggestion]) -> String {
        let count = suggestions.filter(\.selected).count
        if count == 0 { return "Select Items to Add" }
        if count == 1 { return "Add 1 Item" }
        return "Add \(count) Items"
    }

    private func toggle(_ suggestion: Suggestion) {
        guard case .loaded(var current) = phase else { return }
        guard let idx = current.firstIndex(where: { $0.id == suggestion.id }) else { return }
        current[idx].selected.toggle()
        phase = .loaded(current)
    }

    private func generate() async {
        phase = .loading
        Analytics.suggestMoreInvoked(listTitle: list.title, itemCount: list.items.count)
        let outcome = await intelligence.requestSuggestions(for: list)
        switch outcome {
        case .suggestions(let texts):
            if texts.isEmpty {
                phase = .empty
                Analytics.suggestMoreFailed(listTitle: list.title, errorType: "empty_response")
            } else {
                phase = .loaded(texts.map { Suggestion(text: $0) })
                Analytics.suggestMoreSucceeded(listTitle: list.title, itemCount: texts.count)
            }
        case .paywallRequired:
            // Parent should be presenting `PaywallSheet` instead of this view
            // (T-156). If we get here it means the parent forgot to gate;
            // fall back to a graceful error rather than silently misbehaving.
            phase = .error("You've used your 5 free Suggest More tries. Upgrade to liiists Pro for unlimited.")
            Analytics.suggestMorePaywallHit(listTitle: list.title)
        case .unavailable(let message):
            phase = .error(message)
            Analytics.suggestMoreFailed(listTitle: list.title, errorType: "unavailable")
        }
    }
}

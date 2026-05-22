import SwiftUI

/// Modal shown when a user attempts to publish without having accepted the
/// current content policy version. Required for App Store guideline 1.2.
/// Decision 007.
///
/// Two outcomes: accept (records `EULA.accept()` and calls `onAccept`) or
/// decline (calls `onDecline` and dismisses). Cannot be interactively
/// dismissed — declining is the only way to back out.
struct EULASheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: Theme.spaceXS) {
                Text("Content Policy")
                    .font(Theme.headingFont(size: Theme.headingSize, weight: .medium))
                    .foregroundStyle(Theme.ndTextDisplay.resolve(for: colorScheme))
                Text("Last updated \(EULA.lastUpdated)")
                    .font(Theme.bodyFont(size: Theme.captionSize))
                    .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
            }
            .padding(.bottom, Theme.spaceLG)

            // Policy body — scrollable
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spaceMD) {
                    Text(EULA.policyText)
                        .font(Theme.bodyFont())
                        .foregroundStyle(Theme.ndTextPrimary.resolve(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Apple guideline 1.2 — in-app contact for UGC reports.
                    Button {
                        if let url = URL(string: "mailto:david@enigmastudio.app?subject=liiists%20content%20report") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: Theme.spaceXS) {
                            Image(systemName: "envelope")
                                .font(.system(size: 13, weight: .regular))
                            Text("Contact support")
                                .font(Theme.bodyFont(size: Theme.bodySM, weight: .medium))
                        }
                        .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Actions
            VStack(spacing: Theme.spaceSM) {
                Button {
                    EULA.accept()
                    Theme.mediumHaptic()
                    onAccept()
                    dismiss()
                } label: {
                    Text("I Agree")
                        .font(Theme.bodyFont(weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: Theme.buttonMinHeight)
                        .foregroundStyle(Theme.ndBlack.resolve(for: colorScheme))
                        .background(Theme.ndTextDisplay.resolve(for: colorScheme))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                }

                Button {
                    onDecline()
                    dismiss()
                } label: {
                    Text("Decline")
                        .font(Theme.bodyFont())
                        .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                        .frame(maxWidth: .infinity, minHeight: Theme.buttonMinHeight)
                }
            }
            .padding(.top, Theme.spaceLG)
        }
        .padding(.horizontal, Theme.spaceLG)
        .padding(.top, Theme.spaceXL)
        .padding(.bottom, Theme.spaceLG)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.ndBlack.resolve(for: colorScheme))
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(true)
    }
}

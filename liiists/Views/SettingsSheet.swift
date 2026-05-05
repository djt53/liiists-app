import SwiftUI

/// Minimal settings sheet — Pro status, Restore Purchases, About.
/// Apple requires Restore Purchases to be reachable without hitting the paywall.
struct SettingsSheet: View {
    @ObservedObject var paywall: Paywall
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var showPaywall = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("SETTINGS")
                    .font(Theme.labelFont(size: 13))
                    .tracking(13 * 0.08)
                    .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                        .frame(width: 44, height: 44)
                }
            }
            .padding(.leading, Theme.spaceLG)
            .padding(.trailing, Theme.spaceMD)
            .padding(.top, Theme.spaceSM)

            Spacer().frame(height: Theme.spaceXL)

            // Pro status block
            VStack(alignment: .leading, spacing: Theme.spaceSM) {
                Text("STATUS")
                    .nothingLabel(color: Theme.ndTextSecondary.resolve(for: colorScheme))

                if paywall.isPro {
                    HStack(spacing: Theme.spaceSM) {
                        Rectangle()
                            .fill(Theme.ndAccent)
                            .frame(width: 8, height: 8)
                        Text("liiists Pro")
                            .font(Theme.headingFont(size: 22))
                            .foregroundStyle(Theme.ndTextDisplay.resolve(for: colorScheme))
                    }
                    Text("Unlimited lists. Yours forever.")
                        .font(Theme.bodyFont(size: 14))
                        .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                } else {
                    Text("Free")
                        .font(Theme.headingFont(size: 22))
                        .foregroundStyle(Theme.ndTextDisplay.resolve(for: colorScheme))
                    Text("Up to \(Paywall.freeListCap) lists")
                        .font(Theme.bodyFont(size: 14))
                        .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))

                    Button {
                        showPaywall = true
                    } label: {
                        Text("UPGRADE TO PRO")
                            .font(Theme.labelFont(size: 12))
                            .tracking(12 * 0.08)
                            .foregroundStyle(Theme.ndBlack.resolve(for: colorScheme))
                            .padding(.horizontal, Theme.spaceLG)
                            .frame(height: 44)
                            .frame(maxWidth: .infinity)
                            .background(Theme.ndTextDisplay.resolve(for: colorScheme))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, Theme.spaceMD)
                }
            }
            .padding(.horizontal, Theme.spaceLG)

            Spacer().frame(height: Theme.space2XL)

            // Actions
            VStack(spacing: 0) {
                settingsRow(label: "Restore Purchases") {
                    Task {
                        await paywall.restorePurchases()
                    }
                }

                Divider()
                    .background(Theme.ndBorder.resolve(for: colorScheme))

                settingsRow(label: "About liiists") {
                    // Future: about sheet
                }
            }
            .padding(.horizontal, Theme.spaceLG)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.ndBlack.resolve(for: colorScheme))
        .sheet(isPresented: $showPaywall) {
            PaywallSheet(paywall: paywall, reason: "settings_upgrade")
        }
    }

    private func settingsRow(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(Theme.bodyFont(size: 16))
                    .foregroundStyle(Theme.ndTextPrimary.resolve(for: colorScheme))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .light))
                    .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
            }
            .frame(height: 56)
        }
        .buttonStyle(.plain)
    }
}

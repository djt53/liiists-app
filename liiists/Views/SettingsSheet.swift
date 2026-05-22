import SwiftUI

/// Minimal settings sheet — Pro status, Restore Purchases, About.
/// Apple requires Restore Purchases to be reachable without hitting the paywall.
///
/// **v1.0 ships with the paywall disabled.** The `paywallEnabled` flag below
/// hides the Pro status block and Restore Purchases row. Flip to `true`
/// alongside `Paywall.freeListCap` and `IntelligenceStore.freeUseLimit` when
/// reactivating monetization.
struct SettingsSheet: View {
    @ObservedObject var paywall: Paywall
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var showPaywall = false

    private let paywallEnabled = false

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

            // Pro status block — hidden in v1.0 (paywall disabled)
            if paywallEnabled {
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
            }

            // Actions
            VStack(spacing: 0) {
                if paywallEnabled {
                    settingsRow(label: "Restore Purchases") {
                        Task {
                            await paywall.restorePurchases()
                        }
                    }

                    Divider()
                        .background(Theme.ndBorder.resolve(for: colorScheme))
                }

                // Apple guideline 1.2 — in-app contact info for UGC reports.
                settingsRow(label: "Contact support") {
                    if let url = URL(string: "mailto:david@enigmastudio.app?subject=liiists%20support") {
                        UIApplication.shared.open(url)
                    }
                }

                Divider()
                    .background(Theme.ndBorder.resolve(for: colorScheme))

                settingsRow(label: "Privacy policy") {
                    if let url = URL(string: "https://djt53.github.io/liiists-www/privacy/") {
                        UIApplication.shared.open(url)
                    }
                }
            }
            .padding(.horizontal, Theme.spaceLG)

            Spacer()

            // About block — replaces the empty-tap About row. Apple Review
            // sees an actual developer + contact at the bottom of Settings.
            VStack(alignment: .leading, spacing: Theme.spaceXS) {
                Text("liiists")
                    .font(Theme.bodyFont(size: 14, weight: .medium))
                    .foregroundStyle(Theme.ndTextPrimary.resolve(for: colorScheme))
                Text("Made by Enigma Studio Inc.")
                    .font(Theme.bodyFont(size: 13))
                    .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                Text("david@enigmastudio.app")
                    .font(Theme.monoFont(size: 12))
                    .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.spaceLG)
            .padding(.bottom, Theme.spaceLG)
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

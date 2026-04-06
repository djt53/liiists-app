import SwiftUI
import StoreKit

/// Nothing-design paywall presented when a free user attempts to create
/// a 6th list (or from Settings as an upgrade prompt).
struct PaywallSheet: View {
    @ObservedObject var paywall: Paywall
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    let reason: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top bar — close button only
            HStack {
                Spacer()
                Button {
                    Analytics.paywallDismissed(reason: reason)
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                        .frame(width: 44, height: 44)
                }
            }
            .padding(.horizontal, Theme.spaceMD)
            .padding(.top, Theme.spaceSM)

            Spacer().frame(height: Theme.space2XL)

            // Headline
            VStack(alignment: .leading, spacing: Theme.spaceLG) {
                Text("YOU'RE USING ALL\n5 FREE LISTS")
                    .nothingLabel(size: 13, color: Theme.ndTextSecondary.resolve(for: colorScheme))

                Text("liiists\nPro")
                    .font(Theme.displayFont(size: Theme.displayLG))
                    .foregroundStyle(Theme.ndTextDisplay.resolve(for: colorScheme))
                    .lineSpacing(-8)
            }
            .padding(.horizontal, Theme.spaceLG)

            Spacer().frame(height: Theme.space2XL)

            // Promise
            VStack(alignment: .leading, spacing: Theme.spaceMD) {
                promiseRow("Unlimited lists")
                promiseRow("All future Pro features")
                promiseRow("One-time payment")
                promiseRow("Yours forever")
            }
            .padding(.horizontal, Theme.spaceLG)

            Spacer()

            // CTA
            VStack(spacing: Theme.spaceMD) {
                Button {
                    Task {
                        await paywall.purchase()
                        if paywall.isPro { dismiss() }
                    }
                } label: {
                    HStack {
                        if paywall.purchaseInFlight {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(Theme.ndBlack.resolve(for: colorScheme))
                        } else {
                            Text("UNLOCK")
                                .font(Theme.labelFont(size: 13))
                                .tracking(13 * 0.08)
                            Spacer()
                            Text(priceText)
                                .font(Theme.labelFont(size: 13))
                                .tracking(13 * 0.08)
                        }
                    }
                    .foregroundStyle(Theme.ndBlack.resolve(for: colorScheme))
                    .padding(.horizontal, Theme.spaceLG)
                    .frame(height: 56)
                    .frame(maxWidth: .infinity)
                    .background(Theme.ndTextDisplay.resolve(for: colorScheme))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(paywall.purchaseInFlight || paywall.product == nil)

                Button {
                    Task {
                        await paywall.restorePurchases()
                        if paywall.isPro { dismiss() }
                    }
                } label: {
                    Text("RESTORE PURCHASES")
                        .font(Theme.labelFont(size: 11))
                        .tracking(11 * 0.08)
                        .foregroundStyle(Theme.ndTextSecondary.resolve(for: colorScheme))
                        .frame(height: 32)
                }
                .buttonStyle(.plain)

                if let error = paywall.lastError {
                    Text(error)
                        .font(Theme.bodyFont(size: 12))
                        .foregroundStyle(Theme.ndAccent)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.spaceLG)
                }
            }
            .padding(.horizontal, Theme.spaceLG)
            .padding(.bottom, Theme.spaceXL)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.ndBlack.resolve(for: colorScheme))
        .onAppear {
            Analytics.paywallShown(reason: reason)
            Task {
                if paywall.product == nil {
                    await paywall.loadProduct()
                }
            }
        }
    }

    private var priceText: String {
        paywall.product?.displayPrice ?? "$6.99"
    }

    private func promiseRow(_ text: String) -> some View {
        HStack(spacing: Theme.spaceMD) {
            Rectangle()
                .fill(Theme.ndAccent)
                .frame(width: 6, height: 6)
            Text(text)
                .font(Theme.bodyFont(size: 18))
                .foregroundStyle(Theme.ndTextPrimary.resolve(for: colorScheme))
            Spacer()
        }
    }
}

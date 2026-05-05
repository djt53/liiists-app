import Foundation
import StoreKit

/// Manages the liiists Pro one-time IAP via StoreKit 2.
///
/// Free tier: up to 5 lists. Pro: unlimited.
/// See decisions/004-paywall-design.md.
@MainActor
final class Paywall: ObservableObject {
    static let shared = Paywall()

    /// Non-consumable IAP product identifier. Must match the one created in
    /// App Store Connect and the one in `Liiists.storekit`.
    static let proProductID = "com.davidtingle.liiists.pro"

    /// Free tier list cap. The 6th list creation triggers the paywall.
    static let freeListCap = 5

    @Published private(set) var isPro: Bool = false
    @Published private(set) var product: Product?
    @Published private(set) var purchaseInFlight: Bool = false
    @Published private(set) var lastError: String?

    private var updatesTask: Task<Void, Never>?

    private init() {
        // Listen for transaction updates from outside the app (e.g. parental
        // approval, family sharing, ask-to-buy, refunds).
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(transactionResult: result)
            }
        }

        Task {
            await loadProduct()
            await refreshEntitlements()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    /// Whether a free-tier user can create another list.
    func canCreateList(currentCount: Int) -> Bool {
        isPro || currentCount < Self.freeListCap
    }

    /// Fetches the Pro product from the App Store (or local .storekit config).
    func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.proProductID])
            self.product = products.first
        } catch {
            self.lastError = "Couldn't load product: \(error.localizedDescription)"
        }
    }

    /// Initiates a purchase. Updates `isPro` on success.
    func purchase() async {
        guard let product else {
            await loadProduct()
            return
        }

        purchaseInFlight = true
        defer { purchaseInFlight = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if let transaction = try? checkVerified(verification) {
                    await transaction.finish()
                    isPro = true
                    Analytics.purchaseCompleted(productID: product.id)
                }
            case .userCancelled:
                Analytics.purchaseCancelled(productID: product.id)
            case .pending:
                lastError = "Purchase pending approval."
            @unknown default:
                break
            }
        } catch {
            lastError = "Purchase failed: \(error.localizedDescription)"
            Analytics.purchaseFailed(productID: product.id, error: error.localizedDescription)
        }
    }

    /// Restores prior purchases. Apple requires this be user-accessible.
    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            lastError = "Restore failed: \(error.localizedDescription)"
        }
    }

    /// Re-reads the user's current entitlements from StoreKit.
    func refreshEntitlements() async {
        var unlocked = false
        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result),
               transaction.productID == Self.proProductID,
               transaction.revocationDate == nil {
                unlocked = true
            }
        }
        isPro = unlocked
    }

    private func handle(transactionResult: VerificationResult<Transaction>) async {
        guard let transaction = try? checkVerified(transactionResult) else { return }
        if transaction.productID == Self.proProductID {
            isPro = transaction.revocationDate == nil
        }
        await transaction.finish()
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let value):
            return value
        }
    }
}

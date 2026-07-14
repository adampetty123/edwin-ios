import Foundation
import StoreKit

/// StoreKit 2 subscription manager for Edwin Pro.
/// Products: quarterly £14.95 / 3 months (hero) and monthly £9.99.
/// Both carry a 7-day free trial (introductory offer, configured in ASC).
@MainActor
final class Store: ObservableObject {
    static let quarterlyId = "com.flowjam.iris.pro.quarterly"
    static let monthlyId = "com.flowjam.iris.pro.monthly"
    static let productIds = [quarterlyId, monthlyId]

    @Published var quarterly: Product?
    @Published var monthly: Product?
    @Published var isPro = false
    @Published var checked = false      // entitlement check finished (avoid paywall flash)
    @Published var purchasing = false
    @Published var error: String?

    private var updatesTask: Task<Void, Never>?

    init() {
        // keep entitlements fresh across renewals, refunds, family sharing
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let t) = update {
                    await t.finish()
                    await self?.refreshEntitlement()
                }
            }
        }
    }

    deinit { updatesTask?.cancel() }

    func start() async {
        await loadProducts()
        await refreshEntitlement()
        checked = true
    }

    func loadProducts() async {
        do {
            let products = try await Product.products(for: Self.productIds)
            quarterly = products.first { $0.id == Self.quarterlyId }
            monthly = products.first { $0.id == Self.monthlyId }
        } catch {
            self.error = "Couldn't load plans. Check your connection and try again."
        }
    }

    func refreshEntitlement() async {
        var pro = false
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let t) = entitlement, Self.productIds.contains(t.productID) {
                pro = t.revocationDate == nil
            }
        }
        isPro = pro
    }

    /// Runs the native purchase sheet. Returns true when the user ends up subscribed.
    func purchase(_ product: Product) async -> Bool {
        guard !purchasing else { return false }
        purchasing = true
        error = nil
        defer { purchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    error = "Purchase couldn't be verified. Try Restore Purchases."
                    return false
                }
                await transaction.finish()
                isPro = true
                return true
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            self.error = "Purchase didn't go through. Give it another go?"
            return false
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlement()
        if !isPro { error = "No active subscription found for this Apple ID." }
    }

    /// "£4.98/mo" for the quarterly product.
    var quarterlyPerMonth: String? {
        guard let q = quarterly else { return nil }
        let perMonth = q.price / 3
        return perMonth.formatted(q.priceFormatStyle)
    }
}

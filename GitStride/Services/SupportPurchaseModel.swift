import Observation
import StoreKit

@MainActor
@Observable
final class SupportPurchaseModel {
    static let shared = SupportPurchaseModel()
    static let productID = "tech.hyperseek.gitstride.support"

    private(set) var product: Product?
    private(set) var isLoading = false
    private(set) var isPurchasing = false
    private(set) var status: String?

    private var transactionTask: Task<Void, Never>?

    private init() {
        transactionTask = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.complete(result)
            }
        }

        Task { [weak self] in
            for await result in Transaction.unfinished {
                await self?.complete(result)
            }
        }
    }

    func loadProduct() async {
        guard product == nil, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            product = try await Product.products(for: [Self.productID])
                .first { $0.id == Self.productID && $0.type == .consumable }
            if product == nil {
                status = String(localized: "Support purchase is currently unavailable.")
            } else {
                status = nil
            }
        } catch {
            status = String(localized: "Could not load the support purchase. Please try again later.")
        }
    }

    func purchase() async {
        guard let product, !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        status = nil

        do {
            switch try await product.purchase() {
            case .success(let result):
                await complete(result)
            case .pending:
                status = String(localized: "Purchase pending approval.")
            case .userCancelled:
                break
            @unknown default:
                status = String(localized: "Could not complete the purchase.")
            }
        } catch {
            status = String(localized: "Could not complete the purchase.")
        }
    }

    private func complete(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else {
            status = String(localized: "Could not verify the purchase.")
            return
        }
        guard transaction.productID == Self.productID else { return }

        status = String(localized: "Thank you for supporting GitStride!")
        await transaction.finish()
    }
}

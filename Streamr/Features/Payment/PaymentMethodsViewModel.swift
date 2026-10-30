import Foundation
import StripePayments

@MainActor
final class PaymentMethodsViewModel: ObservableObject {
    @Published private(set) var paymentMethods: [SavedPaymentMethod] = []
    @Published private(set) var transactions: [Transaction] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var isProcessing = false

    private var stripeConfigLoaded = false

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let config: () = loadStripeConfigIfNeeded()
        async let methods: () = loadPaymentMethods()
        async let history: () = loadTransactions()
        _ = await (config, methods, history)
    }

    /// Hands Stripe its publishable key, without which `AddCardView` cannot
    /// turn card details into a PaymentMethod.
    ///
    /// **Moved here from PlansViewModel**, which was the only thing that ever
    /// set it. Adding a card therefore worked only if you had visited
    /// Subscription first in the same session, and silently failed otherwise —
    /// latent before, certain now that the plans screen no longer touches
    /// Stripe at all. This screen is the last Stripe surface in the app, so
    /// the key belongs to it.
    ///
    /// Note this is card *management* for a subscription billed on the web,
    /// not a purchase: nothing here charges anything, which is what keeps it
    /// clear of Guideline 3.1.1. See `StoreKitStore.PurchaseRoute`.
    private func loadStripeConfigIfNeeded() async {
        guard !stripeConfigLoaded else { return }
        do {
            let config = try await APIClient.shared.request(
                API.Payment.stripeConfig, as: APIResponse<StripeConfig>.self
            )
            guard let publishableKey = config.data?.stripePK else { return }
            // STPAPIClient.shared.publishableKey (StripePayments), not
            // StripeAPI.defaultPublishableKey (StripeCore) — StripeCore
            // isn't a directly-linkable SPM product in stripe-ios's package
            // manifest (only an internal target other products depend on),
            // confirmed by a real CI failure ("Missing package product
            // 'StripeCore'") 2026-09-28. Setting it on the client instance
            // directly avoids needing that product at all.
            STPAPIClient.shared.publishableKey = publishableKey
            stripeConfigLoaded = true
        } catch {
            // Best-effort — a card entered before this lands surfaces its own
            // "Stripe isn't configured" error instead.
        }
    }

    /// Called standalone by AddCardView/delete, not just load() — re-fetches
    /// just the methods list without touching billing history or the
    /// shared isLoading flag (which would otherwise flash the full-screen
    /// spinner over an already-populated list).
    func loadPaymentMethods() async {
        do {
            let response = try await APIClient.shared.request(
                API.Payment.paymentMethods, as: PaymentMethodsResponse.self
            )
            paymentMethods = response.paymentMethods ?? []
        } catch {
            // A cancelled pull-to-refresh isn't a failure — see
            // Error.isCancellation.
            guard !error.isCancellation else { return }
            errorMessage = error.localizedDescription
        }
    }

    func addCard(paymentMethodId: String, setAsDefault: Bool) async -> Bool {
        isProcessing = true
        errorMessage = nil
        defer { isProcessing = false }

        do {
            _ = try await APIClient.shared.request(
                API.Payment.addPaymentMethod(paymentMethodId: paymentMethodId, setAsDefault: setAsDefault),
                as: APIResponse<EmptyData>.self
            )
            await loadPaymentMethods()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func removeCard(_ method: SavedPaymentMethod) async {
        errorMessage = nil
        do {
            _ = try await APIClient.shared.request(
                API.Payment.removePaymentMethod(paymentMethodId: method.id), as: APIResponse<EmptyData>.self
            )
            paymentMethods.removeAll { $0.id == method.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadTransactions() async {
        do {
            let response = try await APIClient.shared.request(
                API.User.transactions(page: 1), as: APIResponse<[Transaction]>.self
            )
            transactions = response.data ?? []
        } catch {
            // Best-effort — the payment methods list above still works even
            // if billing history fails to load.
        }
    }
}

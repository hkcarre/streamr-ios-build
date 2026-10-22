import Foundation
import StripePayments

@MainActor
final class PlansViewModel: ObservableObject {
    @Published private(set) var plans: [SubscriptionPlan] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var purchasingPlanId: String?
    @Published var purchaseSuccessMessage: String?
    /// Non-nil presents the card-entry sheet — set by selectPlan(_:) for any
    /// paid plan; the free plan never goes through Stripe at all.
    @Published var checkoutPlan: SubscriptionPlan?
    /// A paid plan the person chose, for Apple in-app purchase to pick up.
    ///
    /// App Store Guideline 3.1.1 forbids charging for in-app subscriptions
    /// through anything but Apple's IAP, which is what `checkoutPlan` (Stripe)
    /// does. This is the replacement route. It is a separate property rather
    /// than a change to `checkoutPlan` so the Stripe path stays intact and
    /// usable -- see `useApplePurchasing`.
    @Published var applePurchasePlan: SubscriptionPlan?

    /// Whether to charge through Apple instead of Stripe.
    ///
    /// Set by the view from StoreKit's own answer: true once Apple returns a
    /// product catalogue, false while it returns nothing. That makes the switch
    /// self-healing rather than a flag someone has to remember to flip -- the
    /// Apple products are not registered in App Store Connect yet, and
    /// `Product.products(for:)` omits unknown ids silently, so hard-wiring IAP
    /// today would simply break paid plans. The moment the products exist, iOS
    /// starts using them.
    ///
    /// Stripe must be gone from iOS before submitting for review; this is the
    /// mechanism, not an excuse to leave it.
    var useApplePurchasing = false
    @Published private(set) var isCancelling = false

    private var stripeConfigLoaded = false

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let configLoad: () = loadStripeConfigIfNeeded()
        async let plansLoad: () = loadPlans()
        _ = await (configLoad, plansLoad)
    }

    /// The subscriber's current plan id, so the list can mark it and route a
    /// switch through upgrade rather than a fresh purchase. Set by the view
    /// from the cached user; nil for anyone without a subscription.
    @Published var currentPlanId: String?
    /// True when the current plan is the free trial. A free-plan user switching
    /// to a paid one goes through the normal purchase flow, not upgrade —
    /// that's the split the website makes (`if (!isCurrentlyFree)`).
    @Published var currentPlanIsFree = true

    func isCurrentPlan(_ plan: SubscriptionPlan) -> Bool {
        currentPlanId == plan.id
    }

    func selectPlan(_ plan: SubscriptionPlan) {
        // Already on it — nothing to buy. Without this the list offered
        // "Choose Plan" on the plan you were already paying for, and taking it
        // would have charged you again.
        guard !isCurrentPlan(plan) else { return }

        if plan.isFree {
            Task { await purchaseFree(plan) }
        } else if useApplePurchasing {
            // Apple handles both a first subscription and a change between
            // plans in the same subscription group, so there is no separate
            // upgrade path to take here.
            applePurchasePlan = plan
        } else if currentPlanId != nil, !currentPlanIsFree {
            // Existing PAID subscriber changing plans — a dedicated endpoint,
            // no card entry. See API.Payment.upgradeSubscription.
            Task { await upgrade(to: plan) }
        } else {
            checkoutPlan = plan
        }
    }

    /// Called after Apple confirms a purchase.
    ///
    /// Deliberately honest about what it cannot do. Apple has taken the money
    /// and StoreKit now reports the entitlement, but the Streamr backend has
    /// not been told -- there is no endpoint that accepts an App Store
    /// transaction (checked against the live API 2026-10-22), so
    /// `/user/profile` still reports the old plan and re-reading it would just
    /// overwrite the good news with stale data.
    ///
    /// So this reports success and says the account will catch up, rather than
    /// claiming the plan changed or silently doing nothing. Replace the whole
    /// body with a call to the real endpoint once it exists -- the item is in
    /// streamr-backend-tasks.txt.
    func reloadAfterApplePurchase() async {
        purchaseSuccessMessage = "Thanks — your subscription is active with Apple. It can take a moment to show up on your Streamr account."
    }

    /// Switches an existing paid subscriber to another paid plan.
    private func upgrade(to plan: SubscriptionPlan) async {
        purchasingPlanId = plan.id
        errorMessage = nil
        defer { purchasingPlanId = nil }

        do {
            _ = try await APIClient.shared.request(
                API.Payment.upgradeSubscription(newPlanId: plan.id),
                as: APIResponse<EmptyData>.self
            )
            currentPlanId = plan.id
            currentPlanIsFree = plan.isFree
            purchaseSuccessMessage = "You're now on \(plan.name)."
            await loadPlans()
        } catch {
            guard !error.isCancellation else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// Called by StripeCheckoutView once it's created a real Stripe
    /// PaymentMethod — owning the actual purchase call here (not in the
    /// checkout view) keeps success/error state in one place regardless of
    /// which plan triggered checkout.
    ///
    /// Mirrors stripeCheckoutForm.tsx's handleSubmit exactly: confirm-payment
    /// is called whenever initial-payment comes back with a paymentIntentId
    /// at all (including the already-`"succeeded"` case, e.g. a previously-
    /// saved card) — never skipped just because the charge already went
    /// through, since it's what actually persists the subscription
    /// server-side.
    func completePaidPurchase(plan: SubscriptionPlan, paymentMethodId: String) async throws {
        guard let productId = plan.productId else {
            throw APIError.server(message: "This plan is missing its Stripe product id.", statusCode: 0)
        }

        let initial = try await APIClient.shared.request(
            API.Payment.initialPayment(productId: productId, paymentMethodId: paymentMethodId),
            as: InitialPaymentResponse.self
        )

        if let paymentIntentId = initial.paymentIntentId {
            let confirm = try await APIClient.shared.request(
                API.Payment.confirmPayment(paymentIntentId: paymentIntentId), as: ConfirmPaymentResponse.self
            )
            purchaseSuccessMessage = confirm.message ?? "Subscription purchased successfully."
        } else if initial.success == true {
            purchaseSuccessMessage = initial.message ?? "Subscription purchased successfully."
        } else {
            throw APIError.server(message: initial.message ?? "Payment failed.", statusCode: 0)
        }
    }

    /// GET /payment/subscription/cancel, confirmed by reading
    /// accountSettings.ts — not live-verified (would cancel a real
    /// subscription, nothing safe to test it against without one).
    func cancelSubscription() async {
        isCancelling = true
        errorMessage = nil
        defer { isCancelling = false }

        do {
            let response = try await APIClient.shared.request(
                API.Payment.cancelSubscription, as: APIResponse<EmptyData>.self
            )
            purchaseSuccessMessage = response.message ?? "Subscription cancelled successfully."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

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
            // Best-effort — a paid checkout attempted before this lands
            // will surface its own "Stripe isn't configured" error instead.
        }
    }

    private func loadPlans() async {
        do {
            let response = try await APIClient.shared.request(
                API.Subscription.activePlans, as: APIResponse<[SubscriptionPlan]>.self
            )
            plans = response.data ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func purchaseFree(_ plan: SubscriptionPlan) async {
        purchasingPlanId = plan.id
        errorMessage = nil
        defer { purchasingPlanId = nil }

        do {
            let response = try await APIClient.shared.request(
                API.Payment.purchaseFreePlan(planId: plan.id), as: PurchasePlanResponse.self
            )
            purchaseSuccessMessage = response.message ?? "Subscription enabled successfully."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

import Foundation

@MainActor
final class PlansViewModel: ObservableObject {
    @Published private(set) var plans: [SubscriptionPlan] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var purchasingPlanId: String?
    @Published var purchaseSuccessMessage: String?
    /// A paid plan the person chose, for Apple in-app purchase to pick up.
    ///
    /// Set only on the `.apple` route. The view watches it, starts the
    /// StoreKit purchase and clears it — the view model never touches
    /// StoreKit itself, so this type stays testable without a store.
    @Published var applePurchasePlan: SubscriptionPlan?
    /// A paid plan someone chose while the external-link route is active.
    @Published var externalPurchasePlan: SubscriptionPlan?

    /// How this device may pay, set by the view from `StoreKitStore`.
    ///
    /// Starts at `.unavailable` so nothing can charge before StoreKit has
    /// answered. This replaced a pair of booleans whose "both false" case fell
    /// through to in-app Stripe card entry — a Guideline 3.1.1 violation that
    /// was the live behaviour on every non-US storefront, since no products are
    /// registered in App Store Connect and the external link is US-only.
    @Published var route: StoreKitStore.PurchaseRoute = .unavailable

    var useApplePurchasing: Bool { route == .apple }
    var useExternalPurchaseLink: Bool { route == .externalLink }

    /// Shown instead of a purchase when there is no lawful way to charge.
    ///
    /// Says what is true without steering anyone to the web: naming the
    /// website to a non-US user is itself the anti-steering violation, and the
    /// one storefront where that is permitted gets `.externalLink` instead of
    /// this.
    static let purchaseUnavailableMessage =
        "Subscriptions can't be bought in the app yet. Any plan you already have keeps working."

    @Published private(set) var isCancelling = false

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        await loadPlans()
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

    /// Whether this plan's button can actually do something.
    ///
    /// The free plan always can — it needs no payment route at all. A paid one
    /// needs a lawful way to charge, so on `.unavailable` its button is
    /// disabled rather than live-but-futile: a button that looks tappable and
    /// then raises an error is worse than one that plainly is not.
    func canSelect(_ plan: SubscriptionPlan) -> Bool {
        plan.isFree || route != .unavailable
    }

    func selectPlan(_ plan: SubscriptionPlan) {
        // Already on it — nothing to buy. Without this the list offered
        // "Choose Plan" on the plan you were already paying for, and taking it
        // would have charged you again.
        guard !isCurrentPlan(plan) else { return }

        if plan.isFree {
            // No money changes hands, so Apple has no interest in it. Its own
            // endpoint, as the website uses.
            Task { await purchaseFree(plan) }
            return
        }

        switch route {
        case .apple:
            // Apple handles both a first subscription and a change between
            // plans in the same subscription group, so there is no separate
            // upgrade path to take here.
            applePurchasePlan = plan
        case .externalLink:
            // The view opens the URL; the view model only records the intent so
            // the plan card's own button drives it.
            externalPurchasePlan = plan
        case .unavailable:
            // Deliberately no Stripe card entry and no `upgradeSubscription`
            // call. Both charge for a subscription outside Apple's in-app
            // purchase, and an upgrade billed to a card already on file is the
            // same 3.1.1 violation as a fresh charge — the absence of a card
            // form does not make it compliant.
            errorMessage = Self.purchaseUnavailableMessage
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

    // No `upgrade(to:)` and no `completePaidPurchase(plan:paymentMethodId:)`
    // here any more. Both charged for a subscription through Stripe from
    // inside the app — the first against a card already on file via
    // `/payment/upgrade-subscription`, the second against a freshly-entered
    // one via `/payment/initial-payment`. Guideline 3.1.1 forbids either, and
    // with Apple's catalogue empty they were the only routes a non-US device
    // could reach, so the app was shipping the violation rather than guarding
    // against it. Paid plans now go through Apple, or through the website on
    // the US storefront, or nowhere. The endpoints remain in Endpoint.swift
    // for the website's benefit; nothing on iOS calls them.

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

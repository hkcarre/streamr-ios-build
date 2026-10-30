import Foundation
import StoreKit

/// Apple in-app purchase for Streamr's subscriptions.
///
/// **Every StoreKit transaction type here is written `StoreKit.Transaction`,
/// not `Transaction`.** This app already has its own `Transaction` -- the
/// billing-history row in Endpoint.swift -- and an unqualified `Transaction`
/// inside this module resolves to that one, not Apple's. Confirmed by CI
/// 2026-10-22: four errors, including the diagnostic "cannot convert value of
/// type 'StoreKit.Transaction' to expected argument type 'Streamr.Transaction'".
/// Leave the qualification in place.
///
/// **Why this has to exist.** App Store Review Guideline 3.1.1 requires that
/// digital content and subscriptions consumed inside an app be sold through
/// Apple's in-app purchase. Streamr currently charges through Stripe
/// (`/payment/initial-payment`, `StripeCardField`), which is exactly the
/// arrangement 3.1.1 forbids on iOS. It was one of three open App Store
/// blockers as of 2026-10-22, and the build cannot ship without it.
///
/// Stripe is not removed. It stays for the website, and the plan catalogue
/// still comes from `/subscription/activeplans` — this type only replaces the
/// *payment* step when running on iOS.
///
/// ## The one thing this cannot do on its own
///
/// A successful Apple purchase proves someone paid Apple. It does not tell the
/// Streamr backend anything. For the account to actually gain the plan, the
/// signed transaction has to be posted to a server, verified against Apple,
/// and recorded — and there is no endpoint for that: checked against the live
/// API 2026-10-22, nothing accepts an App Store transaction.
///
/// So `purchase(...)` ends by handing the verified transaction to
/// `onPurchaseVerified`, which is where that call goes once it exists. Until
/// then the purchase completes with Apple and `activeProductIds` reflects it
/// locally, but the Streamr account won't — which is why the paywall says so
/// rather than pretending. Raised as an item in streamr-backend-tasks.txt.
///
/// ## Product identifiers
///
/// Apple product ids are not in the plan payload (it carries Stripe's
/// `productId`/`priceId`), so they are derived from the plan name by
/// `ProductMap`. They must match what is registered in App Store Connect
/// exactly — `Product.products(for:)` silently omits unknown ids rather than
/// erroring, so a typo looks like "the plan vanished".
@MainActor
final class StoreKitStore: ObservableObject {
    /// Apple products, in the order the plans were given to `load`.
    @Published private(set) var products: [Product] = []
    /// Product ids Apple currently considers entitled on this Apple ID.
    @Published private(set) var activeProductIds: Set<String> = []
    @Published private(set) var isLoading = false
    @Published private(set) var purchaseInFlight: String?
    /// Set when loading or purchasing failed, for the paywall to show.
    @Published var errorMessage: String?
    /// True when StoreKit returned no products at all for ids we asked for —
    /// nearly always a configuration problem rather than a code one, and worth
    /// distinguishing because the fix is in App Store Connect, not here.
    @Published private(set) var catalogueUnavailable = false
    /// The App Store country this device buys from, as ISO 3166-1 alpha-3
    /// ("USA", "GBR", ...). nil until `load` has run.
    @Published private(set) var storefrontCountryCode: String?

    /// Whether this device may be shown a link to pay on the web.
    ///
    /// **US storefront only, and that is not a stylistic choice.** Since Apple
    /// updated the guidelines in May 2025 under the Epic injunction, apps on
    /// the United States storefront may include buttons, external links and
    /// calls to action pointing at outside payment, with no entitlement needed
    /// and no anti-steering restriction. Apple is currently charging 0% on
    /// those; it has asked the court for 15% and no rate has been approved.
    ///
    /// Everywhere else the old rules still apply: the EU, Japan and Brazil need
    /// the External Purchase Link Entitlement plus its own StoreKit APIs, and
    /// other storefronts do not permit the link at all. Showing this link to a
    /// non-US account is a 3.1.1 rejection, so it is gated on the storefront
    /// rather than shown everywhere and hoped for.
    var allowsExternalPurchaseLink: Bool { storefrontCountryCode == "USA" }

    /// Where to send someone to subscribe. The website's own plans route.
    static let externalPurchaseURL = URL(string: "https://streamr.nyc/plans")!

    /// How this device may pay for a subscription — the app's single answer.
    ///
    /// **Why an enum rather than two booleans.** It used to be two: "use
    /// Apple" and "use the external link". Nothing handled the case where both
    /// were false, so it fell through to Stripe card entry inside the app —
    /// precisely the arrangement Guideline 3.1.1 forbids. That was not a
    /// theoretical branch. No products are registered in App Store Connect, so
    /// Apple returns an empty catalogue, and the external link is lawful on the
    /// US storefront only; every non-US device therefore took the Stripe path.
    /// An enum makes "neither" a case someone has to answer for, instead of a
    /// gap that lands on Stripe by default.
    enum PurchaseRoute: Equatable {
        /// Apple's in-app purchase. What 3.1.1 asks for, used whenever Apple
        /// actually returns a catalogue.
        case apple
        /// A link out to streamr.nyc. US storefront only — see
        /// `allowsExternalPurchaseLink`.
        case externalLink
        /// No lawful way to take payment on this device. Plans are still
        /// listed; nothing in the app will charge for them.
        case unavailable
    }

    /// Resolved from what Apple has actually said, not from configuration.
    ///
    /// Returns `.unavailable` before `load` has run — `products` is empty and
    /// `storefrontCountryCode` is nil — so a view reading this early cannot be
    /// handed a payment route it has not earned.
    var purchaseRoute: PurchaseRoute {
        if !products.isEmpty { return .apple }
        if allowsExternalPurchaseLink { return .externalLink }
        return .unavailable
    }

    /// Called with a verified transaction after a successful purchase or a
    /// restore. Hook the backend call here.
    var onPurchaseVerified: ((StoreKit.Transaction) async -> Void)?

    private var updatesTask: Task<Void, Never>?

    init() {
        // Must start before any purchase. Apple delivers transactions that
        // completed outside the app — an Ask to Buy approval, a renewal, a
        // purchase made on another device — only through this stream, and a
        // transaction that is never finished is re-delivered on every launch
        // forever.
        updatesTask = Task { [weak self] in
            for await update in StoreKit.Transaction.updates {
                await self?.handle(update)
            }
        }
    }

    deinit { updatesTask?.cancel() }

    // MARK: - Catalogue

    /// Loads the Apple products matching the backend's paid plans.
    ///
    /// The free Trial plan is skipped: there is nothing to charge for, and it
    /// already has its own path (`/payment/purchaseFreePlan`). Selling a $0
    /// subscription through Apple would be rejected as a meaningless IAP.
    func load(plans: [SubscriptionPlan]) async {
        // Read the storefront first and unconditionally: it decides whether the
        // external-link route is even legal, and that answer is needed whether
        // or not Apple returns a product catalogue.
        storefrontCountryCode = await StoreKit.Storefront.current?.countryCode

        let ids = plans.filter { !$0.isFree }.compactMap { ProductMap.appleProductId(for: $0) }
        guard !ids.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let fetched = try await Product.products(for: ids)
            // Preserve the backend's ordering rather than Apple's — the plan
            // list is already sorted by its `order` field and the paywall
            // should read cheapest-first the same way the website does.
            products = ids.compactMap { id in fetched.first { $0.id == id } }
            catalogueUnavailable = products.isEmpty
            if catalogueUnavailable {
                errorMessage = "Subscriptions aren't available right now."
            }
            await refreshEntitlements()
        } catch {
            errorMessage = error.localizedDescription
            catalogueUnavailable = true
        }
    }

    /// The Apple product corresponding to a backend plan, if it loaded.
    func product(for plan: SubscriptionPlan) -> Product? {
        guard let id = ProductMap.appleProductId(for: plan) else { return nil }
        return products.first { $0.id == id }
    }

    /// What Apple says this Apple ID is entitled to, right now.
    func refreshEntitlements() async {
        var active: Set<String> = []
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            // A refunded or expired entitlement still appears here with a
            // revocation date / past expiry, so neither counts as active.
            if transaction.revocationDate != nil { continue }
            if let expires = transaction.expirationDate, expires < Date() { continue }
            active.insert(transaction.productID)
        }
        activeProductIds = active
    }

    // MARK: - Buying

    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        purchaseInFlight = product.id
        defer { purchaseInFlight = nil }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    // `.unverified` means the signature didn't check out. Never
                    // grant anything on it.
                    errorMessage = "That purchase couldn't be verified."
                    return false
                }
                await handle(.verified(transaction))
                return true

            case .userCancelled:
                return false

            case .pending:
                // Ask to Buy, or a bank step. It is not a failure and the
                // transaction will arrive via StoreKit.Transaction.updates later.
                errorMessage = "Your purchase needs approval before it finishes."
                return false

            @unknown default:
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Apple requires a visible restore control on any app selling
    /// subscriptions; without one, review rejects under 3.1.1 even when the
    /// purchase flow itself is correct.
    func restore() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Transactions

    private func handle(_ result: VerificationResult<StoreKit.Transaction>) async {
        guard case .verified(let transaction) = result else { return }

        await onPurchaseVerified?(transaction)

        // Finish only after the handler has had its chance. An unfinished
        // transaction is re-delivered, which is the behaviour we want if
        // recording it server-side failed — the purchase isn't lost.
        await transaction.finish()
        await refreshEntitlements()
    }
}

/// Maps a Streamr plan to its Apple product id.
///
/// Kept separate and dumb on purpose. The backend's plan payload has no Apple
/// identifier in it — `productId`/`priceId` are Stripe's — so something has to
/// bridge the two, and a table that can be read at a glance is easier to keep
/// in step with App Store Connect than logic spread through the paywall.
///
/// **These ids must be registered in App Store Connect before they resolve.**
/// `Product.products(for:)` omits unknown ids without complaint.
enum ProductMap {
    /// Streamr plan name (as `/subscription/activeplans` returns it) -> Apple
    /// product id. The free Trial plan is deliberately absent.
    static let byPlanName: [String: String] = [
        "Basic Subscription": "nyc.streamr.sub.basic",
        "Pro Subscription": "nyc.streamr.sub.pro",
        "Max Subscription": "nyc.streamr.sub.max",
        "Streamr Studio": "nyc.streamr.sub.studio"
    ]

    static func appleProductId(for plan: SubscriptionPlan) -> String? {
        byPlanName[plan.name]
    }

    static func planName(forAppleProductId id: String) -> String? {
        byPlanName.first { $0.value == id }?.key
    }
}

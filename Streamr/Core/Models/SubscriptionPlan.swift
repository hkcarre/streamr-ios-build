import Foundation

/// Confirmed live 2026-09-28 via `GET /subscription/activeplans`. The real
/// response also nests a `stripe: {test: {...}, live: {...}}` object, but
/// the flat `productId`/`priceId` fields already reflect whichever mode is
/// currently active (matches `stripeMode` from `/payment/stripe-config`) —
/// the same fields the website itself reads (see PlansViewModel's doc
/// comment) — so the nested object isn't modeled here at all.
struct SubscriptionPlan: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let description: String?
    let additionalDetails: String?
    let amount: Double
    let validity: String
    let noofstreams: Int
    let streamMaxMinutes: Int
    let isFree: Bool
    /// Required to purchase a paid plan (POST /payment/initial-payment) —
    /// nil for the free plan, which uses purchaseFreePlan instead and never
    /// touches Stripe at all.
    let productId: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, description, additionalDetails, amount, validity
        case noofstreams, streamMaxMinutes, isFree, productId
    }
}

/// `GET /payment/stripe-config`'s real shape, confirmed live 2026-09-28.
/// **`stripeMode` was "live" on the production account at confirmation
/// time** — every purchase against the real backend charges a real card.
/// There is no test-mode toggle reachable from this app; ask whoever
/// manages the Stripe/backend admin panel before doing any real end-to-end
/// paid-purchase QA.
struct StripeConfig: Decodable {
    let stripePK: String
    let stripeMode: String
}

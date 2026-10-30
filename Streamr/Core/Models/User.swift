import Foundation

struct User: Codable, Identifiable, Equatable {
    let id: String
    var firstName: String
    var lastName: String
    var email: String
    var profilePic: String?
    var coverPic: String?
    /// Returned by login and persisted by `/user/complete-profile` — confirmed
    /// live 2026-10-08. Needed because that endpoint takes the whole profile,
    /// so a photo change must send the existing bio back or it gets blanked.
    var bio: String?
    var accountType: String?
    var role: String?
    var isEmailVerified: Bool?
    var status: String?
    var token: String?
    /// Both confirmed live in the login response 2026-10-11, against a
    /// disposable account (`subscriptionPurchased: false` before buying a plan).
    /// The website reads the same two from its cached login payload to decide
    /// whether to show the plans modal — there is no separate "my subscription"
    /// endpoint behind it.
    var subscriptionPurchased: Bool?
    var subscriptionExpiresAt: String?
    /// The subscriber's current plan, so the Subscription screen can mark it
    /// and route a change through upgrade rather than a fresh purchase.
    ///
    /// Read from the login payload, matching how the website gets it
    /// (`user?.purchasedplan?.plan?._id` / `?.isFree`, from its cached login
    /// response — there is no separate subscription endpoint behind it). The
    /// lowercase spelling is the backend's, not a typo.
    ///
    /// Confirmed present once a plan exists: `/payment/purchaseFreePlan`
    /// returns the same `purchasedPlan` object. The exact nesting inside the
    /// LOGIN response is taken from the website's usage rather than observed
    /// directly, which is why `PurchasedPlan` decodes defensively — see its
    /// initialiser.
    var purchasedplan: PurchasedPlan?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case firstName, lastName, email, profilePic, coverPic, bio, accountType, role, isEmailVerified, status, token
        case subscriptionPurchased, subscriptionExpiresAt, purchasedplan
    }

    var fullName: String {
        [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// Decodes defensively ON PURPOSE.
///
/// This hangs off the login response, so a strict decode here would take the
/// whole `User` down with it — i.e. an unexpected shape in a field used only to
/// decorate the Subscription screen would break logging in. The backend already
/// returns this in more than one shape elsewhere (`subscriptionPlanId` is a
/// plain id string from `/payment/purchaseFreePlan` and a full object inside
/// `/show/create`'s `allowedStreams`), so tolerating variation is the realistic
/// assumption rather than pessimism.
///
/// Anything unrecognised degrades to `plan == nil`, which the Subscription
/// screen reads as "no current plan" — the behaviour before this existed.
struct PurchasedPlan: Codable, Equatable {
    var plan: PlanSummary?

    struct PlanSummary: Codable, Equatable {
        var id: String?
        var name: String?
        var isFree: Bool?

        enum CodingKeys: String, CodingKey {
            case id = "_id"
            case name, isFree
        }
    }

    enum CodingKeys: String, CodingKey {
        case plan
    }

    init(plan: PlanSummary? = nil) {
        self.plan = plan
    }

    init(from decoder: Decoder) throws {
        // Non-throwing throughout: `try?` on the container too, in case the
        // value isn't a JSON object at all.
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        plan = try? container?.decodeIfPresent(PlanSummary.self, forKey: .plan)
    }
}

import Foundation

/// Value-based navigation routes for the Hub tab's NavigationStack.
///
/// Replaces the `NavigationLink { Destination() } label: { … }` form that
/// DiscoverView and ShowDetailView used to push with. That closure form has a
/// long-standing defect inside lazy containers (`LazyVStack`, `ForEach` in a
/// `ScrollView`): the link keeps internal presentation state, and after you pop
/// back the SAME link won't fire again — every other row still works, so it
/// reads as one specific episode going dead. Reported 2026-10-11: "when you
/// click on episode page then navigate back, you cannot open the previously
/// opened episode."
///
/// With a value and a `navigationDestination`, the stack owns the path and the
/// link itself holds no state to get stuck, so re-tapping the row you just came
/// back from pushes again like any other.
///
/// `Show` is carried whole rather than re-fetched by id because
/// `ShowDetailView` needs `host` and `coverPic`, and only the Main Stream list
/// endpoint populates those (see Show's doc comments). Hashing is id-only, so
/// the route stays stable even if an unrelated field of the show changes.
struct ShowRoute: Hashable {
    let show: Show

    static func == (lhs: ShowRoute, rhs: ShowRoute) -> Bool {
        lhs.show.id == rhs.show.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(show.id)
    }
}

/// An episode/stream to play. Carries only the id — `PlayerView` fetches the
/// full detail itself, and a stream's status changes while you're watching it,
/// so a snapshot would go stale.
struct PlayerRoute: Hashable {
    let streamId: String
}

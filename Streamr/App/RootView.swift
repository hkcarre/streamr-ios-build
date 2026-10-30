import SwiftUI

/// Main Stream is open to guests (matches the backend: /stream/public/list
/// needs no auth), so there's no hard login wall at the root anymore —
/// MainTabView itself gates Shows / Account behind AuthGate.
struct RootView: View {
    var body: some View {
        MainTabView()
    }
}

import SwiftUI

/// The three bottom destinations. "Add Stream" is deliberately not a real
/// screen — see `onChange(of: selectedTab)` below, which intercepts it before
/// its content ever renders and presents a sheet instead. SwiftUI's `TabView`
/// has no native "action tab" support, so snap-back-and-present is the
/// standard workaround (keeps the free TabView chrome/accessibility instead
/// of hand-rolling a custom bottom bar).
///
/// The first tab is labelled **Hub** (per `wireframes/bottom navigator.png`,
/// 2026-10-08). It hosts both the public discover feed and the user's own
/// shows as an in-page segmented toggle — see `StreamHomeView`. Earlier
/// wireframes alternated this label between "Main Stream"/"My Stream"
/// depending on the active screen, which read as a Figma-prototyping artifact;
/// "Hub" settles it with one stable name for one stable destination.
enum StreamrTab: Hashable {
    case stream
    case addStream
    case account
}

struct MainTabView: View {
    @EnvironmentObject private var authManager: AuthManager
    @State private var selectedTab: StreamrTab = .stream
    @State private var previousTab: StreamrTab = .stream
    @State private var showingAddStreamSheet = false
    @State private var showingAddStreamLogin = false
    /// Bumped when Hub is tapped while already on Hub. StreamHomeView watches
    /// it and returns to the landing page — see StreamrTabBar.onReselect.
    @State private var hubResetToken = 0
    /// Owns the "you are live" state for the whole app — see LiveSessionBar.
    @StateObject private var liveMonitor = LiveSessionMonitor()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // The system tab bar is hidden and replaced by StreamrTabBar — see
        // that file for why the wireframe's floating capsule can't be done
        // with UITabBar appearance. The TabView itself stays so view identity,
        // state preservation and the Add Stream interception keep working.
        TabView(selection: $selectedTab) {
            // `.tabItem` must stay even though the bar is hidden. Dropping it
            // made tabs render blank (reported 2026-10-09: My Account opened to
            // an empty screen) — TabView uses tabItem to build each child's
            // entry, and a child without one has no defined content in the
            // standard style.
            //
            // `.toolbar(.hidden, for: .tabBar)` goes on EACH TAB'S CONTENT,
            // never on the TabView. On the TabView it silently does nothing:
            // the modifier resolves against the nearest enclosing bar, and from
            // the outside of a TabView there isn't one. That left the stock bar
            // drawn underneath the floating capsule — reported 2026-10-11 as
            // "old nav bar still visible under new nav bar", and visible in
            // build 5.
            StreamHomeView(resetToken: hubResetToken)
                .toolbar(.hidden, for: .tabBar)
                .tabItem { Label("Hub", systemImage: "wifi") }
                .tag(StreamrTab.stream)

            Color.clear
                .toolbar(.hidden, for: .tabBar)
                .tabItem { Label("Add Stream", systemImage: "plus.circle.fill") }
                .tag(StreamrTab.addStream)

            AuthGate(prompt: "Log in to manage your account.") {
                AccountView()
            }
            .toolbar(.hidden, for: .tabBar)
            .tabItem { Label("My Account", systemImage: "person.circle") }
            .tag(StreamrTab.account)
        }
        .tint(StreamrColor.primary)
        // safeAreaInset, not overlay: it both places the capsule AND reserves
        // the space it occupies, so screen content can't end up hidden behind
        // it. With an overlay, anything bottom-aligned (AccountView's Log Out
        // button, for one) sat underneath the bar and was unreachable.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                // Above the tab bar, inside the same inset, so it reserves its
                // own space and can never cover content — and so it is on
                // screen on EVERY tab while a broadcast is running. See
                // LiveSessionBar for why it isn't left to the wizard sheet.
                if liveMonitor.myLiveStream != nil {
                    LiveSessionBar(monitor: liveMonitor)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                StreamrTabBar(
                    selection: $selectedTab,
                    avatarURL: authManager.currentUser?.profilePic,
                    onReselect: { tab in
                        // Tapping the tab you're already on goes back to the
                        // top of it, the way the stock tab bar does.
                        if tab == .stream { hubResetToken += 1 }
                    }
                )
            }
            .padding(.top, 6)
            .animation(.easeInOut(duration: 0.25), value: liveMonitor.myLiveStream?.id)
        }
        .onChange(of: selectedTab) { _, newValue in
            guard newValue == .addStream else {
                previousTab = newValue
                return
            }
            selectedTab = previousTab
            if authManager.isAuthenticated {
                showingAddStreamSheet = true
            } else {
                showingAddStreamLogin = true
            }
        }
        // Logging out from My Account used to leave you sitting on My Account,
        // which then rendered its "Log in to manage your account" gate — so the
        // act of signing out dumped you on a login prompt. Reported 2026-10-11
        // ("logout should return you to landing page"). Hub is the landing
        // page: it's the only tab that works signed out.
        //
        // Keyed on isAuthenticated rather than wired into each Log Out button
        // so it covers every route out of a session, including the automatic
        // logout on a 401 (see AuthManager's unauthorized subscription).
        .onChange(of: authManager.isAuthenticated) { _, isAuthenticated in
            liveMonitor.start(userId: isAuthenticated ? authManager.currentUser?.id : nil)
            guard !isAuthenticated else { return }
            selectedTab = .stream
            previousTab = .stream
        }
        .task {
            liveMonitor.start(userId: authManager.isAuthenticated ? authManager.currentUser?.id : nil)
        }
        // Coming back from the background is exactly when a broadcast may have
        // died without the app hearing about it, so re-check immediately rather
        // than waiting out the poll interval.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await liveMonitor.refresh() }
        }
        // The wizard is the one place that ends a stream without going through
        // the monitor, so clear the bar the moment its sheet closes instead of
        // leaving it up for up to a poll interval.
        .onChange(of: showingAddStreamSheet) { _, isShowing in
            guard !isShowing else { return }
            Task { await liveMonitor.refresh() }
        }
        .sheet(isPresented: $showingAddStreamSheet) {
            AddStreamCoordinatorView()
        }
        .sheet(isPresented: $showingAddStreamLogin) {
            LoginView()
        }
        // Says why the app went back to its signed-out state, instead of
        // leaving the user to conclude it forgot them. Offers the way back in
        // from the same alert, since being told to log in with no way to do it
        // is barely better than silence.
        .alert("Session expired", isPresented: $authManager.sessionExpired) {
            Button("Log In") { showingAddStreamLogin = true }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("You've been signed out because your session ended. Log in again to pick up where you left off.")
        }
    }
}

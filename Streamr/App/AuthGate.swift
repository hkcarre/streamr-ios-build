import SwiftUI

/// Wraps a tab's content so it's only shown when logged in; otherwise shows a
/// branded landing screen with a "Log In" button that presents LoginView as a
/// sheet. Used for the My Account tab. The My Stream tab's own auth gating is
/// inline instead (see StreamHomeView) since Main Stream must stay visible
/// even when My Stream requires login — this wraps InlineAuthPrompt so both
/// treatments share one implementation.
struct AuthGate<Content: View>: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var moderation: ModerationStore
    @StateObject private var viewModel = DiscoverViewModel()
    @State private var showingLogin = false

    let prompt: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            if authManager.isAuthenticated {
                content()
            } else {
                loggedOutPrompt
            }
        }
        .sheet(isPresented: $showingLogin) {
            LoginView()
        }
        .onChange(of: authManager.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated { showingLogin = false }
        }
    }

    /// Heads itself with the wordmark and carries the same carousel the landing
    /// page does, rather than being a bare prompt under an empty navigation bar
    /// (reported 2026-10-14 with a screenshot: "it should show Streamr logo and
    /// show carousel, no nav bar").
    ///
    /// The NavigationStack stays — the cards push by value and need a stack to
    /// push into — but its bar is hidden, which is what leaves the dead space at
    /// the top of the screen when there is no title or toolbar to put in it.
    private var loggedOutPrompt: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    LandingLogo()
                        .padding(.top, 8)

                    InlineAuthPrompt(prompt: prompt) {
                        showingLogin = true
                    }

                    if let strip = landingStrip {
                        StreamStrip(title: strip.title, streams: strip.streams)
                    } else if !viewModel.isLoadingLive {
                        emptyStrip
                    }
                }
                .padding(.vertical, 16)
            }
            .streamrBackground()
            .toolbar(.hidden, for: .navigationBar)
            // Registered here so a card tapped from this screen opens, instead
            // of being a picture of something you can't reach.
            .navigationDestination(for: PlayerRoute.self) { route in
                PlayerView(streamId: route.streamId)
            }
            .navigationDestination(for: ShowRoute.self) { route in
                ShowDetailView(show: route.show)
            }
            .task {
                // Hand the view model a way to ask the block list, before the
                // first fetch -- filtering on arrival rather than at render
                // time keeps a blocked creator out of pagination and out of
                // LandingCarousel's ranking, instead of leaving gaps in both.
                viewModel.isBlockedOwner = { moderation.isBlocked(userId: $0) }
                await viewModel.loadInitial()
            }
            .refreshable { await viewModel.refresh() }
        }
    }

    /// Shown when there is nothing public to carousel.
    ///
    /// Without this the signed-out screen rendered the logo, the login prompt
    /// and then nothing — indistinguishable from the carousel being broken,
    /// and reported as such on 2026-10-20. It is empty for a real reason:
    /// `/stream/public/list` is the only endpoint that answers without a
    /// token, and it currently returns nothing watchable (no live episodes, and
    /// finished ones aren't published to it — see API.Discover.recentStreams).
    /// Saying so is better than a blank space.
    private var emptyStrip: some View {
        VStack(spacing: 6) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.white.opacity(0.45))
            Text("Nothing streaming right now")
                .font(StreamrFont.headline(15))
                .foregroundStyle(.white.opacity(0.85))
            Text("Live episodes and replays will appear here.")
                .font(StreamrFont.body(13))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 24)
    }

    /// Exactly the landing page's rule, by construction — see LandingCarousel.
    private var landingStrip: (title: String, streams: [StreamItem])? {
        LandingCarousel.strip(live: viewModel.liveStreams, finished: viewModel.finishedStreams)
    }
}

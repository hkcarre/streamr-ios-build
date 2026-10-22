import SwiftUI

/// Owns the shared NavigationStack, hamburger, and guest/creator toolbar
/// actions for the merged "My Stream" tab — a segmented Main Stream / My
/// Stream toggle over one screen, not two separate tabs. See MainTabView's
/// doc comment for why this reads the wireframe's alternating tab label as
/// an in-page toggle rather than two destinations.
private enum StreamSegment: Hashable {
    case main
    case mine
}

struct StreamHomeView: View {
    /// Incremented by MainTabView when Hub is tapped while already on Hub.
    /// Changing it pops back to the landing page.
    var resetToken: Int = 0

    @EnvironmentObject private var authManager: AuthManager
    @State private var segment: StreamSegment = .main
    @State private var showingLogin = false
    @State private var showingHamburgerMenu = false
    @State private var showingCreateShowSheet = false
    /// Driven explicitly so the tab bar can clear it. With the stack owning its
    /// own path there was no way to pop programmatically, which is why someone
    /// pushed into a show or an episode had no route back to the landing page.
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                segmentedToggle
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                Group {
                    switch segment {
                    case .main:
                        DiscoverView()
                    case .mine:
                        if authManager.isAuthenticated {
                            MyShowsView(showingCreateSheet: $showingCreateShowSheet)
                        } else {
                            InlineAuthPrompt(prompt: "Log in to see and manage your shows.") {
                                showingLogin = true
                            }
                        }
                    }
                }
            }
            .streamrBackground()
            // Registered once here, at the stack root, so it serves every
            // depth — DiscoverView's rows and carousel, and ShowDetailView's
            // episode list below them. See StreamRoute for why these are
            // values rather than inline destination closures.
            .navigationDestination(for: ShowRoute.self) { route in
                ShowDetailView(show: route.show)
            }
            .navigationDestination(for: PlayerRoute.self) { route in
                PlayerView(streamId: route.streamId)
            }
            .toolbar {
                // No navigation-bar logo on Main Stream: that screen now heads
                // itself with the large landing wordmark (see DiscoverView),
                // and two logos stacked a few points apart looked like a
                // mistake. My Stream keeps the bar mark, at the new larger
                // size.
                if segment == .mine {
                    ToolbarItem(placement: .principal) {
                        NavBarLogo()
                    }
                }

                if segment == .main && !authManager.isAuthenticated {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Log In") { showingLogin = true }
                            .foregroundStyle(.white)
                    }
                } else if segment == .mine && authManager.isAuthenticated {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingCreateShowSheet = true
                        } label: {
                            Label("New Show", systemImage: "plus")
                        }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.white)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingHamburgerMenu = true
                    } label: {
                        Image(systemName: "line.3.horizontal")
                    }
                    .foregroundStyle(.white)
                }
            }
            .sheet(isPresented: $showingLogin) {
                LoginView()
            }
            .sheet(isPresented: $showingHamburgerMenu) {
                HamburgerMenuView()
                    .presentationDetents([.medium])
            }
        }
        // "Home" means the landing page, so this clears the pushed stack AND
        // returns to the Main Stream segment — landing on My Stream after
        // asking to go home would be the wrong destination.
        .onChange(of: resetToken) { _, _ in
            path = NavigationPath()
            segment = .main
        }
    }

    private var segmentedToggle: some View {
        Picker("", selection: $segment) {
            Text("Main Stream").tag(StreamSegment.main)
            Text("My Stream").tag(StreamSegment.mine)
        }
        .pickerStyle(.segmented)
        .frame(width: 220)
        .frame(maxWidth: .infinity)
    }

}

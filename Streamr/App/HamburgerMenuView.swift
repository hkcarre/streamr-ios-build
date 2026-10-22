import SwiftUI

/// The iOS equivalent of the website's top-right hamburger dropdown (profile
/// block > Dashboard/Privacy/About/Help/Logout). "Dashboard" is deliberately
/// dropped here since the Account tab already reaches the same place one tap
/// away — no duplicate nav path. Presented as a medium-height sheet rather
/// than a side drawer, which reads as more idiomatically iOS.
struct HamburgerMenuView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingLogin = false
    @State private var showingJoinAsGuest = false
    @State private var legalLink: LegalLink?
    @State private var showingBlocked = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                    .padding(.top, 8)
                    .padding(.bottom, 20)

                VStack(spacing: 0) {
                    // Join as Guest, Privacy, About and Help now also live in
                    // Settings (reachable from the gear), per the 2026-10-08
                    // wireframe note that the gear should reach everything in
                    // My Account. Kept here too because this sheet is reachable
                    // from the Hub without going through the account tab.
                    if authManager.isAuthenticated {
                        menuRow(title: "Join Someone's Broadcast", systemImage: "person.badge.plus") {
                            showingJoinAsGuest = true
                        }
                    }

                    menuRow(title: "Privacy Policy", systemImage: "hand.raised") {
                        legalLink = .privacy
                    }
                    menuRow(title: "About", systemImage: "info.circle") {
                        legalLink = .about
                    }
                    menuRow(title: "Help & Support", systemImage: "questionmark.circle") {
                        legalLink = .help
                    }
                    // Reachable whether or not anyone is signed in: blocks are
                    // stored per device, so a signed-out viewer can have made
                    // some and must be able to undo them. Required to be
                    // reversible under App Store Guideline 1.2 -- see
                    // BlockedAccountsView.
                    menuRow(title: "Blocked accounts", systemImage: "person.slash") {
                        showingBlocked = true
                    }

                    if authManager.isAuthenticated {
                        menuRow(title: "Log Out", systemImage: "rectangle.portrait.and.arrow.right", isDestructive: true) {
                            authManager.logout()
                            dismiss()
                        }
                    } else {
                        menuRow(title: "Log In", systemImage: "person.crop.circle") {
                            showingLogin = true
                        }
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .streamrBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .fullScreenCover(isPresented: $showingJoinAsGuest) {
            JoinAsGuestView()
        }
        .sheet(isPresented: $showingLogin) {
            LoginView()
        }
        .sheet(isPresented: $showingBlocked) {
            NavigationStack { BlockedAccountsView() }
        }
        .sheet(item: $legalLink) { link in
            SafariView(url: link.url)
        }
    }

    /// Signed out, this is a real button that opens login. It used to be a
    /// plain label that looked tappable and did nothing (reported 2026-10-09),
    /// which is worse than useless on the one screen where someone goes
    /// looking for a way to sign in.
    ///
    /// The old copy said "You're browsing as a guest", which collided badly
    /// with the Join as Guest feature below it — that one means joining
    /// somebody's live stream as a second publisher, nothing to do with being
    /// signed out. Two unrelated meanings of "guest" one row apart.
    ///
    /// Branches on `isAuthenticated`, NOT on `currentUser != nil`. Keying it
    /// on the user object is what made this offer "Log in or sign up" to
    /// someone who was already signed in (reported 2026-10-11): after a
    /// relaunch the token was restored but the profile wasn't, so the header
    /// read a nil user as "signed out". KeychainStore now caches the profile
    /// too, but the auth flag stays the single source of truth for which state
    /// to show — a missing profile degrades to a name-less row, and never to
    /// a login prompt that can't be acted on.
    @ViewBuilder
    private var header: some View {
        if authManager.isAuthenticated {
            HStack(spacing: 12) {
                avatarForCurrentUser

                VStack(alignment: .leading, spacing: 2) {
                    Text(authManager.currentUser?.fullName ?? "Your account")
                        .font(StreamrFont.headline(17))
                    if let email = authManager.currentUser?.email {
                        Text(email)
                            .font(StreamrFont.caption())
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }

                Spacer()
            }
        } else {
            Button {
                showingLogin = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 36))
                        .foregroundStyle(.white.opacity(0.75))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Log in or sign up")
                            .font(StreamrFont.headline(17))
                            .foregroundStyle(.white)
                        Text("You're not signed in")
                            .font(StreamrFont.caption())
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// Shows the real profile picture. This drew a generic glyph before, even
    /// when the user had an avatar — and the hamburger is reachable from every
    /// screen, so it was the most-seen avatar slot in the app and the only
    /// fake one.
    @ViewBuilder
    private var avatarForCurrentUser: some View {
        Group {
            if let urlString = authManager.currentUser?.profilePic, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        avatarFallback
                    }
                }
            } else {
                avatarFallback
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
    }

    private var avatarFallback: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.14))
            Image(systemName: "person.fill")
                .font(.system(size: 17))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private func menuRow(
        title: String,
        systemImage: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .frame(width: 22)
                Text(title)
                    .font(StreamrFont.body(16))
                Spacer()
            }
            .foregroundStyle(isDestructive ? StreamrColor.liveRed : .white)
            .padding(.vertical, 14)
        }
        .contentShape(Rectangle())
    }
}

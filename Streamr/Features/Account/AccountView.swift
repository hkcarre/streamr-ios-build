import SwiftUI

/// The My Account tab. Previously this was a near-empty screen — name, email,
/// a photos link and a Log Out button — which is what "I go to an empty
/// screen" meant when it was reported on 2026-10-09.
///
/// Two pieces of guidance set what belongs here, and they agree:
///   - `wireframes/Mobile App Wireframes 082326.pdf` routes My Account
///     straight to the platform Destinations list.
///   - `wireframes/generic background.png` says the gear "should bring you to
///     everything in the My Account", with privacy / about / help at the
///     bottom.
///
/// So this is the full account hub, and the gear in the toolbar opens the same
/// place rather than a separate half-populated Settings screen.
struct AccountView: View {
    @EnvironmentObject private var authManager: AuthManager
    @State private var legalLink: LegalLink?
    @State private var showingJoinAsGuest = false

    var body: some View {
        NavigationStack {
            List {
                profileSection
                publishingSection
                billingSection
                securitySection
                moreSection
                logOutSection
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .streamrBackground()
            .toolbar {
                ToolbarItem(placement: .principal) { NavBarLogo() }
            }
            .sheet(item: $legalLink) { link in
                SafariView(url: link.url)
            }
            .fullScreenCover(isPresented: $showingJoinAsGuest) {
                JoinAsGuestView()
            }
        }
    }

    // MARK: - Sections

    /// Rendered whenever we're authenticated, even if the cached profile is
    /// missing — this block used to be wrapped in `if let user =
    /// authManager.currentUser`, so after a relaunch (token restored, profile
    /// not) the whole header silently vanished and the screen opened on a bare
    /// list of rows. See KeychainStore.saveUser.
    @ViewBuilder
    private var profileSection: some View {
        Section {
            HStack(spacing: 14) {
                avatar
                VStack(alignment: .leading, spacing: 3) {
                    Text(authManager.currentUser?.fullName ?? "Your account")
                        .font(StreamrFont.title(20))
                        .foregroundStyle(.white)
                    if let email = authManager.currentUser?.email {
                        Text(email)
                            .font(StreamrFont.caption())
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            row(title: "Profile Picture", systemImage: "person.crop.circle") {
                EditProfilePhotosView()
            }
        }
    }

    private var publishingSection: some View {
        Section {
            // The wireframe routes My Account directly at Destinations, so it
            // leads this group rather than being buried under a gear.
            row(title: "Destinations", systemImage: "arrow.triangle.branch") {
                DestinationsView()
            }

            button(title: "Join Someone's Broadcast", systemImage: "person.badge.plus") {
                showingJoinAsGuest = true
            }
        } header: {
            header("Publishing")
        }
    }

    private var billingSection: some View {
        Section {
            row(title: "Subscription", systemImage: "creditcard") { PlansView() }
            row(title: "Payment", systemImage: "wallet.pass") { PaymentMethodsView() }
        } header: {
            header("Billing")
        }
    }

    private var securitySection: some View {
        Section {
            row(title: "Change Password", systemImage: "lock") { ChangePasswordView() }
            row(title: "Delete Account", systemImage: "trash", tint: StreamrColor.liveRed) {
                DeleteAccountView()
            }
        } header: {
            header("Account")
        }
    }

    private var moreSection: some View {
        Section {
            button(title: "Privacy Policy", systemImage: "hand.raised") { legalLink = .privacy }
            button(title: "About", systemImage: "info.circle") { legalLink = .about }
            button(title: "Help & Support", systemImage: "questionmark.circle") { legalLink = .help }
            button(title: "Terms & Conditions", systemImage: "doc.text") { legalLink = .terms }
        } header: {
            header("More")
        }
    }

    private var logOutSection: some View {
        Section {
            Button(role: .destructive) {
                authManager.logout()
            } label: {
                Text("Log Out")
                    .font(StreamrFont.headline(17))
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(StreamrColor.liveRed)
            }
            .listRowBackground(Color.white.opacity(0.12))
        }
    }

    // MARK: - Row builders

    private func row<Destination: View>(
        title: String,
        systemImage: String,
        tint: Color = .white,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            Label(title, systemImage: systemImage)
                .font(StreamrFont.body(16))
                .foregroundStyle(tint)
        }
        .listRowBackground(Color.white.opacity(0.06))
    }

    private func button(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(StreamrFont.body(16))
                .foregroundStyle(.white)
        }
        .listRowBackground(Color.white.opacity(0.06))
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(StreamrFont.caption())
            .foregroundStyle(.white.opacity(0.6))
            .textCase(nil)
    }

    @ViewBuilder
    private var avatar: some View {
        Group {
            if let urlString = authManager.currentUser?.profilePic, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        placeholderAvatar
                    }
                }
            } else {
                placeholderAvatar
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(Circle())
    }

    private var placeholderAvatar: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.12))
            Image(systemName: "person.fill")
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}

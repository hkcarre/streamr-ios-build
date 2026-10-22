import SwiftUI
import SafariServices

/// Wraps the website's CMS-driven legal/info pages (About, Help, Privacy,
/// Terms) in an in-app browser instead of rendering their HTML natively —
/// keeps content always in sync with the live site with zero parsing.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

/// Real URLs read from orca-nebula's header dropdown JSX + the terms-conditions
/// link the user supplied directly — centralized here so they can't drift
/// across the hamburger menu and Settings call sites.
enum LegalLink: String, Identifiable, CaseIterable {
    case privacy
    case about
    case help
    case terms

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privacy: "Privacy Policy"
        case .about: "About"
        case .help: "Help & Support"
        case .terms: "Terms & Conditions"
        }
    }

    var url: URL {
        switch self {
        case .privacy: URL(string: "https://streamr.nyc/privacy-policy")!
        case .about: URL(string: "https://streamr.nyc/about")!
        case .help: URL(string: "https://streamr.nyc/help-support")!
        case .terms: URL(string: "https://streamr.nyc/terms-conditions")!
        }
    }
}

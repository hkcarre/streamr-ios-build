import SwiftUI

/// Shared nav-bar logo mark, used wherever a screen's toolbar needs it
/// (My Stream, the Add Stream wizard, My Account). Toolbar items don't
/// propose a size the way a normal container does — .scaledToFit() with only
/// .frame(height:) has no width to resolve against and renders at zero size,
/// so both dimensions are given explicitly. logo.png is 1702x630.
/// Default height raised from 26 to 36 on 2026-10-11 ("can we have the logo
/// much larger than what it is currently?"). 36 is about as tall as a logo can
/// sit in a 44pt navigation bar before the bar starts clipping it; the mark
/// keeps its 1702:630 aspect, so this is a genuine ~38% increase in both
/// dimensions rather than a stretch.
struct NavBarLogo: View {
    var height: CGFloat = 36

    var body: some View {
        Image("Logo")
            .resizable()
            .scaledToFit()
            .frame(width: height * 1702 / 630, height: height)
            .accessibilityLabel("Streamr")
    }
}

/// The oversized wordmark that heads the landing page, from the "Landing"
/// screen of `Mobile App Wireframe 092726.pdf` — logo, then a strip of shows,
/// then Log In. Much larger than the navigation-bar mark because on that screen
/// it IS the header, not chrome.
struct LandingLogo: View {
    var height: CGFloat = 64

    var body: some View {
        Image("Logo")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .accessibilityLabel("Streamr")
    }
}

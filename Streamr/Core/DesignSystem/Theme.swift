import SwiftUI

/// Brand tokens lifted from orca-nebula's `src/style/css/style.css` `:root` block,
/// so the iOS app stays visually consistent with the web user app.
enum StreamrColor {
    /// --primary-color
    static let primary = Color(hex: "9AD0AF")
    // The website's CSS declares `body` background TWICE, both unscoped. The
    // app originally took the first pair (#7A44B6 -> #4768DA), but the second
    // comes later in the cascade and therefore wins on every page. Verified
    // 2026-10-08 against the deployed bundle
    // (streamr.nyc/assets/index-CP9gxTOd.css):
    //   body{...background:linear-gradient(180deg,#7a44b6,#4768da)   <- dead
    //   body{background:linear-gradient(180deg,#7643b9,#5a5aca)      <- wins
    // So these are what users actually see on the web. The duplicate is
    // unresolved on the web side; matching what ships is the safer default.
    /// Body background gradient start
    static let gradientStart = Color(hex: "7643B9")
    /// Body background gradient end
    static let gradientEnd = Color(hex: "5A5ACA")
    /// Secondary accent used on buttons/badges
    static let accentBlue = Color(hex: "4768DA")

    static let liveRed = Color(hex: "FF4B30")
    static let warningGold = Color(hex: "FFC978")
    static let successGreen = Color(hex: "22C55E")

    /// Icons, labels and inner circles on the floating bottom nav. Sampled
    /// directly from `wireframes/bottom navigator.png` rather than estimated.
    ///
    /// The capsule's own flat #182353 fill from that wireframe is gone — the
    /// navigator is a liquid-glass surface now (see `LiquidGlass`), so there is
    /// no solid fill colour left to name.
    static let navTint = Color(hex: "E7F3FF")

    /// The bright violet outline on every liquid-glass surface.
    ///
    /// Sampled pixel by pixel from the reference button supplied 2026-10-11,
    /// not estimated: the ring reads #AF4FE7 along the top, #AD4FE9 along the
    /// bottom, #B451E7 on the left and #A14CE6 on the right — within a few
    /// points of each other all the way round, so it's a flat stroke rather
    /// than a gradient, and a single colour is the faithful match.
    ///
    /// Reads as pink against the #7643B9 background it sits on, which is how
    /// it was described; in isolation it's a violet-leaning magenta.
    static let glassOutline = Color(hex: "AF4FE7")

    static let surfaceDark = Color(hex: "2C303A")
    static let borderColor = Color(hex: "3A3A3A")
    static let grayText = Color(hex: "727272")
}

enum StreamrGradient {
    /// The signature app-wide purple-to-blue background.
    static let background = LinearGradient(
        colors: [StreamrColor.gradientStart, StreamrColor.gradientEnd],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Rainbow accent border used on premium/featured cards on the web app.
    static let premiumBorder = LinearGradient(
        colors: [
            Color(hex: "D37778"),
            Color(hex: "9AD0AF"),
            Color(hex: "7A44B6"),
            Color(hex: "E64040"),
            Color(hex: "DDC1E1")
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Rainbow accent border variant used to highlight live/active state.
    static let liveBorder = LinearGradient(
        colors: [Color(hex: "4768DA"), Color(hex: "22C55E"), Color(hex: "4768DA")],
        startPoint: .top,
        endPoint: .bottom
    )
}

/// Backdrop that applies the brand gradient behind a screen's content.
struct StreamrBackground: ViewModifier {
    func body(content: Content) -> some View {
        ZStack {
            StreamrGradient.background.ignoresSafeArea()
            content
        }
    }
}

extension View {
    func streamrBackground() -> some View {
        modifier(StreamrBackground())
    }
}

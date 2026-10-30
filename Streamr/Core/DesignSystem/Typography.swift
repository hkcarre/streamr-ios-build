import SwiftUI

/// Heebo, the brand typeface named by the Style Guide (`assets/Style Guide.pdf`:
/// "Font: Heebo"). Shipped as `Streamr/Resources/Fonts/Heebo-Variable.ttf`, the
/// OFL-licensed variable font from Google Fonts, registered through `UIAppFonts`
/// in project.yml. The licence travels with it as `Heebo-OFL.txt`.
///
/// It's a VARIABLE font with named weight instances from Thin to Black, so one
/// 122KB file covers every weight the app asks for and `.weight(_:)` resolves
/// against the `wght` axis. The family name registered with the system is plain
/// `"Heebo"` (read from the font's own name table, not assumed).
///
/// Two deliberate properties of every helper below:
///
/// **Dynamic Type.** Each size is declared `relativeTo:` a system text style, so
/// the whole app scales with the reader's Larger Text setting. Before this,
/// every call was `.system(size:)` with a fixed point size — which is NOT
/// Dynamic Type-aware — so a reader who had turned text up saw no change
/// anywhere in the app. That is an accessibility failure Apple's reviewers
/// check for.
///
/// **Larger defaults.** Base sizes are up across the board (title 28→30,
/// headline 20→22, body 16→17, caption 13→14) per "make the fonts as large as
/// UX allows". 17pt body is Apple's own default for readable running text; the
/// previous 16 was below it. Call sites that pass an explicit size keep control,
/// so this raises the floor without overriding considered decisions.
///
/// If the font ever fails to register, `Font.custom` falls back to the system
/// font silently rather than crashing — the app degrades to its previous look
/// instead of breaking.
enum StreamrFont {
    /// The family name as the system knows it. Matches name ID 1 in the font's
    /// name table.
    private static let family = "Heebo"

    static func title(_ size: CGFloat = 30) -> Font {
        .custom(family, size: size, relativeTo: .title)
        .weight(.bold)
    }

    static func headline(_ size: CGFloat = 22) -> Font {
        .custom(family, size: size, relativeTo: .headline)
        .weight(.semibold)
    }

    static func body(_ size: CGFloat = 17) -> Font {
        .custom(family, size: size, relativeTo: .body)
        .weight(.regular)
    }

    static func caption(_ size: CGFloat = 14) -> Font {
        .custom(family, size: size, relativeTo: .caption)
        .weight(.medium)
    }
}

extension View {
    /// Caps how far Dynamic Type may scale inside a view that genuinely cannot
    /// reflow — the floating tab bar's three fixed columns, say.
    ///
    /// Used sparingly and never on running text: clamping body copy defeats the
    /// point of supporting Dynamic Type at all. `.accessibility1` still allows a
    /// substantial increase over the default.
    func streamrDynamicTypeClamp() -> some View {
        dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

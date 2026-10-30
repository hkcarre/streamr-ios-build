import SwiftUI

/// The floating bottom navigator: a liquid-glass capsule sitting over the
/// gradient, rather than iOS's stock translucent tab bar.
///
/// Replaces the system `TabView` chrome because the shape can't be produced by
/// `UITabBar` appearance alone — it floats inset from the screen edges with
/// fully rounded ends, and two of its three items are a filled circle rather
/// than a glyph. The `TabView` underneath is kept (hidden) so view identity,
/// state preservation and the Add Stream interception all keep working exactly
/// as before.
///
/// `wireframes/bottom navigator.png` is treated as a LAYOUT guide only — three
/// slots, floating capsule, two of them filled circles, at the sizes confirmed
/// on 2026-10-11. Its flat 2D fill is an artifact of the tool it was drawn in,
/// not the intended finish: "I prefer the liquid glass feel of the original…
/// that's a format/layout guide, the original style is better."
///
/// The surface itself is `LiquidGlassSurface`, shared with the Add Stream type
/// buttons so the two stay identical by construction.
struct StreamrTabBar: View {
    @Binding var selection: StreamrTab
    /// Drawn in the My Account slot when the signed-in user has one, matching
    /// the wireframe's "AVI" avatar bubble.
    let avatarURL: String?
    /// Fired when a tab that is ALREADY selected is tapped again.
    ///
    /// iOS users expect this to take them back to the top of that tab, and the
    /// stock tab bar does it for free. This bar is hand-built, so it has to be
    /// wired explicitly — without it, tapping Hub while already on Hub set the
    /// same value and did nothing, so anyone pushed into a show or an episode
    /// had no way back to the landing page ("I can't seem to go to home",
    /// 2026-10-11).
    var onReselect: ((StreamrTab) -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            item(.stream) {
                Image(systemName: "wifi")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(StreamrColor.navTint)
            } label: {
                Text("Hub")
            }

            item(.addStream) {
                circle {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.black)
                }
            } label: {
                Text("Add Stream")
            }

            item(.account) {
                circle {
                    avatarContent
                }
            } label: {
                Text("My Account")
            }
        }
        .padding(.vertical, 10)
        // Same treatment as the Add Stream type buttons — see LiquidGlass.
        //
        // The navy #182353 tint this used to carry is gone: at the 0.55 it
        // needed to read as navy it was close to opaque, which is the opposite
        // of the glass look the reference button shows. A light tint lets the
        // gradient through and blur, and the violet outline is what now defines
        // the capsule's edge instead of the fill.
        //
        // Icon and label sizes are deliberately untouched — those were
        // confirmed right on 2026-10-11; only the surface changed.
        .liquidGlass(in: Capsule(style: .continuous), tintOpacity: 0.14, shadowRadius: 14)
        .padding(.horizontal, 20)
        // Three fixed columns in a capsule cannot reflow, so this is one of the
        // few places a Dynamic Type ceiling is justified. Everything else in the
        // app scales freely — see Typography.
        .streamrDynamicTypeClamp()
    }

    // MARK: - Pieces

    private func item<Icon: View, Label: View>(
        _ tab: StreamrTab,
        @ViewBuilder icon: () -> Icon,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button {
            if selection == tab {
                onReselect?(tab)
            } else {
                selection = tab
            }
        } label: {
            VStack(spacing: 6) {
                icon()
                    .frame(height: 34)
                label()
                    .font(StreamrFont.headline(14))
                    .foregroundStyle(StreamrColor.navTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            // Whole column is tappable, not just the glyph.
            .contentShape(Rectangle())
            // Selected state is deliberately subtle: the wireframe shows no
            // active indicator, so this only dims the two you're not on rather
            // than inventing chrome the design doesn't have.
            .opacity(selection == tab || tab == .addStream ? 1 : 0.65)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == tab ? [.isButton, .isSelected] : .isButton)
    }

    private func circle<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack {
            Circle().fill(StreamrColor.navTint)
            content()
        }
        .frame(width: 34, height: 34)
    }

    @ViewBuilder
    private var avatarContent: some View {
        if let avatarURL, let url = URL(string: avatarURL) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    avatarFallback
                }
            }
            .frame(width: 34, height: 34)
            .clipShape(Circle())
        } else {
            avatarFallback
        }
    }

    private var avatarFallback: some View {
        Image(systemName: "person.fill")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.black.opacity(0.75))
    }
}

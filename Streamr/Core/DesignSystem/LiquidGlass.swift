import SwiftUI

/// The app's translucent "liquid glass" surface: real blur of whatever sits
/// behind it, a light tint to lift it off the background, and a bright violet
/// outline.
///
/// Built against the reference button supplied 2026-10-11 and measured rather
/// than eyeballed. Three things that image tells us, each of which drives a
/// line below:
///
///   - **The outline is flat.** #AF4FE7 top, #AD4FE9 bottom, #B451E7 left,
///     #A14CE6 right — so one colour, not a gradient (see
///     `StreamrColor.glassOutline`).
///   - **The fill is translucent, not solid.** The interior reads #8245D9
///     where the background behind it is #7443B9 — brighter AND bluer. A solid
///     fill couldn't do that; blurred background plus a light tint does.
///   - **It lifts off the page.** Hence the shadow, which also keeps the
///     outline from merging into a similarly-coloured background.
///
/// `.ultraThinMaterial` rather than iOS 26's native Liquid Glass: this app
/// deploys to iOS 17, and material renders the same translucency on every
/// version it ships to instead of flattening silently on older ones.
struct LiquidGlassSurface<S: InsettableShape>: View {
    let shape: S
    /// How much light tint sits over the blur. The nav bar carries more than a
    /// button does, because it has to hold white icons legibly over whatever
    /// scrolls underneath it.
    var tintOpacity: Double = 0.12
    var outlineOpacity: Double = 1
    var lineWidth: CGFloat = 1.5
    var shadowRadius: CGFloat = 12
    var shadowOpacity: Double = 0.22

    var body: some View {
        shape
            .fill(.ultraThinMaterial)
            // `Color.white` spelled out, not `.white`: in a generic ShapeStyle
            // position the leading-dot form has more than one candidate and
            // doesn't always infer.
            .overlay { shape.fill(Color.white.opacity(tintOpacity)) }
            .overlay {
                shape.strokeBorder(
                    StreamrColor.glassOutline.opacity(outlineOpacity),
                    lineWidth: lineWidth
                )
            }
            .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: 5)
    }
}

extension View {
    /// Puts a `LiquidGlassSurface` behind this view.
    ///
    /// One implementation shared by the bottom navigator and the Add Stream
    /// type buttons, so the two can't drift apart — they were asked for as the
    /// same treatment, and keeping two copies of a translucent-fill-plus-stroke
    /// stack is how "the same" quietly stops being true.
    func liquidGlass<S: InsettableShape>(
        in shape: S,
        tintOpacity: Double = 0.12,
        outlineOpacity: Double = 1,
        lineWidth: CGFloat = 1.5,
        shadowRadius: CGFloat = 12,
        shadowOpacity: Double = 0.22
    ) -> some View {
        background {
            LiquidGlassSurface(
                shape: shape,
                tintOpacity: tintOpacity,
                outlineOpacity: outlineOpacity,
                lineWidth: lineWidth,
                shadowRadius: shadowRadius,
                shadowOpacity: shadowOpacity
            )
        }
    }
}

import SwiftUI

/// A titled horizontal row of episode cards — the landing page's "Now
/// Streaming" strip, and the same strip on the signed-out account screen.
///
/// Extracted from DiscoverView so the two can't drift apart. The signed-out
/// screen asked for "the Streamr logo and the carousel" (2026-10-14), and a
/// second hand-rolled copy of this row is exactly how one of them ends up with
/// different card sizes or spacing a month later.
///
/// Needs an enclosing NavigationStack that registers `PlayerRoute` — the cards
/// push by value, see StreamRoute for why.
struct StreamStrip: View {
    let title: String
    let streams: [StreamItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(StreamrFont.headline(16))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(streams) { stream in
                        NavigationLink(value: PlayerRoute(streamId: stream.id)) {
                            StreamCardView(stream: stream)
                                .frame(width: 220)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

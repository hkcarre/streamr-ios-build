import SwiftUI

struct StreamCardView: View {
    let stream: StreamItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Without an explicit width, the card sizes to its widest child
            // instead of filling the grid column — cards ended up visibly
            // uneven/misaligned once real (non-uniform) content was in play.
            ZStack(alignment: .topLeading) {
                // `stream.thumbnail` existed on the model and was never read,
                // so every card in every carousel and episode list was the same
                // blank grey box with the same waveform glyph — a whole show's
                // episode list was visually undifferentiated and you picked by
                // title alone. The glyph is now only the fallback.
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(StreamrColor.surfaceDark)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .overlay {
                        artwork
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                if stream.isLive {
                    Text("LIVE")
                        .font(StreamrFont.caption(11))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(StreamrColor.liveRed)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                        .padding(10)
                }
            }

            Text(stream.title)
                .font(StreamrFont.headline(15))
                .foregroundStyle(.white)
                .lineLimit(1)

            if let description = stream.description, !description.isEmpty {
                Text(description)
                    .font(StreamrFont.caption())
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var artwork: some View {
        if let thumbnail = stream.thumbnail, let url = URL(string: thumbnail) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    placeholderGlyph
                }
            }
            // `.fill` overflows its frame by design; without clipping here the
            // overflow lays out before the parent's mask and pushes the title
            // below it off position.
            .clipped()
        } else {
            placeholderGlyph
        }
    }

    private var placeholderGlyph: some View {
        Image(systemName: "waveform")
            .font(.system(size: 32))
            .foregroundStyle(.white.opacity(0.25))
    }
}

import SwiftUI

/// Main Stream's show row — cover art, title, and host — distinct from
/// Shows/ShowRowView (name/description/autoSharing, used by My Shows):
/// different data is available here (Show.host/streamScheduledTime only
/// come from the list-with-category endpoint this screen uses) and the
/// wireframe shows a materially different layout, so this stays a
/// separate, single-purpose view rather than branching one shared row.
struct MainStreamShowRowView: View {
    let show: Show
    /// Whether to render the next scheduled time — only meaningful when
    /// this row came from the Future toggle; Past results never carry
    /// `streamScheduledTime` to begin with.
    let showScheduledTime: Bool

    var body: some View {
        HStack(spacing: 12) {
            coverArt

            VStack(alignment: .leading, spacing: 6) {
                Text(show.name)
                    .font(StreamrFont.headline(15))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    hostAvatar
                    if let hostName = show.host?.displayName, !hostName.isEmpty {
                        Text(hostName)
                            .font(StreamrFont.caption())
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }

                if showScheduledTime, let nextTime = nextScheduledTimeLabel {
                    Text(nextTime)
                        .font(StreamrFont.caption(11))
                        .foregroundStyle(StreamrColor.primary)
                }
            }

            Spacer()
        }
        .padding(12)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var coverArt: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(StreamrColor.surfaceDark)
            .frame(width: 56, height: 56)
            .overlay {
                if let coverPic = show.coverPic, let url = URL(string: coverPic) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.clear
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    Image(systemName: "mic.fill")
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var hostAvatar: some View {
        Circle()
            .fill(avatarColor)
            .frame(width: 16, height: 16)
            .overlay {
                if let profilePic = show.host?.profilePic, let url = URL(string: profilePic) {
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.clear
                    }
                    .clipShape(Circle())
                }
            }
    }

    /// Purely decorative variety (matches the wireframe's differently
    /// colored avatar dots) — picked deterministically from the host id so
    /// a given host always renders the same color, not random per render.
    private var avatarColor: Color {
        let palette: [Color] = [StreamrColor.primary, StreamrColor.accentBlue, StreamrColor.warningGold]
        guard let id = show.host?.id, !id.isEmpty else { return StreamrColor.primary }
        let index = abs(id.hashValue) % palette.count
        return palette[index]
    }

    private var nextScheduledTimeLabel: String? {
        guard let raw = show.streamScheduledTime?.first?.scheduledTime else { return nil }
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: raw) else { return nil }
        let display = DateFormatter()
        display.dateFormat = "MMM d, h:mm a"
        return "Starts \(display.string(from: date))"
    }
}

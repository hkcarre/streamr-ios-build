import SwiftUI
import UIKit

/// The host's own camera plus any guests who have joined, laid out so every
/// face is as large as the space allows.
///
/// Asked for on 2026-10-14: "I would like to be able to see both cameras side
/// by side or if there are more than 1, well distributed in the screen so we
/// can see the face of the person (like a Zoom call)."
///
/// Two people STACK rather than sitting side by side, which is a deliberate
/// departure from the literal request. The container is portrait (3:4), so two
/// side-by-side tiles would each be tall and narrow — about 170pt wide — and a
/// face inside a `.fit` frame that shape ends up tiny. Stacked, each tile gets
/// the full width. Phone video apps stack for the same reason. Three or more
/// go to two columns, where the tiles are squarer and columns do pay off.
struct BroadcastGridView: View {
    let localPreview: UIView?
    let guestViews: [String: UIView]

    /// Sorted so tiles keep their position between redraws — iterating the
    /// dictionary directly would let guests swap places whenever it rehashes.
    private var guestIDs: [String] {
        guestViews.keys.sorted()
    }

    private var tileCount: Int {
        guestIDs.count + 1
    }

    private var columns: Int {
        tileCount <= 2 ? 1 : 2
    }

    var body: some View {
        GeometryReader { geo in
            let rows = Int(ceil(Double(tileCount) / Double(columns)))
            let spacing: CGFloat = 4
            let tileWidth = (geo.size.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            let tileHeight = (geo.size.height - spacing * CGFloat(rows - 1)) / CGFloat(rows)

            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(tileWidth), spacing: spacing), count: columns),
                spacing: spacing
            ) {
                tile(localPreview)
                    .frame(width: tileWidth, height: tileHeight)

                ForEach(guestIDs, id: \.self) { id in
                    tile(guestViews[id])
                        .frame(width: tileWidth, height: tileHeight)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
    }

    private func tile(_ view: UIView?) -> some View {
        CameraPreviewView(previewView: view)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

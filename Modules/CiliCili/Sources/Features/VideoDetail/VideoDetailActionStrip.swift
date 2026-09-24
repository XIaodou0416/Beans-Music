import SwiftUI

struct VideoDetailActionStrip: View, Equatable {
    enum Metrics {
        static let columnSpacing: CGFloat = 7
        static let rowHeight: CGFloat = 32
        static let actionLabelSide: CGFloat = 28
        static let avatarImageSide: CGFloat = 34
        static let avatarSide: CGFloat = avatarImageSide
        static let followHeight: CGFloat = actionLabelSide
        static let iconSize: CGFloat = 13
        static let avatarPixelSize = 112
    }

    let model: VideoDetailActionStripModel
    let onFollow: () -> Void
    let onLike: () -> Void
    let onCoin: () -> Void
    let onFavorite: () -> Void
    let onShareTap: () -> Void

    static func == (lhs: VideoDetailActionStrip, rhs: VideoDetailActionStrip) -> Bool {
        lhs.model == rhs.model
    }

    var body: some View {
        let layout = VideoDetailActionStripLayout(contentWidth: model.contentWidth)

        GlassEffectContainer(spacing: layout.columnSpacing) {
            VideoDetailActionStripButtonRow(
                model: model,
                layout: layout,
                onFollow: onFollow,
                onLike: onLike,
                onCoin: onCoin,
                onFavorite: onFavorite,
                onShareTap: onShareTap
            )
        }
        .frame(width: model.contentWidth, height: layout.rowHeight, alignment: .center)
    }
}

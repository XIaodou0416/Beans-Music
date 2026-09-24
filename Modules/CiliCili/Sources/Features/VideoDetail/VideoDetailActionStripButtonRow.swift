import SwiftUI

struct VideoDetailActionStripButtonRow: View {
    @Environment(\.appThemeTintColor) private var appTintColor

    let model: VideoDetailActionStripModel
    let layout: VideoDetailActionStripLayout
    let onFollow: () -> Void
    let onLike: () -> Void
    let onCoin: () -> Void
    let onFavorite: () -> Void
    let onShareTap: () -> Void

    var body: some View {
        HStack(spacing: layout.columnSpacing) {
            VideoDetailActionStripOwnerAvatar(owner: model.owner)
                .frame(width: layout.columnWidth, height: layout.rowHeight)

            VideoDetailActionStripFollowControl(
                isFollowing: model.isFollowing,
                canFollow: (model.owner?.mid ?? 0) > 0,
                isMutating: model.isMutatingFollow,
                action: onFollow
            )
                .frame(width: layout.columnWidth, height: layout.rowHeight)

            VideoDetailActionStripIconButton(
                accessibilityTitle: "点赞",
                systemImage: "hand.thumbsup.fill",
                foregroundStyle: model.isLiked ? appTintColor : .primary,
                isDisabled: model.isMutatingLike,
                action: onLike
            )
            .frame(width: layout.columnWidth, height: layout.rowHeight)

            VideoDetailActionStripIconButton(
                accessibilityTitle: "投币",
                systemImage: "bitcoinsign.circle.fill",
                foregroundStyle: model.isCoined ? appTintColor : .primary,
                isDisabled: model.isMutatingCoin || model.coinCount >= 2,
                action: onCoin
            )
            .frame(width: layout.columnWidth, height: layout.rowHeight)

            VideoDetailActionStripIconButton(
                accessibilityTitle: model.isFavorited ? "已收藏" : "收藏",
                systemImage: "star.fill",
                foregroundStyle: model.isFavorited ? appTintColor : .primary,
                isDisabled: model.isMutatingFavorite || !model.canFavorite,
                action: onFavorite
            )
            .frame(width: layout.columnWidth, height: layout.rowHeight)

            VideoDetailActionStripShareButton(
                shareURL: model.shareURL,
                shareSubject: model.shareSubject,
                shareMessage: model.shareMessage,
                onShareTap: onShareTap
            )
                .frame(width: layout.columnWidth, height: layout.rowHeight)
        }
    }
}

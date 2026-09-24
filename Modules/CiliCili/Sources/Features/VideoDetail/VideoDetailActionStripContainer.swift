import SwiftUI

struct VideoDetailActionStripContainer: View {
    @ObservedObject var descriptionStore: VideoDetailDescriptionRenderStore
    @ObservedObject var store: VideoDetailInteractionRenderStore
    let contentWidth: CGFloat
    let onFollow: () -> Void
    let onLike: () -> Void
    let onCoin: () -> Void
    let onFavorite: () -> Void
    let onShareTap: () -> Void

    var body: some View {
        VideoDetailActionStrip(
            model: model,
            onFollow: onFollow,
            onLike: onLike,
            onCoin: onCoin,
            onFavorite: onFavorite,
            onShareTap: onShareTap
        )
        .equatable()
    }

    private var model: VideoDetailActionStripModel {
        let interaction = store.interactionState
        return VideoDetailActionStripModel(
            owner: ownerForDisplay,
            canFavorite: descriptionStore.canFavorite,
            shareURL: descriptionStore.shareURL,
            shareSubject: descriptionStore.shareSubject,
            shareMessage: descriptionStore.shareMessage,
            contentWidth: contentWidth,
            isFollowing: interaction.isFollowing,
            isLiked: interaction.isLiked,
            isCoined: interaction.isCoined,
            isFavorited: interaction.isFavorited,
            coinCount: interaction.coinCount,
            isMutatingLike: store.isMutatingInteraction,
            isMutatingCoin: store.isMutatingInteraction,
            isMutatingFavorite: store.isMutatingInteraction,
            isMutatingFollow: store.isMutatingInteraction
        )
    }

    private var ownerForDisplay: VideoOwner? {
        guard let owner = descriptionStore.owner, owner.mid > 0 else { return nil }
        return owner
    }
}

import Foundation

extension VideoDetailViewModel {
    func syncRelatedRenderStore() {
        relatedRenderStore.update(
            related: related,
            state: relatedState,
            lastLoadTimedOut: lastRelatedLoadTimedOut
        )
    }

    func syncInteractionRenderStore() {
        interactionRenderStore.update(
            interactionState: interactionState,
            interactionMessage: interactionMessage,
            isMutatingInteraction: isMutatingInteraction,
            isMutatingLike: isMutatingLike,
            isMutatingCoin: isMutatingCoin,
            isMutatingFavorite: isMutatingFavorite,
            isMutatingFollow: isMutatingFollow,
            playbackFallbackMessage: playbackFallbackMessage
        )
    }

    func syncPlaybackRenderStore() {
        playbackRenderStore.update(VideoDetailPlaybackRenderSnapshot(viewModel: self))
    }
}

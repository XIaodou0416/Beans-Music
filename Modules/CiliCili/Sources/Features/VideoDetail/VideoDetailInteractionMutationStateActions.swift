import Foundation

extension VideoDetailViewModel {
    func refreshInteractionMutationAggregate() {
        let nextValue = isMutatingLike ||
            isMutatingCoin ||
            isMutatingFavorite ||
            isMutatingFollow
        guard isMutatingInteraction != nextValue else { return }
        isMutatingInteraction = nextValue
    }

    func isInteractionMutationActive(_: VideoDetailInteractionMutationKind) -> Bool {
        return isMutatingInteraction
    }

    func setInteractionMutationActive(_ active: Bool, for kind: VideoDetailInteractionMutationKind) {
        switch kind {
        case .like:
            isMutatingLike = active
        case .coin:
            isMutatingCoin = active
        case .favorite:
            isMutatingFavorite = active
        case .follow:
            isMutatingFollow = active
        }
    }
}

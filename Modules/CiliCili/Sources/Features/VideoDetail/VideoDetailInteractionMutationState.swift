import Foundation

struct VideoDetailInteractionMutationState {
    var isMutatingLike = false
    var isMutatingCoin = false
    var isMutatingFavorite = false
    var isMutatingFollow = false
}

extension VideoDetailViewModel {
    var isMutatingLike: Bool {
        get { interactionMutationState.isMutatingLike }
        set {
            interactionMutationState.isMutatingLike = newValue
            refreshInteractionMutationAggregate()
            scheduleRenderStoreSync(.interaction)
        }
    }

    var isMutatingCoin: Bool {
        get { interactionMutationState.isMutatingCoin }
        set {
            interactionMutationState.isMutatingCoin = newValue
            refreshInteractionMutationAggregate()
            scheduleRenderStoreSync(.interaction)
        }
    }

    var isMutatingFavorite: Bool {
        get { interactionMutationState.isMutatingFavorite }
        set {
            interactionMutationState.isMutatingFavorite = newValue
            refreshInteractionMutationAggregate()
            scheduleRenderStoreSync([.interaction, .favoriteFolder])
        }
    }

    var isMutatingFollow: Bool {
        get { interactionMutationState.isMutatingFollow }
        set {
            interactionMutationState.isMutatingFollow = newValue
            refreshInteractionMutationAggregate()
            scheduleRenderStoreSync([.interaction, .description])
        }
    }
}

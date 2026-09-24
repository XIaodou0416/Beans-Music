import Foundation
import Combine

@MainActor
final class VideoDetailInteractionRenderStore: ObservableObject {
    @Published private var snapshot = VideoDetailInteractionRenderSnapshot()
    private var deferredSnapshot = VideoDetailDeferredValue<VideoDetailInteractionRenderSnapshot>()

    var interactionState: VideoInteractionState { snapshot.interactionState }
    var interactionMessage: String? { snapshot.interactionMessage }
    var isMutatingInteraction: Bool { snapshot.isMutatingInteraction }
    var isMutatingLike: Bool { snapshot.isMutatingLike }
    var isMutatingCoin: Bool { snapshot.isMutatingCoin }
    var isMutatingFavorite: Bool { snapshot.isMutatingFavorite }
    var isMutatingFollow: Bool { snapshot.isMutatingFollow }
    var playbackFallbackMessage: String? { snapshot.playbackFallbackMessage }

    func update(
        interactionState: VideoInteractionState,
        interactionMessage: String?,
        isMutatingInteraction: Bool,
        isMutatingLike: Bool,
        isMutatingCoin: Bool,
        isMutatingFavorite: Bool,
        isMutatingFollow: Bool,
        playbackFallbackMessage: String?
    ) {
        setSnapshot(
            VideoDetailInteractionRenderSnapshot(
                interactionState: interactionState,
                interactionMessage: interactionMessage,
                isMutatingInteraction: isMutatingInteraction,
                isMutatingLike: isMutatingLike,
                isMutatingCoin: isMutatingCoin,
                isMutatingFavorite: isMutatingFavorite,
                isMutatingFollow: isMutatingFollow,
                playbackFallbackMessage: playbackFallbackMessage
            )
        )
    }

    private func setSnapshot(_ next: VideoDetailInteractionRenderSnapshot) {
        guard let next = deferredSnapshot.submit(next, current: snapshot, isEquivalent: ==) else {
            return
        }
        snapshot = next
    }

    func setUpdatesDeferred(_ deferred: Bool) {
        guard let pending = deferredSnapshot.setDeferred(deferred), pending != snapshot else { return }
        snapshot = pending
    }
}

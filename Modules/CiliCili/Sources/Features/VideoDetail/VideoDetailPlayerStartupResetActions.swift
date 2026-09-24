import Foundation

extension VideoDetailViewModel {
    func resetStablePlayerForMissingVariant() {
        finishPlaybackStartupWaiters(with: nil)
        stablePlayerViewModel?.stop()
        stablePlayerViewModel = nil
        clearPlaybackTransitionPlayer()
        stablePlayerIdentity = nil
        stablePlayerErrorCancellable = nil
        stablePlayerFirstFrameCancellable = nil
        syncPlayerIdentityRenderStore()
    }

    func resetStablePlayerObserversForNewIdentity(_ identity: String) {
        stablePlayerIdentity = identity
        stablePlayerErrorCancellable = nil
        stablePlayerFirstFrameCancellable = nil
    }
}

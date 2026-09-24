import Foundation

extension VideoDetailViewModel {
    @discardableResult
    func discardTerminatedStablePlayerIfNeeded() -> Bool {
        guard stablePlayerViewModel?.isTerminated == true else { return false }
        finishPlaybackStartupWaiters(with: nil)
        stablePlayerViewModel = nil
        clearPlaybackTransitionPlayer()
        stablePlayerIdentity = nil
        stablePlayerErrorCancellable = nil
        stablePlayerFirstFrameCancellable = nil
        syncPlayerIdentityRenderStore()
        return true
    }

    func cancelRelatedLoad() {
        cancelRelatedLoadingTask()
        cancelRelatedRefreshTask()
        cancelRelatedArtworkPrefetchTask()
        if related.isEmpty, relatedState.isLoading {
            relatedState = .idle
        }
    }
}

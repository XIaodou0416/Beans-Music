import Foundation

extension VideoDetailViewModel {
    func cancelBackgroundWork() {
        cancelSupplementalWork()
        detailLoadingTask?.cancel()
        detailLoadingTask = nil
        detailLoadingToken = nil
    }

    func cancelSupplementalWork() {
        cancelBackgroundTasks()
        pageLoadingTask?.cancel()
        pageLoadingTask = nil
        pageLoadingToken = nil
        detailLoadingTask?.cancel()
        detailLoadingTask = nil
        detailLoadingToken = nil
        cancelStartupPlayURLTask()
        cancelHLSRenditionPrebuildTask()
        cancelSeekWarmups(clearRecent: true)
        cancelPlayVariantSwitchTask()
        cancelRelatedPreloadTask()
        cancelRelatedArtworkPrefetchTask()
        cancelRelatedRefreshTask()
        cancelUploaderInteractionTask()
        uploaderInteractionLoadIdentity = nil
        finishPlaybackStartupWaiters(with: nil)
    }

    nonisolated static func cancelMediaWarmupsPreservingCache() {
        Task(priority: .utility) {
            await VideoPreloadCenter.shared.cancelMediaWarmups(clearCache: false)
        }
    }
}

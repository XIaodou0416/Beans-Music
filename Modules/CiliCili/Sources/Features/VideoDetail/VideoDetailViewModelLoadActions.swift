import Foundation

extension VideoDetailViewModel {
    func load() async {
        guard !isPlaybackInvalidatedForNavigation else { return }
        discardTerminatedStablePlayerIfNeeded()
        if state == .loading {
            return
        }
        if state == .loaded {
            await resumeLoadedDetailIfNeeded()
            return
        }
        beginDetailLoadTracking()

        if activateCurrentDetailForFastStart(source: "seed") {
            await startPlaybackAfterFastStartActivation()
            return
        }

        scheduleDetailAndPlaybackPreloadIfMissingCID(priority: .userInitiated)

        if playbackOptions.usesStartupCaches,
           await applyCachedDetailForFastStartIfAvailable() {
            await startPlaybackAfterFastStartActivation()
            return
        }

        await loadFullDetailAndMetadata(priority: .userInitiated)
    }
}

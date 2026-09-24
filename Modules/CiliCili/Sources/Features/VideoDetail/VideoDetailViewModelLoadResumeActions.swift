import Foundation

extension VideoDetailViewModel {
    func resumeLoadedDetailIfNeeded() async {
        guard !isPlaybackInvalidatedForNavigation else { return }
        beginCloudHistoryResumeFetchIfNeeded()
        scheduleDanmakuLoadIfNeeded()
        scheduleRelatedLoadIfNeeded()
        scheduleUploaderAndInteractionLoadIfNeeded()
        guard stablePlayerViewModel == nil else { return }

        if selectedPlayVariant?.isPlayable == true {
            restoreStablePlayerForLoadedDetail()
        } else {
            await loadPlayURLIfNeeded()
        }
    }

    func restoreStablePlayerForLoadedDetail() {
        let resumeTime = pendingNavigationResumeTime
        let shouldResumeOverride: Bool? = isAwaitingRelatedVideoReturnPlayback
            ? false
            : (shouldResumePlaybackAfterCancelledNavigation
                ? true
                : (hasPendingNavigationInterruption ? false : nil))
        guard !isPlaybackInvalidatedForNavigation else { return }
        updateStablePlayerViewModelIfNeeded(
            resumeTimeOverride: resumeTime,
            shouldResumePlayback: shouldResumeOverride
        )
        pendingNavigationResumeTime = nil
        shouldResumePlaybackAfterCancelledNavigation = false
        hasPendingNavigationInterruption = false
    }

    func schedulePlaybackStartupSideLoads() {
        beginCloudHistoryResumeFetchIfNeeded()
        schedulePlayURLLoadIfNeeded()
        scheduleUploaderAndInteractionLoadIfNeeded()
        scheduleFullDetailLoadIfNeeded(
            priority: .utility,
            waitsForFirstFrame: libraryStore.videoDetailAutoplayEnabled
        )
    }

    func startPlaybackAfterFastStartActivation() async {
        beginCloudHistoryResumeFetchIfNeeded()
        await prioritizeCurrentPlaybackForStartup()
        scheduleUploaderAndInteractionLoadIfNeeded()
        scheduleFullDetailLoadIfNeeded(
            priority: .utility,
            waitsForFirstFrame: libraryStore.videoDetailAutoplayEnabled
        )
        await loadPlayURLIfNeeded()
    }
}

import Foundation

extension VideoDetailViewModel {
    func resetPlaybackStateForSelectedPage() {
        resetDanmakuLoad(clearItems: true)
        currentPlayURLData = nil
        clearVideoListenAudioVariants()
        playVariants = []
        selectedPlayVariant = nil
        playURLElapsedMilliseconds = nil
        lastPlayURLSource = nil
        clearManualPlayVariantSelection()
        failedPlayVariantIDs.removeAll()
        playbackRecoveryAttemptCount = 0
        playbackRecoveryCoordinator.reset()
        lastBufferingCDNRefreshCount = 0
        cancelPlaybackRecoveryReloadTask()
        cancelBufferingCDNRefreshTask()
        finishPlaybackStartupWaiters(with: nil)
        stablePlayerViewModel?.stop()
        stablePlayerViewModel = nil
        clearPlaybackTransitionPlayer()
        stablePlayerIdentity = nil
        stablePlayerErrorCancellable = nil
        stablePlayerFirstFrameCancellable = nil
        syncPlayerIdentityRenderStore()
        playbackFallbackMessage = nil
        cancelPlayVariantSwitchTask()
        cancelCommentsLoadingTask()
        clearCommentThreadLoads()
        cancelStartupPlayURLTask()
        cancelHLSRenditionPrebuildTask()
        cancelSeekWarmups(clearRecent: true)
        cancelSponsorBlockTask()
        sponsorBlockSegments = []
        sponsorBlockIdentity = nil
        playURLState = .idle
    }

    func clearManualPlayVariantSelection() {
        didSelectPlayVariantManually = false
        manuallySelectedPlayVariantQuality = nil
    }
}

import Foundation

extension VideoDetailViewModel {
    func schedulePlayVariantSwitchTask(
        to variant: PlayVariant,
        cid: Int?,
        token: UUID,
        initialResumeTime: TimeInterval,
        initialShouldResumePlayback: Bool,
        initialPlaybackRate: BiliPlaybackRate
    ) {
        let bvid = detail.bvid
        let page = selectedPageNumber
        let variantID = variant.id
        playVariantSwitchTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            defer {
                self.clearPlayVariantSwitchIfCurrent(token)
            }
            let didWarmVariant: Bool
            if self.playbackContentMode == .audioOnly {
                didWarmVariant = true
            } else if let cid {
                didWarmVariant = await VideoPreloadCenter.shared.warmVariantAndWaitCached(
                    variant,
                    bvid: bvid,
                    cid: cid,
                    page: page,
                    timeout: Self.qualitySwitchWarmupTimeout
                )
            } else {
                didWarmVariant = await VideoPreloadCenter.shared.warmVariantAndWait(
                    variant,
                    bvid: bvid,
                    timeout: Self.qualitySwitchWarmupTimeout
                )
            }
            if !didWarmVariant {
                PlayerMetricsLog.record(
                    .qualitySupplement,
                    metricsID: bvid,
                    title: self.detail.title,
                    message: "manualQuality warmTimeoutContinue q\(variant.quality)"
                )
            }
            guard !Task.isCancelled,
                  !self.isPlaybackInvalidatedForNavigation,
                  self.isCurrentPlaybackContext(bvid: bvid, cid: cid, page: page),
                  self.playVariantSwitchToken == token,
                  self.pendingPlayVariantID == variantID
            else { return }

            let resumeTime = max(initialResumeTime, self.currentPlaybackResumeTime())
            let shouldResumePlayback = initialShouldResumePlayback || self.currentPlaybackIntent()
            let playbackRate = self.stablePlayerViewModel?.playbackRate ?? initialPlaybackRate
            self.selectedPlayVariant = variant
            self.playbackFallbackMessage = nil
            self.updateStablePlayerViewModelIfNeeded(
                resumeTimeOverride: resumeTime,
                shouldResumePlayback: shouldResumePlayback,
                playbackRateOverride: playbackRate,
                preservesPreviousPlayerUntilFirstFrame: true,
                usesSeamlessPlaybackHandoff: self.playbackContentMode == .audioOnly
                    && shouldResumePlayback
            )
        }
    }
}

import Foundation

extension VideoDetailViewModel {
    func warmSelectedVariantAfterFirstFrameIfNeeded(_ variant: PlayVariant?, cid: Int?, page: Int?) {
        guard !isPlaybackInvalidatedForNavigation,
              let cid,
              let variant,
              !variant.isProgressiveFastStart
        else { return }
        let canWarmAfterFirstFrame = playbackAdaptationProfile.shouldWarmSupplementalVariants
            || libraryStore.effectivePreferredVideoQuality != nil
        guard canWarmAfterFirstFrame else { return }
        let bvid = detail.bvid
        let variantID = variant.id
        trackBackgroundTask(
            Task(priority: .utility) { [weak self, variant] in
                guard let self else { return }
                let didPresentPlayback = await self.waitForFirstFrameOrFailure()
                guard didPresentPlayback,
                      !Task.isCancelled,
                      !self.isPlaybackInvalidatedForNavigation,
                      self.detail.bvid == bvid,
                      self.selectedCID == cid,
                      self.selectedPlayVariant?.id == variantID
                else { return }
                await VideoPreloadCenter.shared.warmVariant(
                    variant,
                    bvid: bvid,
                    cid: cid,
                    page: page,
                    delay: 0.25
                )
            }
        )
    }

}

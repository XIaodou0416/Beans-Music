import Foundation

extension VideoDetailViewModel {
    func rankPlaybackCDNCandidatesAfterFirstFrameIfNeeded(_ variant: PlayVariant?, cid: Int?) {
        guard !isPlaybackInvalidatedForNavigation,
              libraryStore.isPlaybackAutoOptimizationEnabled,
              libraryStore.playbackCDNPreference == .automatic,
              !PlaybackEnvironment.current.shouldPreferConservativePlayback,
              let cid,
              let variant,
              variant.isPlayable
        else { return }
        let hasVideoCandidates = (variant.videoStream?.backupPlayURLs.isEmpty == false)
        let hasAudioCandidates = (variant.audioStream?.backupPlayURLs.isEmpty == false)
        guard hasVideoCandidates || hasAudioCandidates else { return }

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

                try? await Task.sleep(nanoseconds: 1_200_000_000)
                guard !Task.isCancelled,
                      !self.isPlaybackInvalidatedForNavigation,
                      self.detail.bvid == bvid,
                      self.selectedCID == cid,
                      self.selectedPlayVariant?.id == variantID
                else { return }

                let cdnPreference = self.libraryStore.effectivePlaybackCDNPreference
                let headers = BiliHLSManifestBuilder.httpHeaders(
                    referer: "https://www.bilibili.com/video/\(bvid)"
                )
                await PlayerMetricsLog.withSignpostedInterval(
                    "VideoDetailCDNRanking",
                    message: "bvid=\(bvid) q=\(variant.quality)"
                ) {
                    await PlaybackStartupURLProbeService.rankVariantCandidates(
                        for: variant,
                        cdnPreference: cdnPreference,
                        headers: headers
                    )
                }
            }
        )
    }
}

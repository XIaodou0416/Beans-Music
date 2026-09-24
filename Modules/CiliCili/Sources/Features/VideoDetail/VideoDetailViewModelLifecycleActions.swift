import Combine
import Foundation

extension VideoDetailViewModel {
    func configureLifecycleBindings() {
        lastDanmakuAdaptationProfile = playbackAdaptationProfile
        filterCancellable = libraryStore.$blocksGoodsComments
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                guard self?.isPlaybackInvalidatedForNavigation != true else { return }
                self?.refilterLoadedComments()
            }
        sponsorBlockCancellable = libraryStore.$sponsorBlockEnabled
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                guard self?.isPlaybackInvalidatedForNavigation != true else { return }
                self?.stablePlayerViewModel?.setSponsorBlockEnabled(isEnabled)
                if isEnabled {
                    self?.scheduleSponsorBlockSegmentsAfterFirstFrame()
                } else {
                    self?.resetSponsorBlockSegments()
                }
            }
        playbackAutoOptimizationCancellable = libraryStore.$playbackAutoOptimizationMode
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                guard self?.isPlaybackInvalidatedForNavigation != true else { return }
                self?.refreshDanmakuRenderStoreForPlaybackPerformance(force: true)
            }
        playbackPerformanceCancellable = PlayerPerformanceStore.shared.updates
            .sink { [weak self] _ in
                guard let self,
                    !self.isPlaybackInvalidatedForNavigation
                else { return }
                self.refreshDanmakuRenderStoreForPlaybackPerformance(force: false)
            }
    }

    private func refreshDanmakuRenderStoreForPlaybackPerformance(force: Bool) {
        let nextProfile = playbackAdaptationProfile
        defer { lastDanmakuAdaptationProfile = nextProfile }
        guard force || lastDanmakuAdaptationProfile != nextProfile else { return }
        scheduleRenderStoreSync(.danmaku)
    }

}

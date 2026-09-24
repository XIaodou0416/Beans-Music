import Foundation

extension VideoDetailViewModel {
    func scheduleDetailAndPlaybackPreloadIfMissingCID(priority: TaskPriority = .utility) {
        guard playbackOptions.usesStartupCaches,
              !isPlaybackInvalidatedForNavigation,
              selectedCID == nil,
              !detail.bvid.isEmpty
        else { return }
        let seedDetail = detail
        let preferredQuality = adaptiveStartupPreferredQuality
        let targetPreferredQuality = targetPlaybackPreferredQuality
        let cdnPreference = libraryStore.effectivePlaybackCDNPreference
        let adaptationProfile = playbackAdaptationProfile
        trackBackgroundTask(
            Task(priority: priority) { [api] in
                guard !Task.isCancelled else { return }
                await VideoPreloadCenter.shared.prioritizePlayback(for: seedDetail)
                guard !Task.isCancelled else { return }
                await VideoPreloadCenter.shared.preloadDetailAndPlayback(
                    seedDetail,
                    api: api,
                    preferredQuality: preferredQuality,
                    targetPreferredQuality: targetPreferredQuality,
                    cdnPreference: cdnPreference,
                    warmsMedia: true,
                    mediaWarmupDelay: 0.15,
                    priority: priority,
                    playbackAdaptationProfile: adaptationProfile
                )
            }
        )
    }
}

import Foundation

extension VideoDetailViewModel {
    func scheduleRelatedLoadIfNeeded() {
        guard !detail.isPGCEpisode else { return }
        scheduleRelatedLoadAfterPlaybackStartIfNeeded()
    }

    func scheduleRelatedLoadAfterPlaybackStartIfNeeded() {
        guard !detail.isPGCEpisode else { return }
        guard related.isEmpty, !relatedState.isLoading, relatedLoadingTask == nil else { return }
        let loadGeneration = advanceRelatedLoadingGeneration()
        relatedLoadingTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            defer {
                self.clearRelatedLoadingTaskIfCurrent(generation: loadGeneration)
            }
            if self.libraryStore.videoDetailAutoplayEnabled {
                guard let release = await self.waitForPlaybackStartupRelease(acceptsFailure: true),
                      !Task.isCancelled,
                      !self.isPlaybackInvalidatedForNavigation,
                      self.relatedLoadingGeneration == loadGeneration
                else { return }
                if case .firstFrame = release, self.playbackAdaptationProfile.shouldThrottleBackgroundPreload {
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    guard !Task.isCancelled,
                          !self.isPlaybackInvalidatedForNavigation,
                          self.relatedLoadingGeneration == loadGeneration
                    else { return }
                }
            }
            guard !Task.isCancelled,
                  !self.isPlaybackInvalidatedForNavigation,
                  self.relatedLoadingGeneration == loadGeneration
            else { return }
            await self.loadRelated()
            guard !Task.isCancelled,
                  !self.isPlaybackInvalidatedForNavigation,
                  self.relatedLoadingGeneration == loadGeneration
            else { return }
            self.scheduleDanmakuLoadIfNeeded()
        }
    }
}

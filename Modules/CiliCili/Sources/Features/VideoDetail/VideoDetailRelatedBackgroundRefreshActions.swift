import Foundation

extension VideoDetailViewModel {
    func refreshRelatedInBackgroundIfNeeded() async {
        guard relatedRefreshTask == nil,
              !isPlaybackInvalidatedForNavigation,
              !PlaybackEnvironment.current.shouldPreferConservativePlayback
        else { return }
        let bvid = detail.bvid
        let refreshGeneration = advanceRelatedRefreshGeneration()
        relatedRefreshTask = Task(priority: .background) { [weak self] in
            guard let self else { return }
            defer {
                self.clearRelatedRefreshTaskIfCurrent(generation: refreshGeneration)
            }
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled,
                  !self.isPlaybackInvalidatedForNavigation,
                  self.relatedRefreshGeneration == refreshGeneration
            else { return }
            do {
                let videos = try await VideoPreloadCenter.shared.refreshRelatedVideos(
                    for: bvid,
                    api: self.api,
                    priority: .background,
                    limit: Self.relatedRecommendationsLimit
                )
                guard !Task.isCancelled,
                      !self.isPlaybackInvalidatedForNavigation,
                      self.detail.bvid == bvid,
                      self.relatedRefreshGeneration == refreshGeneration
                else { return }
                if !videos.isEmpty {
                    self.applyLoadedRelatedVideos(videos)
                }
            } catch {
                guard !Task.isCancelled,
                      !self.isPlaybackInvalidatedForNavigation,
                      self.detail.bvid == bvid,
                      self.relatedRefreshGeneration == refreshGeneration
                else { return }
                if self.related.isEmpty {
                    _ = await self.applyRelatedFallbackIfAvailable(reason: error.localizedDescription, bvid: bvid)
                }
            }
        }
    }
}

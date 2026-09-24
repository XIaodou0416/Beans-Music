import Foundation

extension VideoDetailViewModel {
    func applyLoadedRelatedVideos(_ videos: [VideoItem]) {
        let filtered = Array(VideoRecommendationFilter.filtered(
            videos.filter { $0.bvid != detail.bvid },
            configuration: libraryStore.videoRecommendationFilterConfiguration,
            context: .related
        )
            .prefix(Self.relatedRecommendationsLimit))
        guard !filtered.isEmpty || related.isEmpty else { return }
        related = filtered
        lastRelatedLoadTimedOut = false
        relatedState = filtered.isEmpty ? .failed("暂无相关推荐") : .loaded
        if !filtered.isEmpty {
            prefetchRelatedArtwork(filtered)
            scheduleRelatedPlaybackPreloadIfAppropriate(for: filtered)
        }
    }

    @discardableResult
    func applyRelatedFallbackIfAvailable(reason: String, bvid: String) async -> Bool {
        let fallback = await VideoPreloadCenter.shared.fallbackRelatedVideos(
            excluding: bvid,
            limit: Self.relatedRecommendationsLimit
        )
        guard !Task.isCancelled,
              !isPlaybackInvalidatedForNavigation,
              detail.bvid == bvid
        else { return false }
        let filteredFallback = Array(VideoRecommendationFilter.filtered(
            fallback,
            configuration: libraryStore.videoRecommendationFilterConfiguration,
            context: .related
        )
            .prefix(Self.relatedRecommendationsLimit))
        guard !filteredFallback.isEmpty else { return false }
        related = filteredFallback
        lastRelatedLoadTimedOut = reason.localizedCaseInsensitiveContains("超时")
        relatedState = .loaded
        prefetchRelatedArtwork(filteredFallback)
        scheduleRelatedPlaybackPreloadIfAppropriate(for: filteredFallback)
        return true
    }

    func prefetchRelatedArtwork(_ videos: [VideoItem]) {
        let bvid = detail.bvid
        let usesCompactArtwork = shouldUseCompactRelatedArtwork
        let prefetchLimit = usesCompactArtwork ? 2 : 3
        let width = usesCompactArtwork ? 300 : 360
        let height = Int((Double(width) * 9.0 / 16.0).rounded())
        let targetPixelSize = usesCompactArtwork ? 300 : 360
        let sources = videos.prefix(prefetchLimit).compactMap { video -> RemoteImageSource? in
            guard let pic = video.pic?.normalizedBiliURL(),
                  let url = URL(string: pic.biliCoverThumbnailURL(width: width, height: height))
            else { return nil }
            return RemoteImageSource(url: url, fallbackURL: URL(string: pic))
        }
        guard !sources.isEmpty else { return }
        cancelRelatedArtworkPrefetchTask(advancesGeneration: false)
        let prefetchGeneration = advanceRelatedArtworkPrefetchGeneration()
        relatedArtworkPrefetchTask = Task(priority: .background) { [weak self] in
            defer {
                Task { @MainActor [weak self] in
                    self?.clearRelatedArtworkPrefetchTaskIfCurrent(generation: prefetchGeneration)
                }
            }
            try? await Task.sleep(nanoseconds: 550_000_000)
            guard let self,
                  !Task.isCancelled,
                  !self.isPlaybackInvalidatedForNavigation,
                  self.detail.bvid == bvid,
                  self.relatedArtworkPrefetchGeneration == prefetchGeneration
            else { return }
            await RemoteImageCache.shared.prefetch(
                sources,
                targetPixelSize: targetPixelSize,
                maximumConcurrentLoads: usesCompactArtwork ? 1 : 2
            )
        }
    }
}

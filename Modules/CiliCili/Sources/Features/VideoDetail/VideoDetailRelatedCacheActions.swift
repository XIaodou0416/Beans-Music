import Foundation

extension VideoDetailViewModel {
    @discardableResult
    func applyCachedRelatedVideosIfAvailable(bvid: String) async -> Bool {
        guard let cached = await VideoPreloadCenter.shared.cachedRelatedVideos(
            for: bvid,
            limit: Self.relatedRecommendationsLimit
        ) else {
            return false
        }
        guard !Task.isCancelled,
              !isPlaybackInvalidatedForNavigation,
              detail.bvid == bvid
        else { return false }

        related = cached
        relatedState = .loaded
        relatedElapsedMilliseconds = 0
        lastRelatedLoadTimedOut = false
        scheduleRelatedPlaybackPreloadIfAppropriate(for: cached)

        guard cached.count < Self.minimumExpandedRelatedCount else {
            await refreshRelatedInBackgroundIfNeeded()
            return true
        }

        relatedState = .loading
        return false
    }
}

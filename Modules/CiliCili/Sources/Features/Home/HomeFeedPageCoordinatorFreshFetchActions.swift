import Foundation

extension HomeFeedPageCoordinator {
    func fetchFreshPage(
        for mode: HomeFeedMode,
        replacing previousIDs: [String],
        minimumFreshCount: Int? = nil,
        maximumFreshCount: Int? = nil
    ) async throws -> [VideoItem] {
        switch mode {
        case .popular:
            return try await api.fetchPopularVideos(page: popularPage)
        case .recommend:
            if usesNativeAppRecommendSource(for: mode) {
                return filterFeedRecommendations(try await api.fetchRecommendFeed(
                    freshIndex: freshIndex,
                    limit: maximumFreshCount
                ))
            }
            if usesGuestRecommendDiversity(for: mode) {
                return filterFeedRecommendations(try await fetchGuestRecommendPage(
                    excluding: Set(previousIDs),
                    minimumFreshCount: minimumFreshCount ?? (previousIDs.isEmpty ? 14 : 10),
                    maximumFreshCount: maximumFreshCount,
                    maximumAttempts: 5
                ))
            }
            if let minimumFreshCount {
                return filterFeedRecommendations(try await fetchUniqueRecommendRefreshPage(
                    excluding: Set(previousIDs),
                    minimumFreshCount: minimumFreshCount,
                    maximumFreshCount: maximumFreshCount,
                    maximumAttempts: 5
                ))
            }
            var lastPage = [VideoItem]()
            for attempt in 0..<5 {
                if attempt > 0 {
                    freshIndex += 1
                }
                let page = try await api.fetchRecommendFeed(
                    freshIndex: freshIndex,
                    limit: maximumFreshCount
                )
                let filteredPage = filterFeedRecommendations(page)
                lastPage = filteredPage
                if HomeFeedVisibleChangeDetector.hasVisibleChange(in: filteredPage, comparedTo: previousIDs) {
                    return filteredPage
                }
            }
            return lastPage
        }
    }
}

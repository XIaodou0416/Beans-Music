import Foundation

extension HomeFeedPageCoordinator {
    func fetchGuestRecommendPage(
        excluding excludedIDs: Set<String>,
        minimumFreshCount: Int,
        maximumFreshCount: Int? = nil,
        maximumAttempts: Int
    ) async throws -> [VideoItem] {
        var accumulator = HomeGuestRecommendPageAccumulator(
            excludedIDs: excludedIDs,
            recentExposureIDs: HomeGuestRecommendState.recentExposureIDs(),
            minimumFreshCount: minimumFreshCount,
            maximumFreshCount: maximumFreshCount
        )
        var lastRawPage = [VideoItem]()

        for attempt in 0..<maximumAttempts {
            if attempt > 0 {
                freshIndex += 1
            }
            let page = try await api.fetchRecommendFeed(
                freshIndex: freshIndex,
                limit: maximumFreshCount
            )
            lastRawPage = page
            accumulator.append(page)

            if accumulator.hasEnoughFreshVideos {
                break
            }
        }

        HomeGuestRecommendState.storeNextFreshIndex(after: freshIndex)
        return accumulator.resolvedPage(lastRawPage: lastRawPage)
    }
}

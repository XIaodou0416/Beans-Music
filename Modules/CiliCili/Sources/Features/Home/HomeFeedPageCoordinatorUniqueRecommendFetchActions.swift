import Foundation

extension HomeFeedPageCoordinator {
    func fetchUniqueRecommendRefreshPage(
        excluding excludedIDs: Set<String>,
        minimumFreshCount: Int,
        maximumFreshCount: Int? = nil,
        maximumAttempts: Int
    ) async throws -> [VideoItem] {
        var accumulator = HomeUniqueRecommendRefreshAccumulator(
            excludedIDs: excludedIDs,
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

        return accumulator.resolvedPage(lastRawPage: lastRawPage)
    }
}

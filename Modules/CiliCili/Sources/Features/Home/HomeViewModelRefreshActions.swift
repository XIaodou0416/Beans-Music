import Foundation

extension HomeViewModel {
    func refresh(
        resetCursor shouldResetCursor: Bool = false,
        preservingExistingRecommendations shouldPreserveExistingRecommendations: Bool = false
    ) async {
        let usesNativeAppRecommend = pageCoordinator.usesNativeAppRecommendSource(for: mode)
        let preservesExistingRecommendations = shouldPreserveExistingRecommendations && mode == .recommend
        let previousVideos = videos
        let previousLastSeenMarkerIndex = lastSeenMarkerIndex
        let previousIDs = previousVideos.map(\.id)
        requestRevision += 1
        cancelRecommendMetadataHydrationTasks()
        let revision = requestRevision
        isRefreshing = true
        state = .loading
        defer {
            if revision == requestRevision {
                isRefreshing = false
            }
        }
        if shouldResetCursor || usesNativeAppRecommend || shouldPreserveExistingRecommendations {
            pageCoordinator.resetCursor(for: mode)
        } else {
            pageCoordinator.advanceRefreshCursor(for: mode)
        }
        do {
            let userRefreshRecommendationLimit = preservesExistingRecommendations ? Self.userRefreshRecommendationCount : nil
            let refreshedVideos = try await pageCoordinator.fetchFreshPage(
                for: mode,
                replacing: previousIDs,
                minimumFreshCount: userRefreshRecommendationLimit,
                maximumFreshCount: userRefreshRecommendationLimit
            )
            guard revision == requestRevision else { return }
            guard !refreshedVideos.isEmpty else {
                if previousVideos.isEmpty {
                    restoreCachedVideosIfAvailable()
                }
                state = videos.isEmpty ? .failed("暂无内容") : .loaded
                return
            }
            replaceVideos(
                refreshedVideos,
                previousVideos: previousVideos,
                preservingExistingRecommendations: preservesExistingRecommendations
            )
            snapshotCoordinator.save(
                videos: videos,
                mode: mode,
                lastSeenMarkerIndex: lastSeenMarkerIndex
            )
            state = .loaded
        } catch {
            guard revision == requestRevision else { return }
            if preservesExistingRecommendations, !previousVideos.isEmpty {
                updateFeed(previousVideos)
                updateLastSeenMarkerIndex(previousLastSeenMarkerIndex)
                state = .loaded
                return
            }
            if videos.isEmpty {
                restoreCachedVideosIfAvailable()
            }
            state = videos.isEmpty ? .failed(error.localizedDescription) : .loaded
        }
    }
}

import Foundation

extension VideoDetailViewModel {
    func fetchRelatedWithTimeout(
        bvid: String,
        timeout: UInt64,
        forceRefresh: Bool = false
    ) async throws -> [VideoItem] {
        try await withThrowingTaskGroup(of: [VideoItem].self) { group -> [VideoItem] in
            group.addTask(priority: forceRefresh ? .utility : .background) { [api] in
                if forceRefresh {
                    return try await VideoPreloadCenter.shared.refreshRelatedVideos(
                        for: bvid,
                        api: api,
                        priority: .utility,
                        limit: Self.relatedRecommendationsLimit
                    )
                }
                return try await VideoPreloadCenter.shared.relatedVideos(
                    for: bvid,
                    api: api,
                    priority: .background,
                    limit: Self.relatedRecommendationsLimit
                )
            }
            group.addTask(priority: .background) { () -> [VideoItem] in
                try await Task.sleep(nanoseconds: timeout)
                throw VideoDetailLoadTimeoutError.related
            }
            guard let result = try await group.next() else { return [] }
            group.cancelAll()
            return result
        }
    }

    var adaptiveRelatedLoadTimeoutNanoseconds: UInt64 {
        let environment = PlaybackEnvironment.current
        if environment.isLowPowerModeEnabled || environment.isThermallyConstrained {
            return 2_200_000_000
        }
        switch environment.networkClass {
        case .wifi, .unknown:
            return min(relatedLoadTimeoutNanoseconds, 3_200_000_000)
        case .cellular, .constrained:
            return 2_400_000_000
        }
    }
}

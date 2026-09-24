import Foundation

nonisolated struct HomeGuestRecommendPageAccumulator {
    let excludedIDs: Set<String>
    let minimumFreshCount: Int
    let maximumFreshCount: Int?
    var exposureIDs: Set<String>
    var freshVideos = [VideoItem]()
    var freshIDs = Set<String>()
    var fallbackVideos = [VideoItem]()
    var fallbackIDs = Set<String>()

    init(
        excludedIDs: Set<String>,
        recentExposureIDs: Set<String>,
        minimumFreshCount: Int,
        maximumFreshCount: Int? = nil
    ) {
        self.excludedIDs = excludedIDs
        self.minimumFreshCount = minimumFreshCount
        self.maximumFreshCount = maximumFreshCount
        self.exposureIDs = recentExposureIDs.union(excludedIDs)
    }

    var hasEnoughFreshVideos: Bool {
        freshVideos.count >= minimumFreshCount
    }
}

nonisolated struct HomeUniqueRecommendRefreshAccumulator {
    let excludedIDs: Set<String>
    let minimumFreshCount: Int
    let maximumFreshCount: Int?
    var freshVideos = [VideoItem]()
    var freshIDs = Set<String>()

    init(excludedIDs: Set<String>, minimumFreshCount: Int, maximumFreshCount: Int? = nil) {
        self.excludedIDs = excludedIDs
        self.minimumFreshCount = minimumFreshCount
        self.maximumFreshCount = maximumFreshCount
    }

    var hasEnoughFreshVideos: Bool {
        freshVideos.count >= minimumFreshCount
    }
}

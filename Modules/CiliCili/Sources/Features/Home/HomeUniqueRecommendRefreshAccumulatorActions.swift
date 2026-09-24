import Foundation

extension HomeUniqueRecommendRefreshAccumulator {
    mutating func append(_ page: [VideoItem]) {
        for video in page where !video.id.isEmpty {
            guard !excludedIDs.contains(video.id),
                  freshIDs.insert(video.id).inserted
            else { continue }
            freshVideos.append(video)
            if hasEnoughFreshVideos {
                break
            }
        }
    }

    func resolvedPage(lastRawPage: [VideoItem]) -> [VideoItem] {
        let limit = maximumFreshCount ?? minimumFreshCount
        guard !freshVideos.isEmpty else {
            return Array(lastRawPage.prefix(limit))
        }
        return Array(freshVideos.prefix(limit))
    }
}

import Foundation

extension HomeGuestRecommendPageAccumulator {
    mutating func append(_ page: [VideoItem]) {
        for video in page where !video.id.isEmpty {
            appendFallbackIfNeeded(video)
            appendFreshIfNeeded(video)
        }
    }

    func resolvedPage(lastRawPage: [VideoItem]) -> [VideoItem] {
        guard !freshVideos.isEmpty else {
            return limited(fallbackVideos.isEmpty ? lastRawPage : fallbackVideos)
        }
        let targetCount = max(minimumFreshCount, min(20, fallbackVideos.count))
        let resolvedTargetCount = maximumFreshCount.map { min(targetCount, $0) } ?? targetCount
        guard freshVideos.count < resolvedTargetCount else {
            return limited(freshVideos)
        }

        var merged = freshVideos
        var mergedIDs = Set(freshVideos.map(\.id))
        for video in fallbackVideos where mergedIDs.insert(video.id).inserted {
            merged.append(video)
            if merged.count >= resolvedTargetCount {
                break
            }
        }
        return limited(merged)
    }

    mutating func appendFallbackIfNeeded(_ video: VideoItem) {
        guard !excludedIDs.contains(video.id),
              fallbackIDs.insert(video.id).inserted
        else { return }
        fallbackVideos.append(video)
    }

    mutating func appendFreshIfNeeded(_ video: VideoItem) {
        guard !exposureIDs.contains(video.id),
              freshIDs.insert(video.id).inserted
        else { return }
        freshVideos.append(video)
        exposureIDs.insert(video.id)
    }

    private func limited(_ videos: [VideoItem]) -> [VideoItem] {
        guard let maximumFreshCount, videos.count > maximumFreshCount else {
            return videos
        }
        return Array(videos.prefix(maximumFreshCount))
    }
}

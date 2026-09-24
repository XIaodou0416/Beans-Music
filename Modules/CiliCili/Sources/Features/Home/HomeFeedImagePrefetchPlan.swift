import Foundation

nonisolated struct HomeFeedImagePrefetchPlan {
    let coverSources: [RemoteImageSource]
    let coverTargetPixelSize: Int

    static func make(
        for videos: [VideoItem],
        profile: HomeFeedCoverPrefetchProfile,
        startIndex: Int = 0,
        limit: Int
    ) -> HomeFeedImagePrefetchPlan {
        var seenCovers = Set<String>()
        var coverSources = [RemoteImageSource]()
        let coverTargetPixelSize = profile.targetPixelSize
        let safeStartIndex = min(max(startIndex, 0), videos.count)

        for video in videos.dropFirst(safeStartIndex).prefix(limit) {
            if let source = video.pic?.normalizedBiliURL(),
               let coverSource = profile.source(for: source),
               seenCovers.insert(source).inserted {
                coverSources.append(coverSource)
            }
        }

        return HomeFeedImagePrefetchPlan(
            coverSources: coverSources,
            coverTargetPixelSize: coverTargetPixelSize
        )
    }
}

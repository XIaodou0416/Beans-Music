import Foundation

struct HomeFeedRefreshMergeResult {
    let videos: [VideoItem]
    let lastSeenMarkerIndex: Int?
}

enum HomeFeedMergePolicy {
    static func refreshedFeed(
        fresh: [VideoItem],
        previousVideos: [VideoItem],
        mode: HomeFeedMode,
        preservesExistingRecommendations: Bool,
        usesNativeReplacement: Bool = false
    ) -> HomeFeedRefreshMergeResult {
        if usesNativeReplacement && !preservesExistingRecommendations {
            return HomeFeedRefreshMergeResult(videos: fresh, lastSeenMarkerIndex: nil)
        }
        if preservesExistingRecommendations {
            return prependFreshFeed(fresh, to: previousVideos, mode: mode)
        }
        return HomeFeedRefreshMergeResult(
            videos: mergedRefreshVideos(fresh, previousVideos: previousVideos, mode: mode),
            lastSeenMarkerIndex: nil
        )
    }

    static func refreshedVideos(
        fresh: [VideoItem],
        previousVideos: [VideoItem],
        mode: HomeFeedMode,
        preservesExistingRecommendations: Bool,
        usesNativeReplacement: Bool = false
    ) -> [VideoItem] {
        refreshedFeed(
            fresh: fresh,
            previousVideos: previousVideos,
            mode: mode,
            preservesExistingRecommendations: preservesExistingRecommendations,
            usesNativeReplacement: usesNativeReplacement
        )
        .videos
    }

    static func uniqueAppendVideos(
        _ more: [VideoItem],
        to videos: [VideoItem]
    ) -> [VideoItem] {
        let existing = Set(videos.map(\.id))
        return more.filter { !existing.contains($0.id) }
    }

    private static func mergedRefreshVideos(
        _ fresh: [VideoItem],
        previousVideos: [VideoItem],
        mode: HomeFeedMode
    ) -> [VideoItem] {
        guard mode == .recommend, !fresh.isEmpty, !previousVideos.isEmpty else {
            return fresh
        }
        var seen = Set(fresh.map(\.id))
        let retainedTail = previousVideos
            .prefix(50)
            .filter { seen.insert($0.id).inserted }
        return fresh + retainedTail
    }

    private static func prependFreshFeed(
        _ fresh: [VideoItem],
        to previousVideos: [VideoItem],
        mode: HomeFeedMode
    ) -> HomeFeedRefreshMergeResult {
        guard mode == .recommend, !fresh.isEmpty, !previousVideos.isEmpty else {
            return HomeFeedRefreshMergeResult(
                videos: fresh.isEmpty ? previousVideos : fresh,
                lastSeenMarkerIndex: nil
            )
        }
        var seen = Set(fresh.map(\.id))
        let previousCandidates = previousVideos.count > 200
            ? previousVideos.prefix(50)
            : previousVideos.prefix(previousVideos.count)
        let retainedVideos = previousCandidates.filter { seen.insert($0.id).inserted }
        let videos = fresh + retainedVideos
        return HomeFeedRefreshMergeResult(
            videos: videos,
            lastSeenMarkerIndex: retainedVideos.isEmpty ? nil : fresh.count
        )
    }
}

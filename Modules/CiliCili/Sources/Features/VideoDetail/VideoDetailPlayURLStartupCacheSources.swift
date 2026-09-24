import Foundation

extension VideoDetailViewModel {
    func resolvePlayableCachedPlayURLForStartup(
        cid: Int,
        page: Int?,
        mode: VideoDetailPlayURLLoadMode,
        deferredFallback: inout VideoDetailPlayURLFallback?
    ) async -> VideoDetailPlayURLCacheResolution? {
        guard playbackOptions.usesStartupCaches,
              mode.allowsStartupCache,
              let cachedPlayableData = await VideoPreloadCenter.shared.cachedPlayablePlayURL(
                for: detail.bvid,
                cid: cid,
                page: page,
                preferredQuality: adaptiveStartupPreferredQuality
              )
        else { return nil }

        return await resolveStartupCachedPlayURLCandidate(
            cachedPlayableData,
            cid: cid,
            page: page,
            mode: mode,
            cacheKind: "PlayableCache",
            fallbackSource: "playableCacheFallbackAfterNetworkFailure",
            loadedSource: "playableCache",
            loadedSignpost: "bvid=\(detail.bvid) playable cache",
            deferredFallback: &deferredFallback
        )
    }
}

import Foundation

extension VideoDetailViewModel {
    func resolveStoredCachedPlayURLForStartup(
        cid: Int,
        page: Int?,
        mode: VideoDetailPlayURLLoadMode,
        deferredFallback: inout VideoDetailPlayURLFallback?
    ) async -> VideoDetailPlayURLCacheResolution? {
        guard playbackOptions.usesStartupCaches,
              mode.allowsStartupCache,
              let cachedData = await VideoPreloadCenter.shared.cachedOrPendingPlayURL(
                for: detail.bvid,
                cid: cid,
                page: page,
                waitsForPending: false,
                preferredQuality: adaptiveStartupPreferredQuality
              )
        else { return nil }

        return await resolveStartupCachedPlayURLCandidate(
            cachedData,
            cid: cid,
            page: page,
            mode: mode,
            cacheKind: "Cache",
            fallbackSource: "cacheFallbackAfterNetworkFailure",
            loadedSource: "cache",
            loadedSignpost: "bvid=\(detail.bvid) cached",
            deferredFallback: &deferredFallback
        )
    }
}

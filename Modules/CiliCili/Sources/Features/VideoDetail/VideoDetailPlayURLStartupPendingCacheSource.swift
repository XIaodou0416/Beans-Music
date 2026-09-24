import Foundation

extension VideoDetailViewModel {
    func resolvePendingCachedPlayURLForStartup(
        cid: Int,
        page: Int?,
        mode: VideoDetailPlayURLLoadMode,
        deferredFallback: inout VideoDetailPlayURLFallback?
    ) async -> VideoDetailPlayURLCacheResolution? {
        guard playbackOptions.usesStartupCaches,
              mode.allowsStartupCache,
              let pendingData = await VideoPreloadCenter.shared.cachedOrPendingPlayURL(
                for: detail.bvid,
                cid: cid,
                page: page,
                waitsForPending: true,
                preferredQuality: adaptiveStartupPreferredQuality,
                maximumPendingWait: PlaybackEnvironment.current.preferredPlayURLStartupGrace
              )
        else { return nil }

        return await resolveStartupCachedPlayURLCandidate(
            pendingData,
            cid: cid,
            page: page,
            mode: mode,
            cacheKind: "PendingCache",
            fallbackSource: "pendingCacheFallbackAfterNetworkFailure",
            loadedSource: "pendingCache",
            loadedSignpost: "bvid=\(detail.bvid) pending cache",
            deferredFallback: &deferredFallback
        )
    }
}

import Foundation

extension VideoDetailViewModel {
    func resolveCachedPlayURLForStartup(
        cid: Int,
        page: Int?,
        mode: VideoDetailPlayURLLoadMode
    ) async -> VideoDetailPlayURLCacheResolution {
        var deferredPlayableFallback: VideoDetailPlayURLFallback?

        if let resolution = await resolvePendingCachedPlayURLForStartup(
            cid: cid,
            page: page,
            mode: mode,
            deferredFallback: &deferredPlayableFallback
        ) {
            return resolution
        }

        if let resolution = await resolvePlayableCachedPlayURLForStartup(
            cid: cid,
            page: page,
            mode: mode,
            deferredFallback: &deferredPlayableFallback
        ) {
            return resolution
        }

        if let resolution = await resolveStoredCachedPlayURLForStartup(
            cid: cid,
            page: page,
            mode: mode,
            deferredFallback: &deferredPlayableFallback
        ) {
            return resolution
        }

        return .needsNetwork(deferredFallback: deferredPlayableFallback)
    }
}

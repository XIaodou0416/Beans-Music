import Foundation

extension VideoDetailViewModel {
    func applyStalePlayablePlayURLFallbackIfAvailable(
        error: Error,
        cid: Int,
        page: Int?
    ) async -> String? {
        guard let staleFallback = await VideoPreloadCenter.shared.cachedPlayablePlayURL(
            for: detail.bvid,
            cid: cid,
            page: page,
            preferredQuality: nil
        ), isPlayablePlayURLData(staleFallback) else {
            return nil
        }

        return await applyPlayableFallbackPlayURLData(
            staleFallback,
            error: error,
            cid: cid,
            page: page,
            source: "stalePlayableCacheAfterNetworkFailure",
            note: "networkFailureStaleCache",
            playbackFallbackMessage: "播放地址接口临时失败，已使用上次可播放线路",
            signpostMessage: "bvid=\(detail.bvid) stale playable cache after failure"
        )
    }
}

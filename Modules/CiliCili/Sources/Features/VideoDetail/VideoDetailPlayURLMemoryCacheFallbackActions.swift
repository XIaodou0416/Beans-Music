import Foundation

extension VideoDetailViewModel {
    func applyMemoryPlayablePlayURLFallbackIfAvailable(
        error: Error,
        cid: Int,
        page: Int?
    ) async -> String? {
        guard let memoryFallback = await api.cachedPlayablePlayURLFallback(bvid: detail.bvid, cid: cid),
              isPlayablePlayURLData(memoryFallback) else {
            return nil
        }

        return await applyPlayableFallbackPlayURLData(
            memoryFallback,
            error: error,
            cid: cid,
            page: page,
            source: "memoryPlayableCacheAfterNetworkFailure",
            note: "networkFailureMemoryCache",
            playbackFallbackMessage: "播放地址接口临时失败，已使用内存可播放线路",
            signpostMessage: "bvid=\(detail.bvid) memory playable cache after failure"
        )
    }
}

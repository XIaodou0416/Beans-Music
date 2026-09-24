import Foundation

extension VideoDetailViewModel {
    func applyDeferredPlayURLFallbackIfAvailable(
        _ fallback: VideoDetailPlayURLFallback?,
        error: Error,
        cid: Int,
        page: Int?
    ) async -> String? {
        guard let fallback else { return nil }
        return await applyPlayableFallbackPlayURLData(
            fallback.data,
            error: error,
            cid: cid,
            page: page,
            source: fallback.source,
            note: "networkFailureDeferredCache",
            signpostMessage: "bvid=\(detail.bvid) deferred cache after failure"
        )
    }
}

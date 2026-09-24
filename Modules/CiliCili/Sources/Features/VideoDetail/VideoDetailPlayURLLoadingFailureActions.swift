import Foundation

extension VideoDetailViewModel {
    func handlePlayURLLoadingError(
        _ error: Error,
        cid: Int,
        page: Int?,
        mode: VideoDetailPlayURLLoadMode,
        deferredPlayableFallback: VideoDetailPlayURLFallback?
    ) async -> VideoDetailPlayURLFailureHandlingResult {
        guard !Task.isCancelled, !Self.isExpectedPlayURLCancellation(error) else {
            return .aborted(signpostMessage: "bvid=\(detail.bvid) cancelled")
        }
        guard !isPlaybackInvalidatedForNavigation else {
            return .aborted(signpostMessage: "bvid=\(detail.bvid) invalidated")
        }
        if let fallbackSignpostMessage = await applyPlayURLFailureFallbackIfNeeded(
            error,
            cid: cid,
            page: page,
            mode: mode,
            deferredPlayableFallback: deferredPlayableFallback
        ) {
            return .handled(signpostMessage: fallbackSignpostMessage)
        }
        handlePlayURLFailure(error)
        return .handled(signpostMessage: "bvid=\(detail.bvid) failed \(error.localizedDescription)")
    }

    nonisolated static func isExpectedPlayURLCancellation(_ error: Error) -> Bool {
        if error is CancellationError || (error as? URLError)?.code == .cancelled {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}

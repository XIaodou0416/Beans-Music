import Foundation

extension VideoDetailViewModel {
    func applyPlayURLFailureFallbackIfNeeded(
        _ error: Error,
        cid: Int,
        page: Int?,
        mode: VideoDetailPlayURLLoadMode,
        deferredPlayableFallback: VideoDetailPlayURLFallback?
    ) async -> String? {
        if mode.allowsNetworkFailureCacheFallback {
            if let signpostMessage = await applyDeferredPlayURLFallbackIfAvailable(
                deferredPlayableFallback,
                error: error,
                cid: cid,
                page: page
            ) {
                return signpostMessage
            }
            if let signpostMessage = await applyStalePlayablePlayURLFallbackIfAvailable(
                error: error,
                cid: cid,
                page: page
            ) {
                return signpostMessage
            }
            if let signpostMessage = await applyMemoryPlayablePlayURLFallbackIfAvailable(
                error: error,
                cid: cid,
                page: page
            ) {
                return signpostMessage
            }
        }
        if await recoverPlayURLAfterFailure(error, cid: cid, page: page) {
            return "bvid=\(detail.bvid) recovered after failure"
        }
        return nil
    }

    func handlePlayURLFailure(_ error: Error) {
        pendingVideoListenPlaybackIntent = nil
        currentPlayURLData = nil
        clearVideoListenAudioVariants()
        playVariants = []
        selectedPlayVariant = nil
        playURLElapsedMilliseconds = elapsedMilliseconds(since: playURLLoadStartTime)
        playURLState = .failed(playURLFailureMessage(for: error))
    }

    private func playURLFailureMessage(for error: Error) -> String {
        if shouldShowCodecUnavailableMessage(for: error) {
            return codecUnavailableMessage()
        }
        return error.localizedDescription
    }

    private func shouldShowCodecUnavailableMessage(for error: Error) -> Bool {
        guard libraryStore.forceHardwareDecodeEnabled
            || libraryStore.videoCodecPreference.forcedUnavailableMessage != nil
        else { return false }
        if let apiError = error as? BiliAPIError {
            switch apiError {
            case .emptyPlayURL, .unsupportedHardwarePlayback:
                return true
            case .invalidURL, .emptyData, .api, .missingPayload, .missingSESSDATA, .missingCSRF:
                return false
            }
        }
        return false
    }
}

import Foundation

extension VideoDetailViewModel {
    func applyPlayableFallbackPlayURLData(
        _ data: PlayURLData,
        error: Error,
        cid: Int,
        page: Int?,
        source: String,
        note: String,
        playbackFallbackMessage message: String? = nil,
        signpostMessage: String
    ) async -> String {
        let bvid = detail.bvid
        guard isCurrentPlaybackContext(bvid: bvid, cid: cid, page: page) else {
            return "bvid=\(detail.bvid) fallback aborted"
        }
        cancelStartupPlayURLTask()
        PlayerMetricsLog.record(
            .playURLLoaded,
            metricsID: detail.bvid,
            title: detail.title,
            message: playURLLoadedMessage(
                source: source,
                data: data,
                note: note,
                error: error
            )
        )
        await applyPlayURLData(
            data,
            cid: cid,
            page: page,
            source: source
        )
        if let message {
            playbackFallbackMessage = message
        }
        return signpostMessage
    }
}

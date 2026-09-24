import Foundation

extension VideoDetailViewModel {
    func rememberDeferredPlayableFallback(
        _ data: PlayURLData,
        source: String,
        mode: VideoDetailPlayURLLoadMode,
        deferredFallback: inout VideoDetailPlayURLFallback?
    ) {
        guard mode.allowsNetworkFailureCacheFallback else { return }
        guard isPlayablePlayURLData(data) else { return }
        if let existing = deferredFallback,
           existing.data.highestPlayableQuality >= data.highestPlayableQuality {
            return
        }
        deferredFallback = (data, source)
    }

    func applyCachedPlayURLData(
        _ data: PlayURLData,
        cid: Int,
        page: Int?,
        source: String
    ) async {
        guard isCurrentPlaybackContext(bvid: detail.bvid, cid: cid, page: page) else { return }
        PlayerMetricsLog.record(
            .playURLLoaded,
            metricsID: detail.bvid,
            title: detail.title,
            message: playURLLoadedMessage(source: source, data: data)
        )
        await applyPlayURLData(
            data,
            cid: cid,
            page: page,
            source: source
        )
    }
}

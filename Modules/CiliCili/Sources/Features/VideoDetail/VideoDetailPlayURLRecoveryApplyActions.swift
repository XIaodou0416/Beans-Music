import Foundation

extension VideoDetailViewModel {
    func applyRecoveredPlayURLData(
        _ data: PlayURLData,
        cid: Int,
        page: Int?,
        source: String
    ) async -> Bool {
        guard isPlayablePlayURLData(data) else { return false }
        let bvid = detail.bvid
        guard isCurrentPlaybackContext(bvid: bvid, cid: cid, page: page) else { return false }
        await VideoPreloadCenter.shared.store(
            data,
            bvid: detail.bvid,
            cid: cid,
            page: page,
            preferredQuality: adaptiveStartupPreferredQuality,
            targetPreferredQuality: targetPlaybackPreferredQuality,
            cdnPreference: libraryStore.effectivePlaybackCDNPreference,
            warmsMedia: false,
            mediaWarmupDelay: 0
        )
        guard isCurrentPlaybackContext(bvid: bvid, cid: cid, page: page) else { return false }
        PlayerMetricsLog.record(
            .playURLLoaded,
            metricsID: detail.bvid,
            title: detail.title,
            message: playURLLoadedMessage(source: source, data: data, note: "recovered")
        )
        await applyPlayURLData(data, cid: cid, page: page, source: source)
        return selectedPlayVariant?.isPlayable == true || playURLState == .loaded
    }
}

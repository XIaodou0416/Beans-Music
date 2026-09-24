import Foundation

extension VideoDetailViewModel {
    func loadedNetworkPlayURLData(
        cid: Int,
        page: Int?
    ) async throws -> PlayURLData {
        let data = try await startupPlayURLForDefaultQuality(
            bvid: detail.bvid,
            cid: cid,
            page: page
        )
        guard isPlayablePlayURLData(data) else {
            throw BiliAPIError.emptyPlayURL
        }
        return data
    }

    func storeNetworkPlayURLData(
        _ data: PlayURLData,
        cid: Int,
        page: Int?
    ) async {
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
    }

    func applyNetworkPlayURLData(
        _ data: PlayURLData,
        cid: Int,
        page: Int?
    ) async -> VideoDetailPlayURLNetworkApplicationResult {
        let bvid = detail.bvid
        guard !Task.isCancelled else {
            return .aborted(signpostMessage: "bvid=\(detail.bvid) cancelled")
        }
        guard isCurrentPlaybackContext(bvid: bvid, cid: cid, page: page) else {
            return .aborted(signpostMessage: "bvid=\(detail.bvid) invalidated")
        }
        await storeNetworkPlayURLData(data, cid: cid, page: page)
        guard isCurrentPlaybackContext(bvid: bvid, cid: cid, page: page) else {
            return .aborted(signpostMessage: "bvid=\(detail.bvid) invalidated")
        }
        PlayerMetricsLog.record(
            .playURLLoaded,
            metricsID: detail.bvid,
            title: detail.title,
            message: playURLLoadedMessage(source: "network", data: data)
        )
        await applyPlayURLData(data, cid: cid, page: page, source: "network")
        return .applied(signpostMessage: "bvid=\(detail.bvid) network")
    }
}

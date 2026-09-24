import Foundation

extension VideoDetailViewModel {
    func recoverPlayURLAfterFailure(
        _ error: Error,
        cid: Int,
        page: Int?
    ) async -> Bool {
        guard !isPlaybackInvalidatedForNavigation,
              selectedCID == cid
        else { return false }
        let message = error.localizedDescription
        guard !isPlayURLRateLimited(error) else {
            PlayerMetricsLog.record(
                .network,
                metricsID: detail.bvid,
                title: detail.title,
                message: "skip immediate retry after rate limit \(message)"
            )
            playbackFallbackMessage = "播放接口被临时限制，请稍后重试"
            return false
        }
        PlayerMetricsLog.record(
            .network,
            metricsID: detail.bvid,
            title: detail.title,
            message: "retry after failure \(message)"
        )
        await preparePlayURLRecoveryRetry()
        guard !isPlaybackInvalidatedForNavigation,
              selectedCID == cid
        else { return false }

        if await applyStartupPlayURLRecoveryIfPossible(cid: cid, page: page) {
            return true
        }

        guard !isPlaybackInvalidatedForNavigation,
              selectedCID == cid
        else { return false }
        await api.clearCachedPlayURLFailures(bvid: detail.bvid)
        cancelStartupPlayURLTask()

        return await applyFullPlayURLRecoveryIfPossible(cid: cid, page: page)
    }
}

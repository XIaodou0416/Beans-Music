import Foundation
import QuartzCore

extension VideoDetailViewModel {
    func beginDetailLoadTracking() {
        if detailLoadStartTime == nil {
            detailLoadStartTime = CACurrentMediaTime()
            detailLoadElapsedMilliseconds = nil
        }
        didRecordDetailLoadedEvent = false
        PlayerMetricsLog.record(.detailLoadStart, metricsID: detail.bvid, title: detail.title)
    }

    func applyCachedDetailForFastStartIfAvailable() async -> Bool {
        guard !isPlaybackInvalidatedForNavigation else { return false }
        guard !detail.isPGCEpisode else { return false }
        guard let cached = await VideoPreloadCenter.shared.cachedDetail(for: detail.bvid) else {
            return false
        }
        detail = detail.mergingFilledValues(from: cached)
        hasResolvedDetailMetadata = true
        syncCommentsRenderStore()
        selectedCID = selectedCID ?? cached.pages?.first?.cid ?? cached.cid
        return activateCurrentDetailForFastStart(source: "cache")
    }

    @discardableResult
    func activateCurrentDetailForFastStart(source: String) -> Bool {
        guard !isPlaybackInvalidatedForNavigation else { return false }
        selectedCID = selectedCID ?? detail.pages?.first?.cid ?? detail.cid
        guard canActivateDetailFromCurrentData else { return false }

        state = .loaded
        detailLoadElapsedMilliseconds = elapsedMilliseconds(since: detailLoadStartTime) ?? 0
        recordDetailLoadedIfNeeded(source: source)
        scheduleRelatedLoadAfterPlaybackStartIfNeeded()
        return true
    }

    var canActivateDetailFromCurrentData: Bool {
        !detail.bvid.isEmpty
            && selectedCID != nil
            && !detail.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func recordDetailLoadedIfNeeded(source: String) {
        guard !didRecordDetailLoadedEvent else { return }
        didRecordDetailLoadedEvent = true
        PlayerMetricsLog.record(
            .detailLoaded,
            metricsID: detail.bvid,
            title: detail.title,
            message: source
        )
    }
}

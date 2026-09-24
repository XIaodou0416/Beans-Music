import Foundation
import QuartzCore

extension VideoDetailViewModel {
    func beginNetworkDetailLoadIfNeeded() {
        guard state != .loaded else { return }
        state = .loading
        if detailLoadStartTime == nil {
            detailLoadStartTime = CACurrentMediaTime()
            detailLoadElapsedMilliseconds = nil
        }
    }

    func applyLoadedNetworkDetail(_ fullDetail: VideoItem, clearsCurrentDetailTask: Bool) {
        detail = detail.mergingFilledValues(from: fullDetail)
        hasResolvedDetailMetadata = true
        syncCommentsRenderStore()
        selectedCID = selectedCID ?? fullDetail.pages?.first?.cid ?? fullDetail.cid
        if !activateCurrentDetailForFastStart(source: "network") {
            state = .loaded
            detailLoadElapsedMilliseconds = elapsedMilliseconds(since: detailLoadStartTime) ?? 0
            recordDetailLoadedIfNeeded(source: "network")
            scheduleRelatedLoadIfNeeded()
        }
        beginCloudHistoryResumeFetchIfNeeded()
        schedulePlayURLLoadIfNeeded()
        scheduleUploaderAndInteractionLoadIfNeeded()
        if clearsCurrentDetailTask {
            detailLoadingTask = nil
        }
    }

    func applyFailedNetworkDetailLoad(_ error: Error, clearsCurrentDetailTask: Bool) {
        if clearsCurrentDetailTask {
            detailLoadingTask = nil
        }
        detailLoadElapsedMilliseconds = elapsedMilliseconds(since: detailLoadStartTime)
        if state != .loaded {
            state = .failed(error.localizedDescription)
        }
        hasResolvedDetailMetadata = true
    }
}

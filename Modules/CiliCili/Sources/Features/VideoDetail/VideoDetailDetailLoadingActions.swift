import Foundation
import QuartzCore

extension VideoDetailViewModel {
    func loadFullDetailAndMetadata(priority: TaskPriority = .userInitiated) async {
        guard !isPlaybackInvalidatedForNavigation else { return }
        let detailIdentity = detailLoadIdentity
        let signpostState = PlayerMetricsLog.beginSignpostedInterval(
            "VideoDetailDetailLoad",
            message: "\(detailIdentity.metricsMessage) priority=\(String(describing: priority))"
        )
        var signpostMessage = "\(detailIdentity.metricsMessage) loading"
        defer {
            PlayerMetricsLog.endSignpostedInterval(
                "VideoDetailDetailLoad",
                signpostState,
                message: signpostMessage
            )
        }
        let isCurrentDetailTask = detailLoadingTask != nil
        beginNetworkDetailLoadIfNeeded()
        do {
            let fullDetail = try await PlayerMetricsLog.withSignpostedInterval(
                "VideoDetailDetailFetch",
                message: "\(detailIdentity.metricsMessage) priority=\(String(describing: priority))"
            ) {
                try await fetchFullDetail(identity: detailIdentity, priority: priority)
            }
            guard !Task.isCancelled, !isPlaybackInvalidatedForNavigation else {
                signpostMessage = "\(detailIdentity.metricsMessage) cancelled"
                return
            }
            guard isCurrentDetailLoadIdentity(detailIdentity) else {
                signpostMessage = "\(detailIdentity.metricsMessage) stale"
                return
            }
            applyLoadedNetworkDetail(fullDetail, clearsCurrentDetailTask: isCurrentDetailTask)
            signpostMessage = "bvid=\(detail.bvid) loaded"
        } catch {
            guard !Task.isCancelled else {
                signpostMessage = "\(detailIdentity.metricsMessage) cancelled"
                return
            }
            guard !isPlaybackInvalidatedForNavigation else {
                signpostMessage = "\(detailIdentity.metricsMessage) invalidated"
                return
            }
            guard isCurrentDetailLoadIdentity(detailIdentity) else {
                signpostMessage = "\(detailIdentity.metricsMessage) stale"
                return
            }
            applyFailedNetworkDetailLoad(error, clearsCurrentDetailTask: isCurrentDetailTask)
            signpostMessage = "\(detailIdentity.metricsMessage) failed \(error.localizedDescription)"
        }
    }
}

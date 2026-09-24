import Foundation

extension VideoDetailViewModel {
    func updateResumeDiagnostics(
        source: String,
        targetTime: TimeInterval?,
        cid: Int?,
        status: String,
        reason: String,
        currentTime: TimeInterval? = nil
    ) {
        let diagnostics = PlaybackResumeDiagnostics(
            sourceTitle: source,
            targetTime: targetTime,
            cid: cid,
            statusTitle: status,
            reason: reason,
            currentTime: currentTime
        )
        guard diagnostics != resumeDiagnostics else { return }
        resumeDiagnostics = diagnostics

        let targetText = targetTime.map { String(format: "%.2fs", $0) } ?? "none"
        let currentText = currentTime.map { String(format: "%.2fs", $0) } ?? "unknown"
        PlayerMetricsLog.record(
            .resumeDecision,
            metricsID: detail.bvid,
            title: detail.title,
            message: "source=\(source) status=\(status) target=\(targetText) cid=\(cid ?? 0) current=\(currentText) reason=\(reason)"
        )
    }
}

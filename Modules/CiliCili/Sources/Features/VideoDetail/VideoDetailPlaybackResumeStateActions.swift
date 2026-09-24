import Foundation

extension VideoDetailViewModel {
    func recordResumeWaitingForPlayer(sourceTitle: String, resumeTime: TimeInterval, reason: String) {
        updateResumeDiagnostics(
            source: sourceTitle,
            targetTime: resumeTime,
            cid: selectedCID,
            status: "等待播放器",
            reason: reason
        )
    }

    func recordResumeWaitingForTimeline(sourceTitle: String, resumeTime: TimeInterval, reason: String) {
        updateResumeDiagnostics(
            source: sourceTitle,
            targetTime: resumeTime,
            cid: selectedCID,
            status: "等待时间轴",
            reason: reason
        )
    }

    func recordResumeSkippedAsStale(
        sourceTitle: String,
        resumeTime: TimeInterval,
        reason: String,
        currentTime: TimeInterval
    ) {
        updateResumeDiagnostics(
            source: sourceTitle,
            targetTime: resumeTime,
            cid: selectedCID,
            status: "跳过，当前位置更新",
            reason: reason,
            currentTime: currentTime
        )
    }

    func applyResumeTime(
        _ resumeTime: TimeInterval,
        to player: PlayerStateViewModel,
        sourceTitle: String,
        reason: String,
        currentTime: TimeInterval
    ) -> Bool {
        let didApply = player.applyStartupResumeTime(resumeTime, reason: reason)
        updateResumeDiagnostics(
            source: sourceTitle,
            targetTime: resumeTime,
            cid: selectedCID,
            status: didApply ? "已提交并完成 seek" : "已排队等待播放器就绪",
            reason: reason,
            currentTime: currentTime
        )
        return didApply
    }

    func resumePlaybackAfterResumeSeekIfNeeded(_ player: PlayerStateViewModel, wasPlaying: Bool) {
        guard wasPlaying else { return }
        player.setPlaybackIntent(true)
        player.resumePlaybackAfterUserSeek()
    }
}

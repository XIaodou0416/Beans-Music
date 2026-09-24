import Foundation

extension VideoDetailViewModel {
    @discardableResult
    func applyResumeTimeToCurrentPlayerIfPossible(
        _ resumeTime: TimeInterval,
        reason: String,
        shouldResumePlayback: Bool?,
        playbackRateOverride: BiliPlaybackRate?
    ) -> Bool {
        let sourceTitle = resumeSourceTitle(for: reason)
        let signpostState = PlayerMetricsLog.beginSignpostedInterval(
            "VideoDetailResume",
            message: "source=\(sourceTitle) reason=\(reason) target=\(String(format: "%.2f", resumeTime))"
        )
        var signpostMessage = "source=\(sourceTitle) pending"
        defer {
            PlayerMetricsLog.endSignpostedInterval(
                "VideoDetailResume",
                signpostState,
                message: signpostMessage
            )
        }
        guard let player = stablePlayerViewModel else {
            recordResumeWaitingForPlayer(sourceTitle: sourceTitle, resumeTime: resumeTime, reason: reason)
            signpostMessage = "source=\(sourceTitle) waiting player"
            return false
        }
        let snapshot = player.playbackSnapshot()
        let currentTime = max(snapshot.currentTime ?? 0, player.currentTime)
        guard currentTime.isFinite else {
            recordResumeWaitingForTimeline(sourceTitle: sourceTitle, resumeTime: resumeTime, reason: reason)
            signpostMessage = "source=\(sourceTitle) waiting timeline"
            return false
        }
        guard resumeTime > currentTime + 2 else {
            recordResumeSkippedAsStale(
                sourceTitle: sourceTitle,
                resumeTime: resumeTime,
                reason: reason,
                currentTime: currentTime
            )
            signpostMessage = "source=\(sourceTitle) stale"
            return false
        }
        if let playbackRateOverride {
            player.setPlaybackRate(playbackRateOverride)
        }
        let wasPlaying = shouldResumePlayback ?? (player.wantsAutoplay || player.isPlaying || snapshot.isPlaying)
        let didApply = applyResumeTime(
            resumeTime,
            to: player,
            sourceTitle: sourceTitle,
            reason: reason,
            currentTime: currentTime
        )
        signpostMessage = "source=\(sourceTitle) \(didApply ? "applied" : "queued")"
        resumePlaybackAfterResumeSeekIfNeeded(player, wasPlaying: wasPlaying)
        return didApply
    }
}

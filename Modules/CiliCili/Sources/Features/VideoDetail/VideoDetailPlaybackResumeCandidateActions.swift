import Foundation

extension VideoDetailViewModel {
    func currentPlaybackResumeTime() -> TimeInterval {
        guard let player = stablePlayerViewModel else { return 0 }
        let snapshotTime = player.playbackSnapshot().currentTime
        let bestTime = max(snapshotTime ?? 0, player.currentTime)
        guard bestTime.isFinite else { return 0 }
        return max(bestTime, 0)
    }

    func playbackResumeCandidate(
        resumeTimeOverride: TimeInterval?,
        localResumeTime: TimeInterval
    ) -> PlaybackResumeCandidate {
        if let resumeTimeOverride, resumeTimeOverride > 0.25 {
            return PlaybackResumeCandidate(
                time: resumeTimeOverride,
                sourceTitle: resumeSourceTitle(for: "override"),
                reason: "显式续播目标",
                cid: selectedCID
            )
        }

        if localResumeTime > 0.25 {
            return PlaybackResumeCandidate(
                time: localResumeTime,
                sourceTitle: "当前播放",
                reason: "复用当前播放器快照",
                cid: selectedCID
            )
        }

        return PlaybackResumeCandidate(
            time: 0,
            sourceTitle: "无",
            reason: "没有可用历史进度",
            cid: selectedCID
        )
    }

    func resumeSourceTitle(for reason: String) -> String {
        switch reason {
        case "stableIdentityResume", "override":
            return "指定进度"
        default:
            return "当前播放"
        }
    }

    func currentPlaybackIntent() -> Bool {
        if let pendingVideoListenPlaybackIntent {
            return pendingVideoListenPlaybackIntent
        }
        guard let player = stablePlayerViewModel else {
            return libraryStore.videoDetailAutoplayEnabled
        }
        let snapshot = player.playbackSnapshot()
        return player.wantsAutoplay || player.isPlaying || snapshot.isPlaying
    }
}

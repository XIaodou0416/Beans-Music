import Foundation

extension VideoDetailViewModel {
    func applyStableIdentityResumeIfNeeded(
        identity: String,
        resumeTimeOverride: TimeInterval?,
        shouldResumePlayback: Bool?,
        playbackRateOverride: BiliPlaybackRate?
    ) -> Bool {
        guard stablePlayerIdentity == identity else { return false }
        if let resumeTimeOverride {
            updateResumeDiagnostics(
                source: resumeSourceTitle(for: "stableIdentityResume"),
                targetTime: resumeTimeOverride,
                cid: selectedCID,
                status: "同一播放器，准备应用",
                reason: "播放器身份未变化"
            )
            applyResumeTimeToCurrentPlayerIfPossible(
                resumeTimeOverride,
                reason: "stableIdentityResume",
                shouldResumePlayback: shouldResumePlayback,
                playbackRateOverride: playbackRateOverride
            )
        }
        return true
    }
}

import Foundation

struct StablePlayerStartupPreparation {
    let previousPlayer: PlayerStateViewModel?
    let playbackHandoffSource: PlayerStateViewModel?
    let resumeCandidate: PlaybackResumeCandidate
    let resumeTime: TimeInterval
    let shouldAutoplay: Bool
    let playbackRate: BiliPlaybackRate
}

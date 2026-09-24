import Foundation

extension VideoDetailDanmakuOverlayState {
    func refreshSnapshot(
        renderSnapshot: VideoDetailDanmakuRenderSnapshot,
        playerViewModel: PlayerStateViewModel
    ) {
        updateSnapshot {
            $0.isEnabled = renderSnapshot.isDanmakuEnabled
            $0.settings = renderSnapshot.effectiveSettings
            $0.isPlaying = playerViewModel.isPlaying
            $0.playbackRate = playerViewModel.playbackRate.rawValue
            $0.hasPresentedPlayback = Self.canRenderDanmaku(for: playerViewModel)
            $0.isLoadShedding = Self.loadSheddingState(for: playerViewModel)
        }
    }

    static func loadSheddingState(for playerViewModel: PlayerStateViewModel) -> Bool {
        playerViewModel.isUserSeeking
            || playerViewModel.isBuffering
            || playerViewModel.playbackRate.rawValue > 1.15
    }
}

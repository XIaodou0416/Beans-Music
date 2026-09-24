import Foundation

extension VideoDetailViewModel {
    nonisolated static func makeDeinitPlaybackCleanup(
        for player: PlayerStateViewModel?
    ) -> (@Sendable () -> Void)? {
        guard let player else { return nil }
        return {
            stopPlayerAfterDeinit(player)
        }
    }

    nonisolated static func stopPlaybackBeforeDeinit(
        playbackTransitionState: inout VideoDetailPlaybackTransitionState,
        navigationState: inout VideoDetailPlaybackNavigationState
    ) {
        navigationState.playbackStopTask?.cancel()
        navigationState.playbackStopTask = nil
        navigationState.isPlaybackTerminatedForNavigation = true
        navigationState.isPlaybackInvalidatedForNavigation = true
        let transitionPlayer = playbackTransitionState.playerViewModel
        playbackTransitionState.releaseTask?.cancel()
        playbackTransitionState.releaseTask = nil
        playbackTransitionState.releaseGeneration += 1
        playbackTransitionState.playerViewModel = nil
        playbackTransitionState.snapshot = nil
        playbackTransitionState.fallbackCoverURL = nil
        playbackTransitionState.opacity = 0

        stopPlayerAfterDeinit(transitionPlayer)
    }

    private nonisolated static func stopPlayerAfterDeinit(_ player: PlayerStateViewModel?) {
        guard let player else { return }
        Task { @MainActor [player] in
            player.stop(reason: .deallocated)
        }
    }
}

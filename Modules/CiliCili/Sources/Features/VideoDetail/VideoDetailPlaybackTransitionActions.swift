import Foundation

extension VideoDetailViewModel {
    func beginPlaybackTransition(
        from player: PlayerStateViewModel?,
        keepsPlaybackActive: Bool = false
    ) {
        guard !isPlaybackInvalidatedForNavigation else {
            clearPlaybackTransitionPlayer()
            return
        }
        guard let player,
              player.hasPresentedPlayback,
              !player.isTerminated
        else {
            if playbackTransitionPlayerViewModel == nil {
                clearPlaybackTransitionPlayer()
            }
            return
        }
        if let transitionPlayer = playbackTransitionPlayerViewModel,
           transitionPlayer !== player {
            clearPlaybackTransitionPlayer()
        } else {
            cancelPlaybackTransitionReleaseTask()
        }
        let snapshot = player.makePlaybackTransitionSnapshot()
        let fallbackCoverURL = playbackTransitionCoverURL()
        if !keepsPlaybackActive {
            player.prepareForVisualPlaybackTransition()
        }
        playbackTransitionPlayerViewModel = player
        playbackTransitionSnapshot = snapshot
        playbackTransitionFallbackCoverURL = fallbackCoverURL
        playbackTransitionOpacity = (snapshot != nil || fallbackCoverURL != nil) ? 1 : 0
        releasePlaybackTransitionPlayer(after: Self.playbackTransitionMaximumRetainNanoseconds)
    }

    func beginFullscreenExitVisualTransition(from player: PlayerStateViewModel?) {
        beginFullscreenVisualTransition(
            from: player,
            holdNanoseconds: Self.fullscreenExitTransitionMaskHoldNanoseconds,
            fadeDurationNanoseconds: Self.fullscreenExitTransitionMaskFadeDurationNanoseconds
        )
    }

    func beginFullscreenVisualTransition(from player: PlayerStateViewModel?) {
        beginFullscreenVisualTransition(
            from: player,
            holdNanoseconds: VideoDetailViewModel.fullscreenTransitionMaskHoldNanoseconds,
            fadeDurationNanoseconds: VideoDetailViewModel.fullscreenTransitionMaskFadeDurationNanoseconds
        )
    }

    func beginFullscreenVisualTransition(
        from player: PlayerStateViewModel?,
        holdNanoseconds: UInt64,
        fadeDurationNanoseconds: UInt64
    ) {
        guard !isPlaybackInvalidatedForNavigation,
              let player,
              !player.isTerminated
        else { return }

        if let transitionPlayer = playbackTransitionPlayerViewModel,
           transitionPlayer !== player {
            clearPlaybackTransitionPlayer()
        } else {
            cancelPlaybackTransitionReleaseTask()
        }

        guard player.hasPresentedPlayback else { return }

        playbackTransitionPlayerViewModel = player
        playbackTransitionSnapshot = nil
        playbackTransitionFallbackCoverURL = nil
        playbackTransitionOpacity = 0
        VideoDetailRotationWindowMask.remove()
        syncPlayerIdentityRenderStore()

        releasePlaybackTransitionPlayer(
            after: holdNanoseconds,
            fadeDuration: fadeDurationNanoseconds
        )
    }

    func clearPlaybackTransitionPlayer() {
        cancelPlaybackTransitionReleaseTask()
        let transitionPlayer = playbackTransitionPlayerViewModel
        playbackTransitionPlayerViewModel = nil
        playbackTransitionSnapshot = nil
        playbackTransitionFallbackCoverURL = nil
        playbackTransitionOpacity = 0
        VideoDetailRotationWindowMask.remove()
        guard let transitionPlayer else { return }
        if stablePlayerViewModel !== transitionPlayer {
            transitionPlayer.stop(reason: .replacedByAnotherPlayer)
        }
    }

    func playbackTransitionCoverURL() -> URL? {
        guard let cover = detail.pic?.normalizedBiliURL() else { return nil }
        let width = PlaybackEnvironment.current.shouldPreferConservativePlayback ? 480 : 720
        let height = Int((Double(width) * 9.0 / 16.0).rounded())
        return URL(string: cover.biliCoverThumbnailURL(width: width, height: height))
            ?? URL(string: cover)
    }
}

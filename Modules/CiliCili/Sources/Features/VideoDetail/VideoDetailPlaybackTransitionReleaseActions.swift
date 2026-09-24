import Foundation

extension VideoDetailViewModel {
    func releasePlaybackTransitionPlayer(
        after delay: UInt64,
        fadeDuration: UInt64? = nil
    ) {
        guard !isPlaybackInvalidatedForNavigation,
              playbackTransitionPlayerViewModel != nil
        else { return }
        cancelPlaybackTransitionReleaseTask(advancesGeneration: false)
        let releaseGeneration = advancePlaybackTransitionReleaseGeneration()
        let transitionPlayer = playbackTransitionPlayerViewModel
        playbackTransitionReleaseTask = Task { @MainActor [weak self, weak transitionPlayer] in
            try? await Task.sleep(nanoseconds: delay)
            guard let self,
                  !Task.isCancelled,
                  !self.isPlaybackInvalidatedForNavigation,
                  let transitionPlayer,
                  self.playbackTransitionReleaseGeneration == releaseGeneration,
                  self.playbackTransitionPlayerViewModel === transitionPlayer
            else { return }
            self.playbackTransitionOpacity = 0
            VideoDetailRotationWindowMask.release(
                after: 0,
                fadeDuration: fadeDuration ?? Self.playbackTransitionFadeDurationNanoseconds
            )
            try? await Task.sleep(nanoseconds: fadeDuration ?? Self.playbackTransitionFadeDurationNanoseconds)
            guard !Task.isCancelled,
                  !self.isPlaybackInvalidatedForNavigation,
                  self.playbackTransitionReleaseGeneration == releaseGeneration,
                  self.playbackTransitionPlayerViewModel === transitionPlayer
            else { return }
            self.finishPlaybackTransitionRelease(
                transitionPlayer,
                releaseGeneration: releaseGeneration
            )
        }
    }

    func cancelPlaybackTransitionReleaseTask(advancesGeneration: Bool = true) {
        playbackTransitionReleaseTask?.cancel()
        playbackTransitionReleaseTask = nil
        if advancesGeneration {
            advancePlaybackTransitionReleaseGeneration()
        }
    }

    @discardableResult
    func advancePlaybackTransitionReleaseGeneration() -> Int {
        playbackTransitionReleaseGeneration += 1
        return playbackTransitionReleaseGeneration
    }

    private func finishPlaybackTransitionRelease(
        _ transitionPlayer: PlayerStateViewModel,
        releaseGeneration: Int
    ) {
        guard playbackTransitionReleaseGeneration == releaseGeneration else { return }
        playbackTransitionReleaseTask = nil
        guard playbackTransitionPlayerViewModel === transitionPlayer else { return }
        playbackTransitionPlayerViewModel = nil
        playbackTransitionSnapshot = nil
        playbackTransitionFallbackCoverURL = nil
        playbackTransitionOpacity = 0
        VideoDetailRotationWindowMask.remove()
        if stablePlayerViewModel !== transitionPlayer {
            transitionPlayer.stop(reason: .replacedByAnotherPlayer)
        }
    }
}

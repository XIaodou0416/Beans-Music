import Combine
import Foundation
import OSLog

extension VideoDetailViewModel {
    func observePlaybackErrors(_ playerViewModel: PlayerStateViewModel, variant: PlayVariant) {
        stablePlayerErrorCancellable = playerViewModel.$errorMessage
            .compactMap { $0 }
            .removeDuplicates()
            .sink { [weak self, weak playerViewModel] message in
                guard let self,
                      let playerViewModel,
                      self.stablePlayerViewModel === playerViewModel,
                      playerViewModel.onPlaybackFailureWithReason == nil
                else { return }
                self.finishPlaybackStartupWaiters(with: .failed)
                self.handlePlaybackError(message, for: variant)
            }
    }

    func observeFirstFrameMetrics(
        _ playerViewModel: PlayerStateViewModel,
        variant: PlayVariant,
        resumeCandidate: PlaybackResumeCandidate
    ) {
        stablePlayerFirstFrameCancellable = playerViewModel.$firstFrameElapsedMilliseconds
            .compactMap { $0 }
            .first()
            .sink { [weak self, weak playerViewModel] firstFrameElapsedMilliseconds in
                guard let self,
                      let playerViewModel,
                      self.stablePlayerViewModel === playerViewModel
                else { return }
                self.finishPlaybackStartupWaiters(with: .firstFrame)
                self.recordStartupPlaybackMetrics(
                    variant: variant,
                    resumeCandidate: resumeCandidate,
                    playerViewModel: playerViewModel,
                    firstFrameElapsedMilliseconds: firstFrameElapsedMilliseconds
                )
                self.releasePlaybackTransitionPlayer(after: Self.playbackTransitionReleaseDelayNanoseconds)
            }
    }
}

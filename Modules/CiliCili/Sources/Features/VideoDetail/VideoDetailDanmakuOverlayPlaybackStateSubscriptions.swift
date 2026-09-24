import Combine
import Foundation

@MainActor
extension VideoDetailDanmakuOverlayState {
    func bindPlaybackFlags(playerViewModel: PlayerStateViewModel) {
        playerViewModel.$isPlaying
            .removeDuplicates()
            .sink { [weak self, weak playerViewModel] isPlaying in
                guard playerViewModel?.isTerminated != true else { return }
                self?.updateSnapshot { $0.isPlaying = isPlaying }
            }
            .store(in: &cancellables)
    }

    func bindLoadSheddingState(playerViewModel: PlayerStateViewModel) {
        playerViewModel.$playbackRate
            .removeDuplicates()
            .sink { [weak self, weak playerViewModel] rate in
                guard let self,
                      playerViewModel?.isTerminated != true
                else { return }
                let previousLoadShedding = self.snapshot.isLoadShedding
                self.updateSnapshot {
                    $0.playbackRate = rate.rawValue
                    if let playerViewModel {
                        $0.isLoadShedding = Self.loadSheddingState(for: playerViewModel)
                    }
                }
                if let playerViewModel,
                   previousLoadShedding != self.snapshot.isLoadShedding {
                    self.updateWindow(around: playerViewModel.playbackClock.currentTime, force: true)
                }
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(
            playerViewModel.$hasPresentedPlayback,
            playerViewModel.$isCurrentPlaybackSurfaceReadyForDisplay
        )
            .removeDuplicates { lhs, rhs in
                lhs.0 == rhs.0 && lhs.1 == rhs.1
            }
            .sink { [weak self, weak playerViewModel] value in
                let (hasPresentedPlayback, isCurrentPlaybackSurfaceReady) = value
                guard playerViewModel?.isTerminated != true else { return }
                self?.updateSnapshot {
                    $0.hasPresentedPlayback = hasPresentedPlayback && isCurrentPlaybackSurfaceReady
                }
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(playerViewModel.$isBuffering, playerViewModel.$isUserSeeking)
            .sink { [weak self, weak playerViewModel] _, _ in
                guard let self,
                      let playerViewModel,
                      !playerViewModel.isTerminated
                else { return }
                let previousLoadShedding = self.snapshot.isLoadShedding
                self.updateSnapshot { $0.isLoadShedding = Self.loadSheddingState(for: playerViewModel) }
                if previousLoadShedding != self.snapshot.isLoadShedding {
                    self.updateWindow(around: playerViewModel.playbackClock.currentTime, force: true)
                }
            }
            .store(in: &cancellables)
    }
}

import Combine
import Foundation

@MainActor
extension VideoDetailDanmakuOverlayState {
    func bindRenderStoreUpdates(
        store: VideoDetailDanmakuRenderStore,
        playerViewModel: PlayerStateViewModel
    ) {
        store.$snapshot
            .dropFirst()
            .sink { [weak self, weak playerViewModel] renderSnapshot in
                guard let self,
                      playerViewModel?.isTerminated != true
                else { return }
                self.updateSnapshot {
                    $0.isEnabled = renderSnapshot.isDanmakuEnabled
                    $0.settings = renderSnapshot.effectiveSettings
                }
                guard self.sourceItemsRevision != renderSnapshot.itemsRevision else { return }
                self.allItems = renderSnapshot.items
                self.sourceItemsRevision = renderSnapshot.itemsRevision
                self.lastWindowCenterBucket = nil
                self.updateWindow(
                    around: playerViewModel?.playbackClock.currentTime ?? 0,
                    force: true
                )
            }
            .store(in: &cancellables)
    }

    func bindPlaybackClock(playerViewModel: PlayerStateViewModel) {
        let recenterInterval = windowRecenterInterval
        playerViewModel.playbackClock.$currentTime
            .map { currentTime in
                Int(max(0, currentTime) / max(recenterInterval, 1))
            }
            .removeDuplicates()
            .sink { [weak self, weak playerViewModel] _ in
                guard let self,
                      let playerViewModel,
                      !playerViewModel.isTerminated
                else { return }
                self.updateWindow(around: playerViewModel.playbackClock.currentTime, force: false)
            }
            .store(in: &cancellables)
    }
}

import SwiftUI

struct BiliPlayerSpeedBoostActions {
    let viewModel: PlayerStateViewModel
    let surfaceState: PlayerSurfaceStateModel
    let speedBoostModel: PlayerSpeedBoostModel
    let visibilityActions: BiliPlayerPlaybackControlsVisibilityActions

    @discardableResult
    func beginIfNeeded() -> Bool {
        speedBoostModel.beginIfNeeded(
            playerViewModel: viewModel,
            isSurfacePlaying: surfaceState.isPlaying
        ) {
            visibilityActions.cancelAutoHide()
            visibilityActions.playbackControlsVisibility.hide(animated: true)
        }
    }

    func end(reason: PlayerSpeedBoostEndReason) {
        speedBoostModel.end(
            reason: reason,
            playerViewModel: viewModel
        ) {
            visibilityActions.showAndSchedule()
        }
    }
}

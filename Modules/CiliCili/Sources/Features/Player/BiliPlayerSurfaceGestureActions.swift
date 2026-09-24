import SwiftUI

struct BiliPlayerSurfaceGestureActions {
    let viewModel: PlayerStateViewModel
    let visibilityActions: BiliPlayerPlaybackControlsVisibilityActions
    let speedBoostActions: BiliPlayerSpeedBoostActions
    let holdCurrentFrameForSeek: () -> Void
    let prepareUserSeekWarmup: (Double, Bool) -> Void
    let resetPreparedScrubProgress: () -> Void

    func singleTap() {
        guard !viewModel.isTerminated else { return }
        visibilityActions.toggle()
    }

    func doubleTap() {
        guard !viewModel.isTerminated else { return }
        viewModel.togglePlayback()
        visibilityActions.showAndSchedule()
    }

    func beginSpeedBoost() -> Bool {
        speedBoostActions.beginIfNeeded()
    }

    func endSpeedBoost(reason: PlayerSpeedBoostEndReason) {
        speedBoostActions.end(reason: reason)
    }

    func horizontalSeekStart(_ progress: Double) {
        guard !viewModel.isTerminated else { return }
        visibilityActions.markInteraction(keepsVisible: true)
        prepareUserSeekWarmup(progress, true)
        viewModel.beginUserScrubInteraction(source: .surfaceGesture)
    }

    func horizontalSeekChanged(_ progress: Double) {
        guard !viewModel.isTerminated else { return }
        prepareUserSeekWarmup(progress, false)
    }

    func horizontalSeekEnded(_ progress: Double) {
        guard !viewModel.isTerminated else {
            viewModel.playbackClock.clearSeekPreview()
            resetPreparedScrubProgress()
            return
        }
        prepareUserSeekWarmup(progress, true)
        holdCurrentFrameForSeek()
        viewModel.seekAfterSliderCommit(to: progress)
        viewModel.playbackClock.clearSeekPreview()
        resetPreparedScrubProgress()
        visibilityActions.markInteraction()
    }

    func horizontalSeekCancelled() {
        viewModel.cancelUserScrubInteraction()
        viewModel.playbackClock.clearSeekPreview()
        resetPreparedScrubProgress()
        visibilityActions.markInteraction()
    }
}

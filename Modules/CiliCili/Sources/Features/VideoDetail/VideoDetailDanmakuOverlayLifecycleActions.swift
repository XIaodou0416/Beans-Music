import Foundation

struct VideoDetailDanmakuOverlayLifecycleActions {
    let store: VideoDetailDanmakuRenderStore
    let playerViewModel: PlayerStateViewModel
    let clock: PlayerPlaybackClock
    let state: VideoDetailDanmakuOverlayState
    let onPlaybackTime: (TimeInterval, Bool) -> Void

    func bindAndReportPlaybackTime() {
        guard !playerViewModel.isTerminated else {
            state.unbind()
            return
        }
        state.bind(store: store, playerViewModel: playerViewModel)
        reportPlaybackTime()
    }

    func reportPlaybackTime() {
        guard !playerViewModel.isTerminated else { return }
        onPlaybackTime(clock.currentTime, false)
    }

    func unbind() {
        state.unbind()
    }
}

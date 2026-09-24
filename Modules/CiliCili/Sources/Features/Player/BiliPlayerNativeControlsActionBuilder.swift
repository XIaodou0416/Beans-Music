import SwiftUI

struct BiliPlayerNativeControlsActionBuilder {
    let viewModel: PlayerStateViewModel
    let configuration: BiliPlayerViewConfiguration
    let visibilityActions: BiliPlayerPlaybackControlsVisibilityActions
    let seekPreviewModel: PlayerSeekPreviewModel
    let seekPreviewAPI: BiliAPIClient?
    let seekPreviewContext: PlayerSeekPreviewContext?
    let holdCurrentFrameForSeek: () -> Void
    let prepareUserSeekWarmup: (Double, Bool) -> Void
    let resetPreparedScrubProgress: () -> Void
    var isFullscreenActiveOverride: Bool? = nil

    var actions: PlayerNativePlaybackControlsActions {
        PlayerNativePlaybackControlsActions(
            onScrubStart: { progress in
                guard !viewModel.isTerminated else { return }
                seekPreviewModel.beginScrub(
                    api: seekPreviewAPI,
                    context: seekPreviewContext,
                    source: .nativeProgress,
                    progress: progress,
                    duration: resolvedDuration
                )
                visibilityActions.markInteraction(keepsVisible: true)
                prepareUserSeekWarmup(progress, true)
                viewModel.beginUserScrubInteraction(source: .nativeProgress)
            },
            onScrubChanged: { progress in
                guard !viewModel.isTerminated else { return }
                seekPreviewModel.updateScrub(progress: progress, duration: resolvedDuration)
                prepareUserSeekWarmup(progress, false)
            },
            onScrubEnded: { progress in
                seekPreviewModel.endScrub()
                guard !viewModel.isTerminated else {
                    resetPreparedScrubProgress()
                    return
                }
                prepareUserSeekWarmup(progress, true)
                holdCurrentFrameForSeek()
                viewModel.seekAfterSliderCommit(to: progress)
                resetPreparedScrubProgress()
                visibilityActions.markInteraction()
            },
            onScrubCancelled: {
                seekPreviewModel.endScrub()
            },
            onTogglePlayback: {
                guard !viewModel.isTerminated else { return }
                visibilityActions.markInteraction()
                viewModel.togglePlayback()
            },
            onToggleDanmaku: {
                guard !viewModel.isTerminated else { return }
                if let onShowDanmakuSettings = configuration.onShowDanmakuSettings {
                    visibilityActions.markInteraction(keepsVisible: true)
                    onShowDanmakuSettings()
                } else {
                    visibilityActions.markInteraction()
                    configuration.onToggleDanmaku?()
                }
            },
            onToggleFullscreen: {
                guard !viewModel.isTerminated else { return }
                visibilityActions.markInteraction()
                if isFullscreenActiveOverride ?? configuration.isFullscreenActive {
                    configuration.onExitFullscreen?()
                } else {
                    configuration.onRequestFullscreen?()
                }
            }
        )
    }

    private var resolvedDuration: TimeInterval {
        viewModel.playbackClock.duration ?? viewModel.displayDuration ?? 0
    }
}

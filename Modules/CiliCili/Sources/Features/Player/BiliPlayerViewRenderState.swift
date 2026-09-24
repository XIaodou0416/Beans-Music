import SwiftUI

struct BiliPlayerViewRenderState {
    let controlMetrics: PlayerNativeControlMetrics
    let visibilityActions: BiliPlayerPlaybackControlsVisibilityActions
    let speedBoostActions: BiliPlayerSpeedBoostActions
    let showsActivePlaybackControls: Bool
    let showsPlayerLoadingChrome: Bool
    let showsInlineLoadingProgress: Bool

    init(
        context: BiliPlayerViewRenderContext,
        verticalSizeClass: UserInterfaceSizeClass?
    ) {
        controlMetrics = Self.makeControlMetrics(
            configuration: context.configuration,
            verticalSizeClass: verticalSizeClass
        )
        visibilityActions = BiliPlayerPlaybackControlsVisibilityActions(
            playbackControlsVisibility: context.playbackControlsVisibility,
            configuration: context.configuration
        )
        speedBoostActions = BiliPlayerSpeedBoostActions(
            viewModel: context.viewModel,
            surfaceState: context.surfaceState,
            speedBoostModel: context.speedBoostModel,
            visibilityActions: visibilityActions
        )
        showsActivePlaybackControls = context.configuration.showsPlaybackControls
            && context.playbackControlsVisibility.isVisible
        showsPlayerLoadingChrome = Self.makeShowsPlayerLoadingChrome(context: context)
        showsInlineLoadingProgress = context.surfaceState.hasPresentedPlayback
            && (context.surfaceState.isBuffering || context.surfaceState.isUserSeeking)
    }

    private static func makeControlMetrics(
        configuration: BiliPlayerViewConfiguration,
        verticalSizeClass: UserInterfaceSizeClass?
    ) -> PlayerNativeControlMetrics {
        if configuration.fullscreenMode?.isLandscape == true {
            return .landscape
        }
        if configuration.controlLayout.isLive {
            return .livePortrait
        }
        if verticalSizeClass == .compact {
            return .landscape
        }
        return .portrait
    }

    private static func makeShowsPlayerLoadingChrome(
        context: BiliPlayerViewRenderContext
    ) -> Bool {
        guard context.surfaceState.isPreparing || context.surfaceState.isBuffering else { return false }
        guard !context.surfaceState.hasPresentedPlayback else { return false }
        return context.configuration.showsStartupLoadingIndicator
    }
}

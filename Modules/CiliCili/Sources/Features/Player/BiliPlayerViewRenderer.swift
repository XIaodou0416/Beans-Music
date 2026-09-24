import Foundation
import SwiftUI

struct BiliPlayerViewRenderContext {
    let viewModel: PlayerStateViewModel
    let surfaceState: PlayerSurfaceStateModel
    let playbackControlsVisibility: PlayerPlaybackControlsVisibilityModel
    let rotationTransitionSnapshotModel: PlayerRotationTransitionSnapshotModel
    let seekTransitionSnapshotModel: PlayerRotationTransitionSnapshotModel
    let appBackgroundRecoverySnapshotModel: PlayerRotationTransitionSnapshotModel
    let rotationFallbackCoverURL: URL?
    let speedBoostModel: PlayerSpeedBoostModel
    let seekPreviewModel: PlayerSeekPreviewModel
    let seekPreviewAPI: BiliAPIClient?
    let seekPreviewContext: PlayerSeekPreviewContext?
    let configuration: BiliPlayerViewConfiguration
    let isPictureInPictureEnabled: Bool
    let holdCurrentFrameForSeek: () -> Void
    let prepareUserSeekWarmup: (Double, Bool) -> Void
    let resetPreparedScrubProgress: () -> Void
}

struct BiliPlayerViewRenderer: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let context: BiliPlayerViewRenderContext

    private var renderState: BiliPlayerViewRenderState {
        BiliPlayerViewRenderState(
            context: context,
            verticalSizeClass: verticalSizeClass
        )
    }

    var body: some View {
        let state = renderState

        BiliPlayerViewContent(
            context: context,
            renderState: state
        )
        .environment(\.playerNativeControlMetrics, state.controlMetrics)
    }
}

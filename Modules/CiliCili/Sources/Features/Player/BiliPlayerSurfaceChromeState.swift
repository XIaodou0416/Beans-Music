import Foundation
import SwiftUI

struct BiliPlayerSurfaceChromeState {
    let presentation: BiliPlayerPresentation
    let surfaceOverlay: AnyView?
    let rotationSnapshot: PlaybackTransitionSnapshot?
    let seekSnapshot: PlaybackTransitionSnapshot?
    let appBackgroundRecoverySnapshot: PlaybackTransitionSnapshot?
    let rotationFallbackCoverURL: URL?
    let rotationSnapshotOpacity: Double
    let seekSnapshotOpacity: Double
    let appBackgroundRecoverySnapshotOpacity: Double
    let constrainsRotationSnapshotToVideoAspect: Bool
    let showsPlayerLoadingChrome: Bool
    let isBuffering: Bool
    let isPlaying: Bool
    let hasPresentedPlayback: Bool
    let showsInlineLoadingProgress: Bool
    let isUserSeeking: Bool
    let showsActivePlaybackControls: Bool
    let playbackControlsOpacity: Double
    let playbackControlsAllowsHitTesting: Bool
    let topLeadingControlsAccessory: AnyView?
    let topCenterControlsAccessory: AnyView?
    let topTrailingControlsAccessory: AnyView?
    let isFullscreenActive: Bool
    let controlsBottomLift: CGFloat
    let controlsHorizontalInset: CGFloat
    let contentInsets: EdgeInsets
    let errorMessage: String?
}

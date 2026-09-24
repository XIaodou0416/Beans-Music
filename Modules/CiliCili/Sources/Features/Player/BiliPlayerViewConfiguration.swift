import SwiftUI

struct BiliPlayerViewConfiguration {
    let presentation: BiliPlayerPresentation
    let showsNavigationChrome: Bool
    let showsPlaybackControls: Bool
    let allowsDoubleTapPlaybackToggle: Bool
    let showsStartupLoadingIndicator: Bool
    let pausesOnDisappear: Bool
    let surfaceOverlay: AnyView?
    let controlsAccessory: AnyView?
    let controlsCenterAccessory: AnyView?
    let topLeadingControlsAccessory: AnyView?
    let showsMoreControls: Bool
    let controlLayout: BiliPlayerControlLayout
    let moreControlsContent: AnyView?
    let replacesStandardMoreControls: Bool
    let controlsBottomLift: CGFloat
    let controlsHorizontalInset: CGFloat
    let isDanmakuEnabled: Bool
    let onToggleDanmaku: (() -> Void)?
    let onShowDanmakuSettings: (() -> Void)?
    let isSecondaryControlsPresented: Bool
    let durationHint: TimeInterval?
    let embeddedAspectRatio: CGFloat
    let ignoresContainerSafeArea: Bool
    let keepsPlayerSurfaceStable: Bool
    let fullscreenMode: PlayerFullscreenMode?
    let isLayoutTransitioning: Bool
    let usesLiveSurfaceDuringLayoutTransition: Bool
    let disablesSurfaceImplicitLayoutAnimations: Bool
    let showsRotationTransitionSnapshot: Bool
    let onPrepareForUserSeek: ((Double) -> Void)?
    let onRequestFullscreen: (() -> Void)?
    let onExitFullscreen: (() -> Void)?
    let allowsPlaybackActivation: (() -> Bool)?

    var isFullscreenActive: Bool {
        fullscreenMode != nil
    }

    var canToggleFullscreen: Bool {
        if isFullscreenActive {
            return onExitFullscreen != nil
        }
        return onRequestFullscreen != nil
    }

    init(
        presentation: BiliPlayerPresentation,
        showsNavigationChrome: Bool,
        showsPlaybackControls: Bool,
        allowsDoubleTapPlaybackToggle: Bool,
        showsStartupLoadingIndicator: Bool,
        pausesOnDisappear: Bool,
        surfaceOverlay: AnyView?,
        controlsAccessory: AnyView?,
        controlsCenterAccessory: AnyView?,
        topLeadingControlsAccessory: AnyView?,
        showsMoreControls: Bool,
        controlLayout: BiliPlayerControlLayout,
        moreControlsContent: AnyView?,
        replacesStandardMoreControls: Bool,
        controlsBottomLift: CGFloat,
        controlsHorizontalInset: CGFloat,
        isDanmakuEnabled: Bool,
        onToggleDanmaku: (() -> Void)?,
        onShowDanmakuSettings: (() -> Void)?,
        isSecondaryControlsPresented: Bool,
        durationHint: TimeInterval?,
        embeddedAspectRatio: CGFloat,
        ignoresContainerSafeArea: Bool,
        keepsPlayerSurfaceStable: Bool,
        fullscreenMode: PlayerFullscreenMode?,
        isLayoutTransitioning: Bool,
        usesLiveSurfaceDuringLayoutTransition: Bool,
        disablesSurfaceImplicitLayoutAnimations: Bool,
        showsRotationTransitionSnapshot: Bool,
        onPrepareForUserSeek: ((Double) -> Void)?,
        onRequestFullscreen: (() -> Void)?,
        onExitFullscreen: (() -> Void)?,
        allowsPlaybackActivation: (() -> Bool)?
    ) {
        self.presentation = presentation
        self.showsNavigationChrome = showsNavigationChrome
        self.showsPlaybackControls = showsPlaybackControls
        self.allowsDoubleTapPlaybackToggle = allowsDoubleTapPlaybackToggle
        self.showsStartupLoadingIndicator = showsStartupLoadingIndicator
        self.pausesOnDisappear = pausesOnDisappear
        self.surfaceOverlay = surfaceOverlay
        self.controlsAccessory = controlsAccessory
        self.controlsCenterAccessory = controlsCenterAccessory
        self.topLeadingControlsAccessory = topLeadingControlsAccessory
        self.showsMoreControls = showsMoreControls
        self.controlLayout = controlLayout
        self.moreControlsContent = moreControlsContent
        self.replacesStandardMoreControls = replacesStandardMoreControls
        self.controlsBottomLift = controlsBottomLift
        self.controlsHorizontalInset = controlsHorizontalInset
        self.isDanmakuEnabled = isDanmakuEnabled
        self.onToggleDanmaku = onToggleDanmaku
        self.onShowDanmakuSettings = onShowDanmakuSettings
        self.isSecondaryControlsPresented = isSecondaryControlsPresented
        self.durationHint = durationHint
        self.embeddedAspectRatio = embeddedAspectRatio
        self.ignoresContainerSafeArea = ignoresContainerSafeArea
        self.keepsPlayerSurfaceStable = keepsPlayerSurfaceStable
        self.fullscreenMode = fullscreenMode
        self.isLayoutTransitioning = isLayoutTransitioning
        self.usesLiveSurfaceDuringLayoutTransition = usesLiveSurfaceDuringLayoutTransition
        self.disablesSurfaceImplicitLayoutAnimations = disablesSurfaceImplicitLayoutAnimations
        self.showsRotationTransitionSnapshot = showsRotationTransitionSnapshot
        self.onPrepareForUserSeek = onPrepareForUserSeek
        self.onRequestFullscreen = onRequestFullscreen
        self.onExitFullscreen = onExitFullscreen
        self.allowsPlaybackActivation = allowsPlaybackActivation
    }

}

import SwiftUI

enum BiliPlayerControlLayout: Equatable {
    case standard
    case live
    case livePiliPod

    var showsProgress: Bool { self == .standard }
    var showsPlaybackToggle: Bool { self == .standard || self == .livePiliPod }
    var showsTimeLabel: Bool { self == .standard }
    var isLive: Bool { self == .live || self == .livePiliPod }
}

struct BiliPlayerViewOptions {
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

    init(
        presentation: BiliPlayerPresentation = .fullScreen,
        showsNavigationChrome: Bool = true,
        showsPlaybackControls: Bool = true,
        allowsDoubleTapPlaybackToggle: Bool = true,
        showsStartupLoadingIndicator: Bool = true,
        pausesOnDisappear: Bool = true,
        surfaceOverlay: AnyView? = nil,
        controlsAccessory: AnyView? = nil,
        controlsCenterAccessory: AnyView? = nil,
        topLeadingControlsAccessory: AnyView? = nil,
        showsMoreControls: Bool = true,
        controlLayout: BiliPlayerControlLayout = .standard,
        moreControlsContent: AnyView? = nil,
        replacesStandardMoreControls: Bool = false,
        controlsBottomLift: CGFloat = 0,
        controlsHorizontalInset: CGFloat = 0,
        isDanmakuEnabled: Bool = true,
        onToggleDanmaku: (() -> Void)? = nil,
        onShowDanmakuSettings: (() -> Void)? = nil,
        isSecondaryControlsPresented: Bool = false,
        durationHint: TimeInterval? = nil,
        embeddedAspectRatio: CGFloat = 16 / 9,
        ignoresContainerSafeArea: Bool = true,
        keepsPlayerSurfaceStable: Bool = false,
        fullscreenMode: PlayerFullscreenMode? = nil,
        isLayoutTransitioning: Bool = false,
        usesLiveSurfaceDuringLayoutTransition: Bool = false,
        disablesSurfaceImplicitLayoutAnimations: Bool = false,
        showsRotationTransitionSnapshot: Bool = true,
        onPrepareForUserSeek: ((Double) -> Void)? = nil,
        onRequestFullscreen: (() -> Void)? = nil,
        onExitFullscreen: (() -> Void)? = nil,
        allowsPlaybackActivation: (() -> Bool)? = nil
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

    func configuration() -> BiliPlayerViewConfiguration {
        BiliPlayerViewConfiguration(
            presentation: presentation,
            showsNavigationChrome: showsNavigationChrome,
            showsPlaybackControls: showsPlaybackControls,
            allowsDoubleTapPlaybackToggle: allowsDoubleTapPlaybackToggle,
            showsStartupLoadingIndicator: showsStartupLoadingIndicator,
            pausesOnDisappear: pausesOnDisappear,
            surfaceOverlay: surfaceOverlay,
            controlsAccessory: controlsAccessory,
            controlsCenterAccessory: controlsCenterAccessory,
            topLeadingControlsAccessory: topLeadingControlsAccessory,
            showsMoreControls: showsMoreControls,
            controlLayout: controlLayout,
            moreControlsContent: moreControlsContent,
            replacesStandardMoreControls: replacesStandardMoreControls,
            controlsBottomLift: controlsBottomLift,
            controlsHorizontalInset: controlsHorizontalInset,
            isDanmakuEnabled: isDanmakuEnabled,
            onToggleDanmaku: onToggleDanmaku,
            onShowDanmakuSettings: onShowDanmakuSettings,
            isSecondaryControlsPresented: isSecondaryControlsPresented,
            durationHint: durationHint,
            embeddedAspectRatio: embeddedAspectRatio,
            ignoresContainerSafeArea: ignoresContainerSafeArea,
            keepsPlayerSurfaceStable: keepsPlayerSurfaceStable,
            fullscreenMode: fullscreenMode,
            isLayoutTransitioning: isLayoutTransitioning,
            usesLiveSurfaceDuringLayoutTransition: usesLiveSurfaceDuringLayoutTransition,
            disablesSurfaceImplicitLayoutAnimations: disablesSurfaceImplicitLayoutAnimations,
            showsRotationTransitionSnapshot: showsRotationTransitionSnapshot,
            onPrepareForUserSeek: onPrepareForUserSeek,
            onRequestFullscreen: onRequestFullscreen,
            onExitFullscreen: onExitFullscreen,
            allowsPlaybackActivation: allowsPlaybackActivation
        )
    }
}

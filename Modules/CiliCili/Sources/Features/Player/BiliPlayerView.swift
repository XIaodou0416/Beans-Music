import AVFoundation
import SwiftUI

struct BiliPlayerView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @EnvironmentObject private var libraryStore: LibraryStore
    @StateObject private var viewModelBox: PlayerViewModelBox
    @StateObject private var surfaceState: PlayerSurfaceStateModel
    @StateObject private var playbackControlsVisibility = PlayerPlaybackControlsVisibilityModel()
    @StateObject private var rotationTransitionSnapshotModel = PlayerRotationTransitionSnapshotModel()
    @StateObject private var seekTransitionSnapshotModel = PlayerRotationTransitionSnapshotModel()
    @StateObject private var appBackgroundRecoverySnapshotModel = PlayerRotationTransitionSnapshotModel()
    @StateObject private var speedBoostModel = PlayerSpeedBoostModel()
    @StateObject private var seekPreviewModel = PlayerSeekPreviewModel()
    @StateObject private var playbackProgressCoordinator = PlayerPlaybackProgressCoordinator()
    @State private var lastPreparedScrubProgress = -1.0
    @StateObject private var progressReporter = PlayerPlaybackProgressReporter()
    private let historyVideo: VideoItem?
    private let historyCID: Int?
    private let historyDuration: TimeInterval?
    private let configuration: BiliPlayerViewConfiguration
    private var viewModel: PlayerStateViewModel {
        viewModelBox.viewModel
    }

    private var runtimeContext: BiliPlayerViewRuntimeContext {
        BiliPlayerViewRuntimeContextBuilder(
            dependencies: dependencies,
            libraryStore: libraryStore,
            viewModel: viewModel,
            surfaceState: surfaceState,
            playbackControlsVisibility: playbackControlsVisibility,
            rotationTransitionSnapshotModel: rotationTransitionSnapshotModel,
            seekTransitionSnapshotModel: seekTransitionSnapshotModel,
            appBackgroundRecoverySnapshotModel: appBackgroundRecoverySnapshotModel,
            speedBoostModel: speedBoostModel,
            seekPreviewModel: seekPreviewModel,
            playbackProgressCoordinator: playbackProgressCoordinator,
            progressReporter: progressReporter,
            historyVideo: historyVideo,
            historyCID: historyCID,
            historyDuration: historyDuration,
            configuration: configuration,
            isPictureInPictureEnabled: libraryStore.pictureInPictureEnabled,
            videoGravity: videoGravity,
            holdCurrentFrameForSeek: holdCurrentFrameForSeek,
            prepareUserSeekWarmup: prepareUserSeekWarmupIfNeeded,
            resetPreparedScrubProgress: { lastPreparedScrubProgress = -1 }
        ).context
    }

    init(
        viewModel: PlayerStateViewModel,
        historyVideo: VideoItem? = nil,
        historyCID: Int? = nil,
        duration: TimeInterval? = nil,
        presentation: BiliPlayerPresentation = .fullScreen,
        showsNavigationChrome: Bool = true,
        showsPlaybackControls: Bool = true,
        showsStartupLoadingIndicator: Bool = true,
        pausesOnDisappear: Bool = true,
        surfaceOverlay: AnyView? = nil,
        controlsAccessory: AnyView? = nil,
        topLeadingControlsAccessory: AnyView? = nil,
        controlsBottomLift: CGFloat = 0,
        isDanmakuEnabled: Bool = true,
        onToggleDanmaku: (() -> Void)? = nil,
        onShowDanmakuSettings: (() -> Void)? = nil,
        isSecondaryControlsPresented: Bool = false,
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
        self.init(
            viewModel: viewModel,
            historyVideo: historyVideo,
            historyCID: historyCID,
            options: Self.makeOptions(
                presentation: presentation,
                showsNavigationChrome: showsNavigationChrome,
                showsPlaybackControls: showsPlaybackControls,
                showsStartupLoadingIndicator: showsStartupLoadingIndicator,
                pausesOnDisappear: pausesOnDisappear,
                surfaceOverlay: surfaceOverlay,
                controlsAccessory: controlsAccessory,
                topLeadingControlsAccessory: topLeadingControlsAccessory,
                controlsBottomLift: controlsBottomLift,
                isDanmakuEnabled: isDanmakuEnabled,
                onToggleDanmaku: onToggleDanmaku,
                onShowDanmakuSettings: onShowDanmakuSettings,
                isSecondaryControlsPresented: isSecondaryControlsPresented,
                durationHint: duration,
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
        )
    }

    init(
        videoURL: URL,
        title: String,
        referer: String = "https://www.bilibili.com",
        duration: TimeInterval? = nil,
        presentation: BiliPlayerPresentation = .fullScreen,
        showsNavigationChrome: Bool = true,
        showsPlaybackControls: Bool = true,
        showsStartupLoadingIndicator: Bool = true,
        pausesOnDisappear: Bool = true,
        surfaceOverlay: AnyView? = nil,
        controlsAccessory: AnyView? = nil,
        topLeadingControlsAccessory: AnyView? = nil,
        controlsBottomLift: CGFloat = 0,
        isDanmakuEnabled: Bool = true,
        onToggleDanmaku: (() -> Void)? = nil,
        onShowDanmakuSettings: (() -> Void)? = nil,
        isSecondaryControlsPresented: Bool = false,
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
        let playerViewModel = BiliPlayerViewModelFactory.makeDirectURLViewModel(
            videoURL: videoURL,
            title: title,
            referer: referer,
            duration: duration
        )
        self.init(
            viewModel: playerViewModel,
            historyVideo: nil,
            historyCID: nil,
            options: Self.makeOptions(
                presentation: presentation,
                showsNavigationChrome: showsNavigationChrome,
                showsPlaybackControls: showsPlaybackControls,
                showsStartupLoadingIndicator: showsStartupLoadingIndicator,
                pausesOnDisappear: pausesOnDisappear,
                surfaceOverlay: surfaceOverlay,
                controlsAccessory: controlsAccessory,
                topLeadingControlsAccessory: topLeadingControlsAccessory,
                controlsBottomLift: controlsBottomLift,
                isDanmakuEnabled: isDanmakuEnabled,
                onToggleDanmaku: onToggleDanmaku,
                onShowDanmakuSettings: onShowDanmakuSettings,
                isSecondaryControlsPresented: isSecondaryControlsPresented,
                durationHint: duration,
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
        )
    }

    init(
        playVariant: PlayVariant,
        title: String,
        referer: String = "https://www.bilibili.com",
        duration: TimeInterval? = nil,
        resumeTime: TimeInterval? = nil,
        historyVideo: VideoItem? = nil,
        historyCID: Int? = nil,
        presentation: BiliPlayerPresentation = .fullScreen,
        showsNavigationChrome: Bool = true,
        showsPlaybackControls: Bool = true,
        showsStartupLoadingIndicator: Bool = true,
        pausesOnDisappear: Bool = true,
        surfaceOverlay: AnyView? = nil,
        controlsAccessory: AnyView? = nil,
        topLeadingControlsAccessory: AnyView? = nil,
        controlsBottomLift: CGFloat = 0,
        isDanmakuEnabled: Bool = true,
        onToggleDanmaku: (() -> Void)? = nil,
        onShowDanmakuSettings: (() -> Void)? = nil,
        isSecondaryControlsPresented: Bool = false,
        embeddedAspectRatio: CGFloat = 16 / 9,
        ignoresContainerSafeArea: Bool = true,
        keepsPlayerSurfaceStable: Bool = false,
        cdnPreference: PlaybackCDNPreference = .automatic,
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
        let playerViewModel = BiliPlayerViewModelFactory.makePlayVariantViewModel(
            playVariant: playVariant,
            title: title,
            referer: referer,
            duration: duration,
            resumeTime: resumeTime,
            historyVideo: historyVideo,
            cdnPreference: cdnPreference
        )
        self.init(
            viewModel: playerViewModel,
            historyVideo: historyVideo,
            historyCID: historyCID,
            options: Self.makeOptions(
                presentation: presentation,
                showsNavigationChrome: showsNavigationChrome,
                showsPlaybackControls: showsPlaybackControls,
                showsStartupLoadingIndicator: showsStartupLoadingIndicator,
                pausesOnDisappear: pausesOnDisappear,
                surfaceOverlay: surfaceOverlay,
                controlsAccessory: controlsAccessory,
                topLeadingControlsAccessory: topLeadingControlsAccessory,
                controlsBottomLift: controlsBottomLift,
                isDanmakuEnabled: isDanmakuEnabled,
                onToggleDanmaku: onToggleDanmaku,
                onShowDanmakuSettings: onShowDanmakuSettings,
                isSecondaryControlsPresented: isSecondaryControlsPresented,
                durationHint: duration,
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
        )
    }

    init(
        viewModel: PlayerStateViewModel,
        historyVideo: VideoItem?,
        historyCID: Int?,
        options: BiliPlayerViewOptions
    ) {
        self.init(
            viewModel: viewModel,
            historyVideo: historyVideo,
            historyCID: historyCID,
            historyDuration: historyVideo?.duration.map(TimeInterval.init),
            configuration: options.configuration()
        )
    }

    private init(
        viewModel: PlayerStateViewModel,
        historyVideo: VideoItem?,
        historyCID: Int?,
        historyDuration: TimeInterval?,
        configuration: BiliPlayerViewConfiguration
    ) {
        self.historyVideo = historyVideo
        self.historyCID = historyCID
        self.historyDuration = historyDuration
        self.configuration = configuration
        _viewModelBox = StateObject(wrappedValue: PlayerViewModelBox(viewModel: viewModel))
        _surfaceState = StateObject(wrappedValue: PlayerSurfaceStateModel(viewModel: viewModel))
    }

    var body: some View {
        let context = runtimeContext

        BiliPlayerViewHost(
            playerSurface: BiliPlayerViewRenderer(context: context.renderContext),
            title: viewModel.title,
            configuration: configuration,
            isPictureInPictureEnabled: libraryStore.pictureInPictureEnabled,
            lifecycleActions: context.lifecycleActions
        )
        .onChange(of: surfaceState.isUserSeeking) { _, isUserSeeking in
            updateSeekTransitionSnapshot(isUserSeeking: isUserSeeking)
        }
    }

    private var videoGravity: AVLayerVideoGravity {
        .resizeAspect
    }

    private static func makeOptions(
        presentation: BiliPlayerPresentation,
        showsNavigationChrome: Bool,
        showsPlaybackControls: Bool,
        showsStartupLoadingIndicator: Bool,
        pausesOnDisappear: Bool,
        surfaceOverlay: AnyView?,
        controlsAccessory: AnyView?,
        topLeadingControlsAccessory: AnyView?,
        controlsBottomLift: CGFloat,
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
    ) -> BiliPlayerViewOptions {
        BiliPlayerViewOptions(
            presentation: presentation,
            showsNavigationChrome: showsNavigationChrome,
            showsPlaybackControls: showsPlaybackControls,
            showsStartupLoadingIndicator: showsStartupLoadingIndicator,
            pausesOnDisappear: pausesOnDisappear,
            surfaceOverlay: surfaceOverlay,
            controlsAccessory: controlsAccessory,
            topLeadingControlsAccessory: topLeadingControlsAccessory,
            controlsBottomLift: controlsBottomLift,
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

    private func prepareUserSeekWarmupIfNeeded(_ progress: Double, force: Bool = false) {
        let clampedProgress = min(max(progress, 0), 1)
        guard force || abs(clampedProgress - lastPreparedScrubProgress) >= 0.008 else { return }
        lastPreparedScrubProgress = clampedProgress
        configuration.onPrepareForUserSeek?(clampedProgress)
    }

    private func holdCurrentFrameForSeek() {
        seekTransitionSnapshotModel.hold(
            hasPresentedPlayback: surfaceState.hasPresentedPlayback,
            surfaceLayoutGeneration: viewModel.surfaceLayoutGeneration
        ) {
            viewModel.makePlaybackTransitionSnapshot()
        }
    }

    private func updateSeekTransitionSnapshot(isUserSeeking: Bool) {
        if isUserSeeking {
            guard viewModel.shouldHoldSeekSnapshotAtInteractionStart else { return }
            holdCurrentFrameForSeek()
        } else {
            seekTransitionSnapshotModel.releaseForSeekTransition(
                isReadyForReveal: {
                    viewModel.isSeekRecoverySnapshotReadyForReveal()
                },
                onReleased: {
                    viewModel.finishUserSeekVisualReveal()
                }
            )
        }
    }
}

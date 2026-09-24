import AVFoundation
import Combine
import SwiftUI
import UIKit

/// 直播播放器的正式视频层协调入口。
/// SwiftUI 仍拥有直播详情内容与控件，UIKit 只托管稳定的 player surface 容器。
struct LiveRoomSurfaceCoordinatorView: UIViewControllerRepresentable {
    @ObservedObject var viewModel: LiveRoomViewModel
    let playbackSession: PlaybackSession
    let dependencies: AppDependencies
    let usesLandscapeChrome: Bool
    let usesPortraitFullscreen: Bool
    let onRequestFullscreen: (PlayerStateViewModel?) -> Void
    let onExitFullscreen: (PlayerStateViewModel?) -> Void

    func makeUIViewController(context _: Context) -> LiveRoomSurfaceCoordinatorViewController {
        LiveRoomSurfaceCoordinatorViewController(
            viewModel: viewModel,
            playbackSession: playbackSession,
            dependencies: dependencies,
            usesLandscapeChrome: usesLandscapeChrome,
            usesPortraitFullscreen: usesPortraitFullscreen,
            onRequestFullscreen: onRequestFullscreen,
            onExitFullscreen: onExitFullscreen
        )
    }

    func updateUIViewController(
        _ viewController: LiveRoomSurfaceCoordinatorViewController,
        context _: Context
    ) {
        viewController.update(
            playbackSession: playbackSession,
            usesLandscapeChrome: usesLandscapeChrome,
            usesPortraitFullscreen: usesPortraitFullscreen
        )
    }
}

@MainActor
final class LiveRoomSurfaceCoordinatorViewController: UIViewController {
    private let viewModel: LiveRoomViewModel
    private let dependencies: AppDependencies
    private let onRequestFullscreen: (PlayerStateViewModel?) -> Void
    private let onExitFullscreen: (PlayerStateViewModel?) -> Void
    private let playerContainer = UIView()
    private var playbackSession: PlaybackSession
    private var usesLandscapeChrome: Bool
    private var usesPortraitFullscreen: Bool

    private lazy var surfaceController: PlayerSurfaceController = {
        PlayerSurfaceController(
            parentViewController: self,
            containerView: playerContainer,
            makeHost: { [weak self] playerViewModel in
                guard let self else { return nil }
                return LiveRoomSurfaceHost(
                    playerViewModel: playerViewModel,
                    viewModel: self.viewModel,
                    dependencies: self.dependencies,
                    onRequestFullscreen: self.onRequestFullscreen,
                    onExitFullscreen: self.onExitFullscreen
                )
            }
        )
    }()

    init(
        viewModel: LiveRoomViewModel,
        playbackSession: PlaybackSession,
        dependencies: AppDependencies,
        usesLandscapeChrome: Bool,
        usesPortraitFullscreen: Bool,
        onRequestFullscreen: @escaping (PlayerStateViewModel?) -> Void,
        onExitFullscreen: @escaping (PlayerStateViewModel?) -> Void
    ) {
        self.viewModel = viewModel
        self.playbackSession = playbackSession
        self.dependencies = dependencies
        self.usesLandscapeChrome = usesLandscapeChrome
        self.usesPortraitFullscreen = usesPortraitFullscreen
        self.onRequestFullscreen = onRequestFullscreen
        self.onExitFullscreen = onExitFullscreen
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        playerContainer.backgroundColor = .black
        view.addSubview(playerContainer)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerContainer.frame = view.bounds
        bindSurface()
    }

    func update(
        playbackSession: PlaybackSession,
        usesLandscapeChrome: Bool,
        usesPortraitFullscreen: Bool
    ) {
        self.playbackSession = playbackSession
        self.usesLandscapeChrome = usesLandscapeChrome
        self.usesPortraitFullscreen = usesPortraitFullscreen
        guard isViewLoaded else { return }
        bindSurface()
    }

    private func bindSurface() {
        let layout = PlayerSurfaceLayout(
            frame: playerContainer.bounds,
            videoAspectRatio: 16.0 / 9.0,
            videoGravity: .resizeAspect,
            usesLandscapeChrome: usesLandscapeChrome,
            usesPortraitFullscreen: usesPortraitFullscreen,
            isTransitioning: false
        )
        surfaceController.bind(to: playbackSession, layout: layout)
    }
}

@MainActor
final class LiveRoomSurfaceHost: UIView, PlayerSurfaceHosting {
    @MainActor
    final class State: ObservableObject {
        @Published var playerViewModel: PlayerStateViewModel
        @Published var usesLandscapeChrome = false
        @Published var isPortraitFullscreen = false
        @Published var isBareSurfaceTransitionActive = false
        @Published var retainsChromeDuringBareSurfaceTransition = false
        @Published var videoAspectRatio: CGFloat = 16.0 / 9.0

        init(playerViewModel: PlayerStateViewModel) {
            self.playerViewModel = playerViewModel
        }

        func setBareSurfaceTransitionActive(_ active: Bool, retainsChromeTree: Bool) {
            if active {
                retainsChromeDuringBareSurfaceTransition = retainsChromeTree
                isBareSurfaceTransitionActive = true
            } else {
                isBareSurfaceTransitionActive = false
                retainsChromeDuringBareSurfaceTransition = false
            }
        }
    }

    private let state: State
    private let rotationStabilityState: LiveRotationSurfaceAlignmentState
    private let danmakuOverlayState: LiveDanmakuOverlayState
    private var videoGravity: AVLayerVideoGravity = .resizeAspect
    // Keep the decoded video layer out of the SwiftUI player tree. The live
    // overlay may change during rotation, but the surface itself stays owned by UIKit.
    private let surfaceHostView: UIKitPlayerSurfaceHostView
    private let overlayHostingController: UIHostingController<LiveRoomSurfaceRoot>
    private var cancellables = Set<AnyCancellable>()
    private var rotationChromePrewarmGeneration = 0
    private var isRotationChromePrewarming = false
    private var rotationChromePrewarmOriginalLandscape: Bool?

    init(
        playerViewModel: PlayerStateViewModel,
        viewModel: LiveRoomViewModel,
        dependencies: AppDependencies,
        onRequestFullscreen: @escaping (PlayerStateViewModel?) -> Void,
        onExitFullscreen: @escaping (PlayerStateViewModel?) -> Void,
        onNavigateBack: @escaping () -> Void = {}
    ) {
        let state = State(playerViewModel: playerViewModel)
        let rotationStabilityState = viewModel.liveRotationSurfaceAlignmentState
        let danmakuOverlayState = LiveDanmakuOverlayState(
            store: viewModel.liveDanmakuRenderStore,
            rotationState: rotationStabilityState
        )
        self.state = state
        self.rotationStabilityState = rotationStabilityState
        self.danmakuOverlayState = danmakuOverlayState
        self.surfaceHostView = UIKitPlayerSurfaceHostView(
            viewModel: playerViewModel,
            isPictureInPictureEnabled: dependencies.libraryStore.pictureInPictureEnabled
        )
        self.overlayHostingController = UIHostingController(
            rootView: LiveRoomSurfaceRoot(
                state: state,
                danmakuOverlayState: danmakuOverlayState,
                viewModel: viewModel,
                dependencies: dependencies,
                onRequestFullscreen: onRequestFullscreen,
                onExitFullscreen: onExitFullscreen,
                onNavigateBack: onNavigateBack
            )
        )
        super.init(frame: .zero)

        backgroundColor = .black
        surfaceHostView.translatesAutoresizingMaskIntoConstraints = false
        surfaceHostView.isUserInteractionEnabled = false
        overlayHostingController.view.backgroundColor = .clear
        overlayHostingController.view.isOpaque = false
        if #available(iOS 16.4, *) {
            overlayHostingController.safeAreaRegions = []
        }
        overlayHostingController.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(surfaceHostView)
        addSubview(overlayHostingController.view)
        NSLayoutConstraint.activate([
            surfaceHostView.leadingAnchor.constraint(equalTo: leadingAnchor),
            surfaceHostView.trailingAnchor.constraint(equalTo: trailingAnchor),
            surfaceHostView.topAnchor.constraint(equalTo: topAnchor),
            surfaceHostView.bottomAnchor.constraint(equalTo: bottomAnchor),
            overlayHostingController.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlayHostingController.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            overlayHostingController.view.topAnchor.constraint(equalTo: topAnchor),
            overlayHostingController.view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        dependencies.libraryStore.$pictureInPictureEnabled
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] isEnabled in
                self?.surfaceHostView.setPictureInPictureEnabled(isEnabled)
            }
            .store(in: &cancellables)

    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var surfaceView: UIView { self }

    func attach(to parent: UIViewController) {
        surfaceHostView.attach(to: parent)
        parent.addChild(overlayHostingController)
        overlayHostingController.didMove(toParent: parent)
    }

    func setPlayerViewModel(_ playerViewModel: PlayerStateViewModel) {
        guard state.playerViewModel !== playerViewModel else { return }
        state.playerViewModel = playerViewModel
        surfaceHostView.setPlayerViewModel(playerViewModel)
        playerViewModel.setVideoGravity(videoGravity)
    }

    func setVideoGravity(_ gravity: AVLayerVideoGravity) {
        guard videoGravity != gravity else { return }
        videoGravity = gravity
        surfaceHostView.setVideoGravity(gravity)
    }

    func setVideoAspectRatio(_ aspectRatio: CGFloat) {
        guard aspectRatio > 0.1,
              abs(state.videoAspectRatio - aspectRatio) > 0.001
        else { return }
        state.videoAspectRatio = aspectRatio
    }

    func setLandscape(_ landscape: Bool) {
        guard state.usesLandscapeChrome != landscape else { return }
        state.usesLandscapeChrome = landscape
    }

    func setPortraitFullscreen(_ active: Bool) {
        guard state.isPortraitFullscreen != active else { return }
        state.isPortraitFullscreen = active
    }

    func setBareSurfaceTransitionActive(_ active: Bool, retainsChromeTree: Bool) {
        cancelRotationChromePrewarm()
        if active {
            // Keeping an invisible SwiftUI tree in the compositor still costs
            // a layout/render pass on every rotation frame. Hide it without
            // removing it so the already-built controls remain reusable.
            UIView.performWithoutAnimation {
                overlayHostingController.view.isHidden = true
                overlayHostingController.view.isUserInteractionEnabled = false
            }
        }
        state.setBareSurfaceTransitionActive(active, retainsChromeTree: retainsChromeTree)
        danmakuOverlayState.setUpdatesDeferred(active)
        rotationStabilityState.setBareSurfaceTransitionActive(active)
        if !active {
            UIView.performWithoutAnimation {
                overlayHostingController.view.isHidden = false
                overlayHostingController.view.isUserInteractionEnabled = true
            }
        }
    }

    func prewarmRotationChrome() {
        guard !isRotationChromePrewarming,
              !state.isBareSurfaceTransitionActive
        else { return }
        isRotationChromePrewarming = true
        rotationChromePrewarmGeneration &+= 1
        let generation = rotationChromePrewarmGeneration
        let originalLandscape = state.usesLandscapeChrome
        rotationChromePrewarmOriginalLandscape = originalLandscape

        UIView.performWithoutAnimation {
            state.setBareSurfaceTransitionActive(
                true,
                retainsChromeTree: true
            )
            state.usesLandscapeChrome = !originalLandscape
        }
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.isRotationChromePrewarming,
                  self.rotationChromePrewarmGeneration == generation
            else { return }
            self.layoutRotationChromePrewarm()
            UIView.performWithoutAnimation {
                self.state.usesLandscapeChrome = originalLandscape
            }
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.isRotationChromePrewarming,
                      self.rotationChromePrewarmGeneration == generation
                else { return }
                self.layoutRotationChromePrewarm()
                UIView.performWithoutAnimation {
                    self.state.setBareSurfaceTransitionActive(false, retainsChromeTree: false)
                }
                self.isRotationChromePrewarming = false
                self.rotationChromePrewarmOriginalLandscape = nil
            }
        }
    }

    func cancelRotationChromePrewarm() {
        guard isRotationChromePrewarming else { return }
        rotationChromePrewarmGeneration &+= 1
        isRotationChromePrewarming = false
        let originalLandscape = rotationChromePrewarmOriginalLandscape
        rotationChromePrewarmOriginalLandscape = nil
        UIView.performWithoutAnimation {
            if let originalLandscape {
                state.usesLandscapeChrome = originalLandscape
            }
            state.setBareSurfaceTransitionActive(false, retainsChromeTree: false)
        }
    }

    func refreshLayoutImmediately() {
        UIView.performWithoutAnimation {
            setNeedsLayout()
            layoutIfNeeded()
            surfaceHostView.refreshLayoutImmediately()
            guard !state.isBareSurfaceTransitionActive else { return }
            overlayHostingController.view.setNeedsLayout()
            overlayHostingController.view.layoutIfNeeded()
        }
    }

    private func layoutRotationChromePrewarm() {
        overlayHostingController.view.setNeedsLayout()
        overlayHostingController.view.layoutIfNeeded()
    }
}

private struct LiveRoomSurfaceRoot: View {
    @ObservedObject var state: LiveRoomSurfaceHost.State
    @ObservedObject var danmakuOverlayState: LiveDanmakuOverlayState
    @ObservedObject var viewModel: LiveRoomViewModel
    let dependencies: AppDependencies
    let onRequestFullscreen: (PlayerStateViewModel?) -> Void
    let onExitFullscreen: (PlayerStateViewModel?) -> Void
    let onNavigateBack: () -> Void

    var body: some View {
        LiveRoomSurfaceOnlyOverlay(
            playerViewModel: state.playerViewModel,
            state: state,
            danmakuOverlayState: danmakuOverlayState,
            viewModel: viewModel,
            dependencies: dependencies,
            onRequestFullscreen: onRequestFullscreen,
            onExitFullscreen: onExitFullscreen,
            onNavigateBack: onNavigateBack
        )
        .id(ObjectIdentifier(state.playerViewModel))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .ignoresSafeArea()
        .sheet(isPresented: $viewModel.isShowingLivePlaybackDiagnostics) {
            LivePlaybackDiagnosticsSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isShowingLiveDanmakuSettings) {
            LiveDanmakuSettingsSheet(viewModel: viewModel)
        }
    }
}

/// The native video surface lives below this view. This root owns only the
/// SwiftUI interaction, controls, loading chrome and live danmaku layers.
private struct LiveRoomSurfaceOnlyOverlay: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @ObservedObject var playerViewModel: PlayerStateViewModel
    @ObservedObject var state: LiveRoomSurfaceHost.State
    @ObservedObject var danmakuOverlayState: LiveDanmakuOverlayState
    @ObservedObject var viewModel: LiveRoomViewModel
    @ObservedObject private var libraryStore: LibraryStore

    let dependencies: AppDependencies
    let onRequestFullscreen: (PlayerStateViewModel?) -> Void
    let onExitFullscreen: (PlayerStateViewModel?) -> Void
    let onNavigateBack: () -> Void

    @StateObject private var surfaceState: PlayerSurfaceStateModel
    @StateObject private var playbackControlsVisibility = PlayerPlaybackControlsVisibilityModel()
    @StateObject private var rotationTransitionSnapshotModel = PlayerRotationTransitionSnapshotModel()
    @StateObject private var seekTransitionSnapshotModel = PlayerRotationTransitionSnapshotModel()
    @StateObject private var appBackgroundRecoverySnapshotModel = PlayerRotationTransitionSnapshotModel()
    @StateObject private var speedBoostModel = PlayerSpeedBoostModel()
    @StateObject private var seekPreviewModel = PlayerSeekPreviewModel()
    @StateObject private var playbackProgressCoordinator = PlayerPlaybackProgressCoordinator()
    @StateObject private var progressReporter = PlayerPlaybackProgressReporter()
    @State private var lastPreparedScrubProgress = -1.0

    init(
        playerViewModel: PlayerStateViewModel,
        state: LiveRoomSurfaceHost.State,
        danmakuOverlayState: LiveDanmakuOverlayState,
        viewModel: LiveRoomViewModel,
        dependencies: AppDependencies,
        onRequestFullscreen: @escaping (PlayerStateViewModel?) -> Void,
        onExitFullscreen: @escaping (PlayerStateViewModel?) -> Void,
        onNavigateBack: @escaping () -> Void
    ) {
        self.playerViewModel = playerViewModel
        self.state = state
        self.danmakuOverlayState = danmakuOverlayState
        self.viewModel = viewModel
        self.libraryStore = dependencies.libraryStore
        self.dependencies = dependencies
        self.onRequestFullscreen = onRequestFullscreen
        self.onExitFullscreen = onExitFullscreen
        self.onNavigateBack = onNavigateBack
        _surfaceState = StateObject(wrappedValue: PlayerSurfaceStateModel(viewModel: playerViewModel))
    }

    var body: some View {
        let context = runtimeContext
        let renderContext = context.renderContext
        let renderState = BiliPlayerViewRenderState(
            context: renderContext,
            verticalSizeClass: verticalSizeClass
        )
        let visibilityActions = renderState.visibilityActions
        let speedActions = renderState.speedBoostActions
        let nativeActions = BiliPlayerNativeControlsActionBuilder(
            viewModel: playerViewModel,
            configuration: renderContext.configuration,
            visibilityActions: visibilityActions,
            seekPreviewModel: renderContext.seekPreviewModel,
            seekPreviewAPI: renderContext.seekPreviewAPI,
            seekPreviewContext: renderContext.seekPreviewContext,
            holdCurrentFrameForSeek: holdCurrentFrameForSeek,
            prepareUserSeekWarmup: prepareUserSeekWarmupIfNeeded,
            resetPreparedScrubProgress: { lastPreparedScrubProgress = -1 }
        ).actions
        let chromeState = surfaceChromeState(
            context: renderContext,
            renderState: renderState
        )

        ZStack {
            if keepsChromeMounted {
                Group {
                    BiliPlayerSurfaceGestureLayerHost(
                        content: Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity),
                        visibilityActions: visibilityActions,
                        speedBoostActions: speedActions,
                        viewModel: playerViewModel,
                        allowsDoubleTapPlaybackToggle: configuration.allowsDoubleTapPlaybackToggle,
                        seekPreviewModel: renderContext.seekPreviewModel,
                        seekPreviewAPI: renderContext.seekPreviewAPI,
                        seekPreviewContext: renderContext.seekPreviewContext,
                        holdCurrentFrameForSeek: holdCurrentFrameForSeek,
                        prepareUserSeekWarmup: prepareUserSeekWarmupIfNeeded,
                        resetPreparedScrubProgress: { lastPreparedScrubProgress = -1 }
                    )
                    .zIndex(1)

                    BiliPlayerSurfaceOverlayLayer(
                        state: chromeState,
                        speedBoostModel: renderContext.speedBoostModel,
                        seekPreviewModel: renderContext.seekPreviewModel
                    )
                    .zIndex(2)

                    BiliPlayerControlsOverlayLayer(
                        state: chromeState,
                        playbackControls: AnyView(
                            BiliPlayerNativeControlsHost(
                                context: renderContext,
                                renderState: renderState,
                                actions: nativeActions
                            )
                        )
                    )
                    .zIndex(3)
                }
                .opacity(state.isBareSurfaceTransitionActive ? 0 : 1)
                .allowsHitTesting(!state.isBareSurfaceTransitionActive)
            }

            LiveDanmakuOverlay(
                state: danmakuOverlayState,
                playerViewModel: playerViewModel,
                usesLandscapeChrome: state.usesLandscapeChrome,
                isLayoutTransitioning: state.isBareSurfaceTransitionActive,
                videoAspectRatio: state.videoAspectRatio
            )
            .allowsHitTesting(false)
            .zIndex(2.5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .background {
            PlaybackDetailPlayerReadinessProbe(
                playerViewModel: playerViewModel,
                context: .live(roomID: viewModel.roomID, title: viewModel.title)
            )
        }
        .environmentObject(dependencies)
        .environmentObject(libraryStore)
        .environment(\.appThemeTintColor, libraryStore.appTintColor)
        .environment(\.playerNativeControlMetrics, renderState.controlMetrics)
        .biliPlayerLifecycle(
            isFullscreenActive: configuration.isFullscreenActive,
            presentation: configuration.presentation,
            isLayoutTransitioning: configuration.isLayoutTransitioning,
            isSecondaryControlsPresented: configuration.isSecondaryControlsPresented,
            isPictureInPictureEnabled: libraryStore.pictureInPictureEnabled,
            actions: context.lifecycleActions
        )
        .onChange(of: state.isBareSurfaceTransitionActive) { _, isActive in
            if isActive {
                playbackControlsVisibility.cancelAutoHide()
            }
        }
        .onChange(of: surfaceState.isUserSeeking) { _, isUserSeeking in
            updateSeekTransitionSnapshot(isUserSeeking: isUserSeeking)
        }
    }

    private var fullscreenMode: PlayerFullscreenMode? {
        if state.isPortraitFullscreen {
            return .portrait
        }
        if state.usesLandscapeChrome {
            return .landscape(.landscapeRight)
        }
        return nil
    }

    private var supportsFullscreen: Bool {
        LiveRoomVideoDetailLayoutPolicy.supportsFullscreen(
            videoAspectRatio: state.videoAspectRatio
        )
    }

    private var keepsChromeMounted: Bool {
        !state.isBareSurfaceTransitionActive
            || state.retainsChromeDuringBareSurfaceTransition
    }

    private var configuration: BiliPlayerViewConfiguration {
        BiliPlayerViewOptions(
            presentation: fullscreenMode == nil ? .embedded : .fullScreen,
            showsNavigationChrome: false,
            showsPlaybackControls: keepsChromeMounted,
            allowsDoubleTapPlaybackToggle: true,
            showsStartupLoadingIndicator: keepsChromeMounted,
            pausesOnDisappear: false,
            controlsAccessory: keepsChromeMounted
                ? liveControlsAccessory
                : nil,
            controlsCenterAccessory: nil,
            topLeadingControlsAccessory: keepsChromeMounted
                ? topLeadingControlsAccessory : nil,
            showsMoreControls: false,
            controlLayout: .livePiliPod,
            moreControlsContent: AnyView(
                LivePlayerMoreControlsContent(viewModel: viewModel)
            ),
            replacesStandardMoreControls: true,
            controlsBottomLift: 0,
            controlsHorizontalInset: 0,
            isDanmakuEnabled: viewModel.isDanmakuEnabled,
            onShowDanmakuSettings: {
                viewModel.showLiveDanmakuSettings()
            },
            keepsPlayerSurfaceStable: true,
            fullscreenMode: fullscreenMode,
            isLayoutTransitioning: state.isBareSurfaceTransitionActive,
            usesLiveSurfaceDuringLayoutTransition: true,
            disablesSurfaceImplicitLayoutAnimations: true,
            showsRotationTransitionSnapshot: false,
            onRequestFullscreen: supportsFullscreen ? {
                onRequestFullscreen(playerViewModel)
            } : nil,
            onExitFullscreen: {
                onExitFullscreen(playerViewModel)
            }
        ).configuration()
    }

    private var topLeadingControlsAccessory: AnyView? {
        guard state.usesLandscapeChrome || state.isPortraitFullscreen else { return nil }
        return AnyView(
            LivePlayerSimpleLiveFullscreenHeader(viewModel: viewModel) {
                onExitFullscreen(playerViewModel)
            }
        )
    }

    private var liveControlsAccessory: AnyView {
        AnyView(LivePlayerSimpleLiveAccessory(viewModel: viewModel))
    }

    private var runtimeContext: BiliPlayerViewRuntimeContext {
        BiliPlayerViewRuntimeContextBuilder(
            dependencies: dependencies,
            libraryStore: libraryStore,
            viewModel: playerViewModel,
            surfaceState: surfaceState,
            playbackControlsVisibility: playbackControlsVisibility,
            rotationTransitionSnapshotModel: rotationTransitionSnapshotModel,
            seekTransitionSnapshotModel: seekTransitionSnapshotModel,
            appBackgroundRecoverySnapshotModel: appBackgroundRecoverySnapshotModel,
            speedBoostModel: speedBoostModel,
            seekPreviewModel: seekPreviewModel,
            playbackProgressCoordinator: playbackProgressCoordinator,
            progressReporter: progressReporter,
            historyVideo: nil,
            historyCID: nil,
            historyDuration: nil,
            configuration: configuration,
            isPictureInPictureEnabled: libraryStore.pictureInPictureEnabled,
            videoGravity: .resizeAspect,
            holdCurrentFrameForSeek: holdCurrentFrameForSeek,
            prepareUserSeekWarmup: prepareUserSeekWarmupIfNeeded,
            resetPreparedScrubProgress: { lastPreparedScrubProgress = -1 }
        ).context
    }

    private func surfaceChromeState(
        context: BiliPlayerViewRenderContext,
        renderState: BiliPlayerViewRenderState
    ) -> BiliPlayerSurfaceChromeState {
        BiliPlayerSurfaceChromeState(
            presentation: context.configuration.presentation,
            surfaceOverlay: nil,
            rotationSnapshot: nil,
            seekSnapshot: seekTransitionSnapshotModel.snapshot,
            appBackgroundRecoverySnapshot: appBackgroundRecoverySnapshotModel.snapshot,
            rotationFallbackCoverURL: nil,
            rotationSnapshotOpacity: 0,
            seekSnapshotOpacity: seekTransitionSnapshotModel.opacity,
            appBackgroundRecoverySnapshotOpacity: appBackgroundRecoverySnapshotModel.opacity,
            constrainsRotationSnapshotToVideoAspect: false,
            showsPlayerLoadingChrome: renderState.showsPlayerLoadingChrome,
            isBuffering: context.surfaceState.isBuffering,
            isPlaying: context.surfaceState.isPlaying,
            hasPresentedPlayback: context.surfaceState.hasPresentedPlayback,
            showsInlineLoadingProgress: renderState.showsInlineLoadingProgress,
            isUserSeeking: context.surfaceState.isUserSeeking,
            showsActivePlaybackControls: renderState.showsActivePlaybackControls,
            playbackControlsOpacity: playbackControlsVisibility.opacity,
            playbackControlsAllowsHitTesting: playbackControlsVisibility.acceptsHitTesting,
            topLeadingControlsAccessory: context.configuration.topLeadingControlsAccessory,
            topCenterControlsAccessory: nil,
            topTrailingControlsAccessory: nil,
            isFullscreenActive: context.configuration.isFullscreenActive,
            controlsBottomLift: context.configuration.controlsBottomLift,
            controlsHorizontalInset: context.configuration.controlsHorizontalInset,
            contentInsets: EdgeInsets(),
            errorMessage: context.surfaceState.errorMessage
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
            surfaceLayoutGeneration: playerViewModel.surfaceLayoutGeneration
        ) {
            playerViewModel.makePlaybackTransitionSnapshot()
        }
    }

    private func updateSeekTransitionSnapshot(isUserSeeking: Bool) {
        if isUserSeeking {
            holdCurrentFrameForSeek()
        } else {
            seekTransitionSnapshotModel.releaseForSeekTransition(
                isReadyForReveal: {
                    playerViewModel.isSeekRecoverySnapshotReadyForReveal()
                },
                onReleased: {
                    playerViewModel.finishUserSeekVisualReveal()
                }
            )
        }
    }
}

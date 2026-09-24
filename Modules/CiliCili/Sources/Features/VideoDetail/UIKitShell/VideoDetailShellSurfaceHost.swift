import AVFoundation
import Combine
import SwiftUI
import UIKit

/// 详情页 UIKit 外壳：播放器宿主（surface-only + 独立控件浮层）。
///
/// 对齐原型：UIKit 容器只驱动 frame，SwiftUI 根视图里直接铺 `VideoSurfaceView`，
/// 控件/手势/加载态作为 overlay 叠上去，不再让完整 `BiliPlayerView` 的
/// presentation 切换参与旋转。
@MainActor
final class VideoDetailShellSurfaceHost: UIView {
    @MainActor
    final class State: ObservableObject {
        @Published var isBareSurfaceTransitionActive = false
        @Published var retainsChromeDuringBareSurfaceTransition = false
        @Published var isCollapsedChromeActive = false
        @Published var playbackControlsHideRequestGeneration = 0
        @Published var playerViewModel: PlayerStateViewModel
        @Published var videoAspectRatio: CGFloat = 16.0 / 9.0

        init(playerViewModel: PlayerStateViewModel) {
            self.playerViewModel = playerViewModel
        }

        func setBareSurfaceTransitionActive(_ active: Bool, retainsChromeTree: Bool) {
            if active {
                // 保留控件树时，先设标志再进入 bare state，避免 SwiftUI 删除子树。
                retainsChromeDuringBareSurfaceTransition = retainsChromeTree
                isBareSurfaceTransitionActive = true
            } else {
                // 先退出 bare state，再清标志，保证控件树连续存在。
                isBareSurfaceTransitionActive = false
                retainsChromeDuringBareSurfaceTransition = false
            }
        }

        func requestPlaybackControlsHideForRotation() {
            playbackControlsHideRequestGeneration &+= 1
        }
    }

    private let state: State
    private let overlayState: VideoDetailShellOverlayState
    private let experimentState: VideoDetailPerformanceExperimentState
    private let libraryStore: LibraryStore
    private let rotationCoordinator: PlaybackRotationCoordinator
    private let surfaceHostView: any VideoDetailPlayerSurfaceHostingView
    private let overlayHostingController: UIHostingController<PlayerOverlayHostRoot>
    private var cancellables = Set<AnyCancellable>()
    private var rotationChromePrewarmGeneration = 0
    private var isRotationChromePrewarming = false
    private(set) var isRotationChromePrewarmed = false
    private(set) var isTornDown = false

    init(
        playerViewModel: PlayerStateViewModel,
        detailViewModel: VideoDetailViewModel,
        dependencies: AppDependencies,
        runtimeSettings: VideoDetailRuntimeSettingsStore,
        rotationCoordinator: PlaybackRotationCoordinator,
        onShowMoreControls: @escaping (@escaping () -> Void) -> Void,
        onDismissMoreControls: @escaping () -> Void,
        onRequestFullscreen: @escaping () -> Void,
        onExitFullscreen: @escaping () -> Void,
        onToggleDanmaku: @escaping () -> Void,
        onShowDanmakuSettings: @escaping () -> Void,
        onNavigateBack: @escaping () -> Void
    ) {
        let state = State(playerViewModel: playerViewModel)
        let experimentState = VideoDetailPerformanceExperimentState(
            directUIKitSurfaceEnabled: true,
            narrowPlayerOverlayObservationEnabled: true
        )
        let overlayState = VideoDetailShellOverlayState(
            detailViewModel: detailViewModel,
            experimentState: experimentState
        )
        self.state = state
        self.overlayState = overlayState
        self.experimentState = experimentState
        self.libraryStore = dependencies.libraryStore
        self.rotationCoordinator = rotationCoordinator
        self.surfaceHostView = VideoDetailSwiftUISurfaceHostingView(
            viewModel: playerViewModel,
            isPictureInPictureEnabled: dependencies.libraryStore.pictureInPictureEnabled
                && !playerViewModel.isAudioOnlyPlayback
        )
        let overlayRoot = PlayerOverlayHostRoot(
            detailViewModel: detailViewModel,
            state: state,
            rotationCoordinator: rotationCoordinator,
            overlayState: overlayState,
            experimentState: experimentState,
            runtimeSettings: runtimeSettings,
            usesNarrowObservation: true,
            dependencies: dependencies,
            onShowMoreControls: onShowMoreControls,
            onDismissMoreControls: onDismissMoreControls,
            onRequestFullscreen: onRequestFullscreen,
            onExitFullscreen: onExitFullscreen,
            onToggleDanmaku: onToggleDanmaku,
            onShowDanmakuSettings: onShowDanmakuSettings,
            onNavigateBack: onNavigateBack
        )
        self.overlayHostingController = UIHostingController(rootView: overlayRoot)
        super.init(frame: .zero)

        backgroundColor = .black
        overlayHostingController.view.backgroundColor = .clear
        overlayHostingController.view.isOpaque = false
        overlayHostingController.view.isUserInteractionEnabled = true
        if #available(iOS 16.4, *) {
            overlayHostingController.safeAreaRegions = []
        }
        let hostedSurfaceView = surfaceHostView.hostedView
        hostedSurfaceView.translatesAutoresizingMaskIntoConstraints = false
        hostedSurfaceView.isUserInteractionEnabled = false
        overlayHostingController.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostedSurfaceView)
        addSubview(overlayHostingController.view)
        NSLayoutConstraint.activate([
            hostedSurfaceView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostedSurfaceView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostedSurfaceView.topAnchor.constraint(equalTo: topAnchor),
            hostedSurfaceView.bottomAnchor.constraint(equalTo: bottomAnchor),
            overlayHostingController.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlayHostingController.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            overlayHostingController.view.topAnchor.constraint(equalTo: topAnchor),
            overlayHostingController.view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        dependencies.libraryStore.$pictureInPictureEnabled
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.surfaceHostView.setPictureInPictureEnabled(
                        isEnabled && !self.state.playerViewModel.isAudioOnlyPlayback
                    )
                }
            }
            .store(in: &cancellables)

    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func attach(to parent: UIViewController) {
        guard !isTornDown else { return }
        surfaceHostView.attach(to: parent)
        guard overlayHostingController.parent == nil else { return }
        parent.addChild(overlayHostingController)
        overlayHostingController.didMove(toParent: parent)
    }

    func tearDown() {
        guard !isTornDown else { return }
        isTornDown = true
        cancelRotationChromePrewarm()
        cancellables.removeAll()
        surfaceHostView.tearDown()
        surfaceHostView.hostedView.removeFromSuperview()
        overlayHostingController.willMove(toParent: nil)
        overlayHostingController.view.removeFromSuperview()
        overlayHostingController.removeFromParent()
    }

    func requestPlaybackControlsHideForRotation() {
        state.requestPlaybackControlsHideForRotation()
    }

    func markRotationChromePrewarmed() {
        isRotationChromePrewarmed = true
    }

    /// 系统旋转期间退化成 bare surface，但始终保留弹幕层以避免重建和闪烁。
    /// 实验路径可保留不可见的控件树，避免旋转结束时集中重建 SwiftUI 叠层。
    func setBareSurfaceTransitionActive(_ active: Bool, retainsChromeTree: Bool = false) {
        guard state.isBareSurfaceTransitionActive != active
            || state.retainsChromeDuringBareSurfaceTransition != retainsChromeTree
        else { return }
        cancelRotationChromePrewarm()
        overlayState.setBareSurfaceTransitionActive(active)
        experimentState.setBareSurfaceTransitionActive(active)
        state.setBareSurfaceTransitionActive(active, retainsChromeTree: retainsChromeTree)
        UIView.performWithoutAnimation {
            overlayHostingController.view.isHidden = false
            overlayHostingController.view.isUserInteractionEnabled = !active
            surfaceHostView.hostedView.isUserInteractionEnabled = false
        }
    }

    func refreshLayoutImmediately() {
        UIView.performWithoutAnimation {
            setNeedsLayout()
            layoutIfNeeded()
            surfaceHostView.refreshLayoutImmediately()
            if !state.isBareSurfaceTransitionActive {
                overlayHostingController.view.setNeedsLayout()
                overlayHostingController.view.layoutIfNeeded()
            }
        }
    }

    func prewarmRotationChrome() {
        guard !isRotationChromePrewarming,
              !state.isBareSurfaceTransitionActive
        else { return }
        isRotationChromePrewarmed = false
        isRotationChromePrewarming = true
        rotationChromePrewarmGeneration &+= 1
        let generation = rotationChromePrewarmGeneration
        let prewarmLandscape = !rotationCoordinator.isLandscape

        UIView.performWithoutAnimation {
            state.setBareSurfaceTransitionActive(true, retainsChromeTree: true)
            rotationCoordinator.beginChromePrewarm(for: prewarmLandscape)
        }
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.isRotationChromePrewarming,
                  self.rotationChromePrewarmGeneration == generation
            else { return }
            self.layoutRotationChromePrewarm()
            UIView.performWithoutAnimation {
                self.rotationCoordinator.endChromePrewarm()
            }
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.isRotationChromePrewarming,
                      self.rotationChromePrewarmGeneration == generation
                else { return }
                self.layoutRotationChromePrewarm()
                UIView.performWithoutAnimation {
                    self.state.setBareSurfaceTransitionActive(false, retainsChromeTree: true)
                }
                self.isRotationChromePrewarming = false
                self.isRotationChromePrewarmed = true
            }
        }
    }

    func cancelRotationChromePrewarm() {
        guard isRotationChromePrewarming else { return }
        rotationChromePrewarmGeneration &+= 1
        isRotationChromePrewarming = false
        UIView.performWithoutAnimation {
            rotationCoordinator.endChromePrewarm()
            state.setBareSurfaceTransitionActive(false, retainsChromeTree: true)
        }
    }

    /// 清晰度切换等场景会替换 player 实例，UIKit 直连路径会原位重绑叠层。
    func setPlayerViewModel(_ playerViewModel: PlayerStateViewModel) {
        guard state.playerViewModel !== playerViewModel else { return }
        state.playerViewModel = playerViewModel
        surfaceHostView.setPlayerViewModel(playerViewModel)
        surfaceHostView.setPictureInPictureEnabled(
            libraryStore.pictureInPictureEnabled
                && !playerViewModel.isAudioOnlyPlayback
        )
    }

    func setVideoGravity(_ gravity: AVLayerVideoGravity) {
        surfaceHostView.setVideoGravity(gravity)
    }

    func setVideoAspectRatio(_ aspectRatio: CGFloat) {
        guard aspectRatio > 0.1, abs(state.videoAspectRatio - aspectRatio) > 0.001 else { return }
        state.videoAspectRatio = aspectRatio
    }

    func setCollapsedChromeActive(_ active: Bool) {
        guard state.isCollapsedChromeActive != active else { return }
        state.isCollapsedChromeActive = active
    }

    private func layoutRotationChromePrewarm() {
        overlayHostingController.view.setNeedsLayout()
        overlayHostingController.view.layoutIfNeeded()
    }

}

extension VideoDetailShellSurfaceHost: PlayerSurfaceHosting {
    var surfaceView: UIView { self }

    func setLandscape(_: Bool) {}

    func setPortraitFullscreen(_: Bool) {}
}

private struct VideoDetailShellOverlaySnapshot: Equatable {
    var historyVideo: VideoItem
    var recordsPlaybackHistory = true
    var historyCID: Int?
    var historyDuration: TimeInterval?
    var isDanmakuEnabled = true
    var isSwitchingPlayQuality = false
    var playbackContentMode: PlayerPlaybackContentMode = .video
    var isSwitchingVideoListenMode = false

    init(
        detail: VideoItem,
        recordsPlaybackHistory: Bool,
        selectedCID: Int?,
        isDanmakuEnabled: Bool,
        isSwitchingPlayQuality: Bool,
        playbackContentMode: PlayerPlaybackContentMode,
        isSwitchingVideoListenMode: Bool
    ) {
        self.historyVideo = detail
        self.recordsPlaybackHistory = recordsPlaybackHistory
        self.historyCID = recordsPlaybackHistory ? (selectedCID ?? detail.cid) : nil
        self.historyDuration = detail.duration.map(TimeInterval.init)
        self.isDanmakuEnabled = isDanmakuEnabled
        self.isSwitchingPlayQuality = isSwitchingPlayQuality
        self.playbackContentMode = playbackContentMode
        self.isSwitchingVideoListenMode = isSwitchingVideoListenMode
    }
}

@MainActor
private final class VideoDetailShellOverlayState: ObservableObject {
    @Published private(set) var snapshot: VideoDetailShellOverlaySnapshot
    private var isBareSurfaceTransitionActive = false
    private var pendingSnapshot: VideoDetailShellOverlaySnapshot?
    private weak var experimentState: VideoDetailPerformanceExperimentState?
    private var cancellables = Set<AnyCancellable>()

    init(
        detailViewModel: VideoDetailViewModel,
        experimentState: VideoDetailPerformanceExperimentState
    ) {
        self.experimentState = experimentState
        self.snapshot = VideoDetailShellOverlaySnapshot(
            detail: detailViewModel.detail,
            recordsPlaybackHistory: detailViewModel.playbackOptions.recordsPlaybackHistory,
            selectedCID: detailViewModel.selectedCID,
            isDanmakuEnabled: detailViewModel.isDanmakuEnabled,
            isSwitchingPlayQuality: detailViewModel.isSwitchingPlayQuality,
            playbackContentMode: detailViewModel.playbackContentMode,
            isSwitchingVideoListenMode: detailViewModel.isSwitchingVideoListenMode
        )

        let playbackSnapshotPublisher = Publishers.CombineLatest4(
            detailViewModel.$detail,
            detailViewModel.$selectedCID,
            detailViewModel.$isDanmakuEnabled,
            detailViewModel.$isSwitchingPlayQuality
        )
        let listenModePublisher = detailViewModel.$playbackContentMode
            .combineLatest(detailViewModel.$isSwitchingVideoListenMode)

        Publishers.CombineLatest(playbackSnapshotPublisher, listenModePublisher)
        .map { playback, listenMode in
            let (detail, selectedCID, isDanmakuEnabled, isSwitchingPlayQuality) = playback
            let (playbackContentMode, isSwitchingVideoListenMode) = listenMode
            return VideoDetailShellOverlaySnapshot(
                detail: detail,
                recordsPlaybackHistory: detailViewModel.playbackOptions.recordsPlaybackHistory,
                selectedCID: selectedCID,
                isDanmakuEnabled: isDanmakuEnabled,
                isSwitchingPlayQuality: isSwitchingPlayQuality,
                playbackContentMode: playbackContentMode,
                isSwitchingVideoListenMode: isSwitchingVideoListenMode
            )
        }
        .removeDuplicates()
        .sink { [weak self] snapshot in
            self?.receive(snapshot)
        }
        .store(in: &cancellables)
    }

    func setBareSurfaceTransitionActive(_ active: Bool) {
        guard isBareSurfaceTransitionActive != active else { return }
        isBareSurfaceTransitionActive = active
        if !active {
            flushPendingSnapshot()
        }
    }

    private func receive(_ nextSnapshot: VideoDetailShellOverlaySnapshot) {
        guard nextSnapshot != snapshot else { return }
        if isBareSurfaceTransitionActive {
            pendingSnapshot = nextSnapshot
            experimentState?.recordOverlayDeferred()
            return
        }
        snapshot = nextSnapshot
        experimentState?.recordOverlayPublish()
    }

    private func flushPendingSnapshot() {
        guard let pendingSnapshot else { return }
        self.pendingSnapshot = nil
        guard pendingSnapshot != snapshot else { return }
        snapshot = pendingSnapshot
        experimentState?.recordOverlayFlush()
    }
}

private extension UIView {
    func removeLayerAnimationsRecursively() {
        layer.removeAllAnimations()
        subviews.forEach { $0.removeLayerAnimationsRecursively() }
    }
}

@MainActor
private final class VideoDetailPlayerOverlayLegacyObservationBridge: ObservableObject {
    @Published private(set) var revision = 0

    private var updateScheduled = false
    private var cancellables = Set<AnyCancellable>()

    init(
        viewModel: PlayerStateViewModel,
        libraryStore: LibraryStore,
        isEnabled: Bool
    ) {
        guard isEnabled else { return }
        Publishers.Merge(
            viewModel.objectWillChange,
            libraryStore.objectWillChange
        )
        .sink { [weak self] in
            self?.scheduleUpdate()
        }
        .store(in: &cancellables)
    }

    private func scheduleUpdate() {
        guard !updateScheduled else { return }
        updateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updateScheduled = false
            self.revision &+= 1
        }
    }
}

private struct PlayerOverlayHostRoot: View {
    let detailViewModel: VideoDetailViewModel
    @ObservedObject var state: VideoDetailShellSurfaceHost.State
    @ObservedObject var rotationCoordinator: PlaybackRotationCoordinator
    @ObservedObject var overlayState: VideoDetailShellOverlayState
    let experimentState: VideoDetailPerformanceExperimentState
    let runtimeSettings: VideoDetailRuntimeSettingsStore
    let usesNarrowObservation: Bool
    let dependencies: AppDependencies
    let onShowMoreControls: (@escaping () -> Void) -> Void
    let onDismissMoreControls: () -> Void
    let onRequestFullscreen: () -> Void
    let onExitFullscreen: () -> Void
    let onToggleDanmaku: () -> Void
    let onShowDanmakuSettings: () -> Void
    let onNavigateBack: () -> Void

    var body: some View {
        let overlaySnapshot = overlayState.snapshot
        let overlay = SurfaceOnlyPlayerOverlayRoot(
            viewModel: state.playerViewModel,
            detailViewModel: detailViewModel,
            rotationCoordinator: rotationCoordinator,
            overlaySnapshot: overlaySnapshot,
            experimentState: experimentState,
            runtimeSettings: runtimeSettings,
            usesNarrowObservation: usesNarrowObservation,
            dependencies: dependencies,
            isBareSurfaceTransitionActive: state.isBareSurfaceTransitionActive,
            retainsChromeDuringBareSurfaceTransition: state.retainsChromeDuringBareSurfaceTransition,
            isCollapsedChromeActive: state.isCollapsedChromeActive,
            playbackControlsHideRequestGeneration: state.playbackControlsHideRequestGeneration,
            videoAspectRatio: state.videoAspectRatio,
            onShowMoreControls: onShowMoreControls,
            onDismissMoreControls: onDismissMoreControls,
            onToggleDanmaku: onToggleDanmaku,
            onShowDanmakuSettings: onShowDanmakuSettings,
            onNavigateBack: onNavigateBack,
            onRequestFullscreen: onRequestFullscreen,
            onExitFullscreen: onExitFullscreen
        )

        Group {
            if usesNarrowObservation {
                overlay
            } else {
                overlay.id(ObjectIdentifier(state.playerViewModel))
            }
        }
        .ignoresSafeArea()
    }
}

private struct SurfaceOnlyPlayerOverlayRoot: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    let viewModel: PlayerStateViewModel
    let detailViewModel: VideoDetailViewModel
    @ObservedObject var libraryStore: LibraryStore
    @ObservedObject var runtimeSettings: VideoDetailRuntimeSettingsStore

    let overlaySnapshot: VideoDetailShellOverlaySnapshot
    let experimentState: VideoDetailPerformanceExperimentState
    let usesNarrowObservation: Bool
    let dependencies: AppDependencies
    @ObservedObject var rotationCoordinator: PlaybackRotationCoordinator
    let isBareSurfaceTransitionActive: Bool
    let retainsChromeDuringBareSurfaceTransition: Bool
    let isCollapsedChromeActive: Bool
    let playbackControlsHideRequestGeneration: Int
    let videoAspectRatio: CGFloat
    let onShowMoreControls: (@escaping () -> Void) -> Void
    let onDismissMoreControls: () -> Void
    let onToggleDanmaku: () -> Void
    let onShowDanmakuSettings: () -> Void
    let onNavigateBack: () -> Void
    let onRequestFullscreen: () -> Void
    let onExitFullscreen: () -> Void

    @StateObject private var surfaceState: PlayerSurfaceStateModel
    @StateObject private var playbackControlsVisibility = PlayerPlaybackControlsVisibilityModel()
    @StateObject private var rotationTransitionSnapshotModel = PlayerRotationTransitionSnapshotModel()
    @StateObject private var seekTransitionSnapshotModel = PlayerRotationTransitionSnapshotModel()
    @StateObject private var appBackgroundRecoverySnapshotModel = PlayerRotationTransitionSnapshotModel()
    @StateObject private var speedBoostModel = PlayerSpeedBoostModel()
    @StateObject private var seekPreviewModel = PlayerSeekPreviewModel()
    @StateObject private var playbackProgressCoordinator = PlayerPlaybackProgressCoordinator()
    @StateObject private var progressReporter = PlayerPlaybackProgressReporter()
    @StateObject private var legacyObservationBridge: VideoDetailPlayerOverlayLegacyObservationBridge
    @State private var lastPreparedScrubProgress = -1.0
    @State private var isMoreControlsPresented = false
    @State private var portraitMoreControlsRequestID: UUID?
    @State private var isMoreControlsButtonPressed = false
    @State private var isVideoListenQueuePresented = false

    private var isLandscape: Bool {
        rotationCoordinator.chromeLandscape
    }

    private var isPortraitFullscreen: Bool {
        rotationCoordinator.isPortraitFullscreen
    }

    init(
        viewModel: PlayerStateViewModel,
        detailViewModel: VideoDetailViewModel,
        rotationCoordinator: PlaybackRotationCoordinator,
        overlaySnapshot: VideoDetailShellOverlaySnapshot,
        experimentState: VideoDetailPerformanceExperimentState,
        runtimeSettings: VideoDetailRuntimeSettingsStore,
        usesNarrowObservation: Bool,
        dependencies: AppDependencies,
        isBareSurfaceTransitionActive: Bool,
        retainsChromeDuringBareSurfaceTransition: Bool,
        isCollapsedChromeActive: Bool,
        playbackControlsHideRequestGeneration: Int,
        videoAspectRatio: CGFloat,
        onShowMoreControls: @escaping (@escaping () -> Void) -> Void,
        onDismissMoreControls: @escaping () -> Void,
        onToggleDanmaku: @escaping () -> Void,
        onShowDanmakuSettings: @escaping () -> Void,
        onNavigateBack: @escaping () -> Void,
        onRequestFullscreen: @escaping () -> Void,
        onExitFullscreen: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.detailViewModel = detailViewModel
        self.rotationCoordinator = rotationCoordinator
        self.overlaySnapshot = overlaySnapshot
        self.experimentState = experimentState
        self.runtimeSettings = runtimeSettings
        self.usesNarrowObservation = usesNarrowObservation
        self.dependencies = dependencies
        _libraryStore = ObservedObject(wrappedValue: dependencies.libraryStore)
        self.isBareSurfaceTransitionActive = isBareSurfaceTransitionActive
        self.retainsChromeDuringBareSurfaceTransition = retainsChromeDuringBareSurfaceTransition
        self.isCollapsedChromeActive = isCollapsedChromeActive
        self.playbackControlsHideRequestGeneration = playbackControlsHideRequestGeneration
        self.videoAspectRatio = videoAspectRatio
        self.onShowMoreControls = onShowMoreControls
        self.onDismissMoreControls = onDismissMoreControls
        self.onToggleDanmaku = onToggleDanmaku
        self.onShowDanmakuSettings = onShowDanmakuSettings
        self.onNavigateBack = onNavigateBack
        self.onRequestFullscreen = onRequestFullscreen
        self.onExitFullscreen = onExitFullscreen
        _surfaceState = StateObject(wrappedValue: PlayerSurfaceStateModel(viewModel: viewModel))
        _legacyObservationBridge = StateObject(
            wrappedValue: VideoDetailPlayerOverlayLegacyObservationBridge(
                viewModel: viewModel,
                libraryStore: dependencies.libraryStore,
                isEnabled: !usesNarrowObservation
            )
        )
    }

    var body: some View {
        let _ = legacyObservationBridge.revision
        let context = runtimeContext
        let renderContext = context.renderContext
        let renderState = BiliPlayerViewRenderState(
            context: renderContext,
            verticalSizeClass: verticalSizeClass
        )
        let visibilityActions = renderState.visibilityActions
        let speedActions = renderState.speedBoostActions
        let nativeActions = BiliPlayerNativeControlsActionBuilder(
            viewModel: viewModel,
            configuration: renderContext.configuration,
            visibilityActions: visibilityActions,
            seekPreviewModel: renderContext.seekPreviewModel,
            seekPreviewAPI: renderContext.seekPreviewAPI,
            seekPreviewContext: renderContext.seekPreviewContext,
            holdCurrentFrameForSeek: holdCurrentFrameForSeek,
            prepareUserSeekWarmup: prepareUserSeekWarmupIfNeeded,
            resetPreparedScrubProgress: { lastPreparedScrubProgress = -1 },
            isFullscreenActiveOverride: isPortraitFullscreen ? true : nil
        ).actions
        let shouldKeepChromeMounted = keepsChromeMounted && !isCollapsedChromeActive

        GeometryReader { proxy in
            let videoInsets = visibleVideoInsets(in: proxy.size)
            let chromeState = surfaceChromeState(
                context: renderContext,
                renderState: renderState,
                contentInsets: videoInsets
            )
            ZStack {
                if isAudioOnlyPlayback {
                    VideoListenArtworkLayer(
                        video: overlaySnapshot.historyVideo,
                        isLandscape: isLandscape
                    )
                    .allowsHitTesting(false)
                    .zIndex(0.5)
                }

                if shouldKeepChromeMounted {
                    Group {
                        BiliPlayerSurfaceGestureLayerHost(
                            content: Color.clear
                                .frame(maxWidth: .infinity, maxHeight: .infinity),
                            visibilityActions: visibilityActions,
                            speedBoostActions: speedActions,
                            viewModel: viewModel,
                            allowsDoubleTapPlaybackToggle: true,
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
                                    actions: nativeActions,
                                    progressStyle: .telegram,
                                    isFullscreenActiveOverride: isPortraitFullscreen ? true : nil
                                )
                            ),
                            usesFullscreenSafeArea: isPortraitFullscreen
                        )
                        .zIndex(3)

                        if isAudioOnlyPlayback {
                            persistentMoreControlsButton(contentInsets: videoInsets)
                        }

                        if runtimeSettings.playerPerformanceOverlayEnabled {
                            performanceOverlay(contentInsets: videoInsets, in: proxy.size)
                                .zIndex(8)
                        }

                        let rotationReportMetricsID = overlaySnapshot.historyVideo.bvid
                        if runtimeSettings.videoRotationFrameReportOverlayEnabled,
                           !rotationReportMetricsID.isEmpty {
                            VideoRotationFrameReportFloatingWindow(
                                metricsID: rotationReportMetricsID,
                                contentInsets: videoInsets
                            )
                            .zIndex(8.5)
                        }

                        if isLandscape, isMoreControlsPresented {
                            SurfaceOnlyLandscapeMoreControlsOverlay(
                                detailViewModel: detailViewModel,
                                viewModel: viewModel,
                                libraryStore: libraryStore,
                                qualityStore: detailViewModel.playbackRenderStore.qualityControlStore,
                                selectPlayVariant: { detailViewModel.selectPlayVariant($0) },
                                onToggleDanmaku: onToggleDanmaku,
                                contentInsets: videoInsets,
                                close: { isMoreControlsPresented = false }
                            )
                            .transition(.opacity)
                            .zIndex(9)
                        }
                    }
                    .opacity(isBareSurfaceTransitionActive ? 0 : 1)
                    .allowsHitTesting(!isBareSurfaceTransitionActive)
                }

                if showsCenterPlaybackControl {
                    centerPlaybackControl
                        .zIndex(5)
                }

                if !isAudioOnlyPlayback {
                    VideoDetailPlayerSurfaceDanmakuLayer(
                        store: detailViewModel.danmakuRenderStore,
                        playerViewModel: viewModel,
                        usesLandscapePlaybackChrome: configuration.isFullscreenActive,
                        isLayoutTransitioning: isBareSurfaceTransitionActive,
                        onPlaybackTime: { detailViewModel.updateDanmakuPlaybackTime($0, underLoad: $1) }
                    )
                    .allowsHitTesting(false)
                    .zIndex(2.5)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .background {
            PlaybackDetailPlayerReadinessProbe(
                playerViewModel: viewModel,
                context: .video(overlaySnapshot.historyVideo)
            )
        }
        .environmentObject(dependencies)
        .environmentObject(libraryStore)
        .environment(\.appThemeTintColor, runtimeSettings.appTintColor)
        .biliPlayerLifecycle(
            isFullscreenActive: configuration.isFullscreenActive,
            presentation: configuration.presentation,
            isLayoutTransitioning: configuration.isLayoutTransitioning,
            isSecondaryControlsPresented: configuration.isSecondaryControlsPresented,
            isPictureInPictureEnabled: effectivePictureInPictureEnabled,
            actions: context.lifecycleActions
        )
        .onAppear {
            if !isAudioOnlyPlayback {
                detailViewModel.scheduleDanmakuLoadIfNeeded()
            }
        }
        .onChange(of: ObjectIdentifier(viewModel)) { _, _ in
            guard usesNarrowObservation else { return }
            context.lifecycleActions.onPlayerChanged()
            experimentState.recordPlayerRebind()
        }
        .onChange(of: isLandscape) { _, isLandscape in
            // 旋转控件预热会在 bare transition 中短暂翻转该值，不能把它当成
            // 用户真实进入横屏，否则刚弹出的竖屏菜单会被预热流程立即关闭。
            guard !isBareSurfaceTransitionActive else { return }
            if isLandscape {
                portraitMoreControlsRequestID = nil
                onDismissMoreControls()
                isVideoListenQueuePresented = false
            } else {
                isMoreControlsPresented = false
            }
        }
        .onChange(of: overlaySnapshot.playbackContentMode) { _, mode in
            if mode != .audioOnly {
                isVideoListenQueuePresented = false
            }
            guard mode == .audioOnly else { return }
            isMoreControlsPresented = false
            portraitMoreControlsRequestID = nil
            onDismissMoreControls()
            if isLandscape {
                onExitFullscreen()
            }
        }
        .onChange(of: isBareSurfaceTransitionActive) { _, isActive in
            guard isActive else { return }
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isMoreControlsPresented = false
                isVideoListenQueuePresented = false
            }
            playbackControlsVisibility.cancelAutoHide()
        }
        .onChange(of: playbackControlsHideRequestGeneration) { _, _ in
            playbackControlsVisibility.hide(animated: false)
        }
        .onChange(of: surfaceState.isUserSeeking) { _, isUserSeeking in
            updateSeekTransitionSnapshot(isUserSeeking: isUserSeeking)
        }
        .onReceive(surfaceState.$snapshot.dropFirst()) { _ in
            guard usesNarrowObservation else { return }
            experimentState.recordPlayerStatePublish()
        }
        .onReceive(runtimeSettings.$snapshot.dropFirst()) { _ in
            guard usesNarrowObservation else { return }
            experimentState.recordSettingsStatePublish()
        }
        .sheet(isPresented: $isVideoListenQueuePresented) {
            NavigationStack {
                SurfaceOnlyVideoListenQueuePage(
                    detailViewModel: detailViewModel,
                    closeSheet: { isVideoListenQueuePresented = false }
                )
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var backButton: some View {
        VideoDetailPlayerSurfaceBackButtonHost(action: handleBackButton)
            .environment(\.playerNativeControlMetrics, controlMetrics)
            .accessibilityIdentifier("ui.player.back")
    }

    private func handleBackButton() {
        if fullscreenMode != nil || isPortraitFullscreen {
            onExitFullscreen()
        } else {
            onNavigateBack()
        }
    }

    private var fullscreenMode: PlayerFullscreenMode? {
        guard !isAudioOnlyPlayback else { return nil }
        return isLandscape ? .landscape(.landscapeRight) : nil
    }

    private var isAudioOnlyPlayback: Bool {
        overlaySnapshot.playbackContentMode == .audioOnly
    }

    private var effectivePictureInPictureEnabled: Bool {
        runtimeSettings.pictureInPictureEnabled && !isAudioOnlyPlayback
    }

    private var keepsChromeMounted: Bool {
        !isBareSurfaceTransitionActive || retainsChromeDuringBareSurfaceTransition
    }

    private var showsCenterPlaybackControl: Bool {
        keepsChromeMounted
            && !isCollapsedChromeActive
            && !isBareSurfaceTransitionActive
            && surfaceState.showsExplicitPlaybackStartControl
            && surfaceState.errorMessage == nil
    }

    private var centerPlaybackControl: some View {
        PlayerNativeGlassIconButton(
            systemName: "play.fill",
            accessibilityLabel: "播放",
            metrics: centerPlaybackControlMetrics
        ) {
            viewModel.play()
            playbackControlsVisibility.showAndSchedule(
                showsPlaybackControls: keepsChromeMounted,
                isLayoutTransitioning: isBareSurfaceTransitionActive
            )
        }
        .biliLiquidGlassForeground(shadowOpacity: 0.20)
    }

    private var centerPlaybackControlMetrics: PlayerNativeControlMetrics {
        controlMetrics.sized(controlHeight: 56, iconSize: 24)
    }

    private var configuration: BiliPlayerViewConfiguration {
        BiliPlayerViewOptions(
            presentation: isLandscape ? .fullScreen : .embedded,
            showsNavigationChrome: false,
            showsPlaybackControls: keepsChromeMounted,
            showsStartupLoadingIndicator: keepsChromeMounted && viewModel.wantsAutoplay,
            pausesOnDisappear: false,
            controlsAccessory: isAudioOnlyPlayback
                ? AnyView(videoListenQuickControls)
                : usesFullscreenStatusChrome
                    ? AnyView(moreControlsButton)
                    : nil,
            topLeadingControlsAccessory: keepsChromeMounted ? AnyView(backButton) : nil,
            isDanmakuEnabled: keepsChromeMounted && overlaySnapshot.isDanmakuEnabled && !isAudioOnlyPlayback,
            onToggleDanmaku: isAudioOnlyPlayback ? nil : onToggleDanmaku,
            onShowDanmakuSettings: isAudioOnlyPlayback ? nil : onShowDanmakuSettings,
            isSecondaryControlsPresented: keepsChromeMounted
                && (isMoreControlsPresented
                    || portraitMoreControlsRequestID != nil
                    || isVideoListenQueuePresented),
            ignoresContainerSafeArea: true,
            keepsPlayerSurfaceStable: true,
            fullscreenMode: fullscreenMode,
            isLayoutTransitioning: isBareSurfaceTransitionActive,
            usesLiveSurfaceDuringLayoutTransition: true,
            disablesSurfaceImplicitLayoutAnimations: true,
            showsRotationTransitionSnapshot: false,
            onRequestFullscreen: isAudioOnlyPlayback ? nil : onRequestFullscreen,
            onExitFullscreen: isAudioOnlyPlayback ? nil : onExitFullscreen
        ).configuration()
    }

    private var videoListenQuickControls: some View {
        SurfaceOnlyVideoListenQuickControls(
            detailViewModel: detailViewModel,
            libraryStore: libraryStore,
            metrics: controlMetrics,
            showQueue: { isVideoListenQueuePresented = true }
        )
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
            historyVideo: overlaySnapshot.recordsPlaybackHistory ? overlaySnapshot.historyVideo : nil,
            historyCID: overlaySnapshot.historyCID,
            historyDuration: overlaySnapshot.historyDuration,
            configuration: configuration,
            isPictureInPictureEnabled: effectivePictureInPictureEnabled,
            videoGravity: .resizeAspect,
            holdCurrentFrameForSeek: holdCurrentFrameForSeek,
            prepareUserSeekWarmup: prepareUserSeekWarmupIfNeeded,
            resetPreparedScrubProgress: { lastPreparedScrubProgress = -1 }
        ).context
    }

    private var moreControlsButton: some View {
        SurfaceOnlyUIKitMoreControlsButton(
            metrics: controlMetrics,
            systemImageName: usesFullscreenStatusChrome ? "gearshape.fill" : "ellipsis.circle",
            onPressBegan: {
                isMoreControlsButtonPressed = true
                playbackControlsVisibility.cancelAutoHide()
            },
            onPressEnded: {
                isMoreControlsButtonPressed = false
                guard portraitMoreControlsRequestID == nil,
                      !isMoreControlsPresented
                else { return }
                playbackControlsVisibility.scheduleAutoHide(
                    showsPlaybackControls: keepsChromeMounted,
                    isLayoutTransitioning: isBareSurfaceTransitionActive
                )
            }
        ) {
            playbackControlsVisibility.cancelAutoHide()
            if isLandscape {
                withAnimation(.default) {
                    isMoreControlsPresented = true
                }
            } else {
                let requestID = UUID()
                portraitMoreControlsRequestID = requestID
                onShowMoreControls {
                    guard portraitMoreControlsRequestID == requestID else { return }
                    portraitMoreControlsRequestID = nil
                }
            }
        }
        .frame(width: controlMetrics.controlHeight, height: controlMetrics.controlHeight)
        .frame(width: 44, height: controlMetrics.controlHeight, alignment: .trailing)
        .biliPlayerExpandedHitTarget(horizontal: 0, vertical: 8)
        .accessibilityLabel("更多播放设置")
    }

    private func persistentMoreControlsButton(contentInsets: EdgeInsets) -> some View {
        GeometryReader { _ in
            let safeAreaInsets = fullscreenSafeAreaInsets()
            let topInset = max(safeAreaInsets.top, contentInsets.top)
            let trailingInset = max(safeAreaInsets.right, contentInsets.trailing)
            VStack {
                HStack {
                    Spacer()
                    moreControlsButton
                        .padding(.top, topControlsPadding + topInset)
                        .padding(.trailing, moreControlsTrailingPadding(trailingInset: trailingInset))
                }
                Spacer()
            }
        }
        .opacity(isMoreControlsButtonPressed ? 1 : playbackControlsVisibility.opacity)
        .allowsHitTesting(
            isMoreControlsButtonPressed || playbackControlsVisibility.acceptsHitTesting
        )
        .zIndex(4)
    }

    private func performanceOverlay(contentInsets: EdgeInsets, in size: CGSize) -> some View {
        let safeAreaInsets = fullscreenSafeAreaInsets()
        let topInset = max(safeAreaInsets.top, contentInsets.top)
        let leadingInset = max(safeAreaInsets.left, contentInsets.leading)
        let trailingInset = max(safeAreaInsets.right, contentInsets.trailing)
        let bottomInset = max(safeAreaInsets.bottom, contentInsets.bottom)
        let horizontalPadding = horizontalControlsPadding
        let availableWidth = max(1, size.width - leadingInset - trailingInset - horizontalPadding * 2)
        let availableHeight = max(1, size.height - topInset - bottomInset - topControlsPadding - 14)
        let panelWidth = min(isLandscape ? 340 : 320, max(260, availableWidth))
        let maximumHeight = min(isLandscape ? 420 : 360, max(180, availableHeight))

        return VStack {
            HStack {
                VideoDetailPerformanceOverlayContainer(
                    store: detailViewModel.networkDiagnosticsRenderStore,
                    experimentState: experimentState,
                    panelWidth: panelWidth,
                    maximumHeight: maximumHeight
                )
                .padding(.top, topControlsPadding + topInset)
                .padding(.leading, horizontalPadding + leadingInset)

                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func visibleVideoInsets(in size: CGSize) -> EdgeInsets {
        guard configuration.isFullscreenActive,
              size.width > 1,
              size.height > 1,
              videoAspectRatio > 0.1
        else { return EdgeInsets() }

        let containerAspect = size.width / size.height
        let horizontalInset: CGFloat
        let verticalInset: CGFloat
        if videoAspectRatio > containerAspect {
            let fittedHeight = size.width / videoAspectRatio
            horizontalInset = 0
            verticalInset = max(0, (size.height - fittedHeight) / 2)
        } else {
            let fittedWidth = size.height * videoAspectRatio
            horizontalInset = max(0, (size.width - fittedWidth) / 2)
            verticalInset = 0
        }

        return EdgeInsets(
            top: verticalInset,
            leading: horizontalInset,
            bottom: verticalInset,
            trailing: horizontalInset
        )
    }

    private func moreControlsTrailingPadding(trailingInset: CGFloat) -> CGFloat {
        horizontalControlsPadding + trailingInset
    }

    private var usesFullscreenChromeSpacing: Bool {
        configuration.presentation == .fullScreen || configuration.isFullscreenActive
    }

    private var topControlsPadding: CGFloat {
        usesFullscreenChromeSpacing ? 14 : 10
    }

    private var horizontalControlsPadding: CGFloat {
        usesFullscreenChromeSpacing ? 14 : 10
    }

    private func fullscreenSafeAreaInsets() -> UIEdgeInsets {
        guard configuration.isFullscreenActive,
              let window = UIApplication.shared.playbackDetailForegroundKeyWindow
        else { return .zero }
        return window.safeAreaInsets
    }

    private var controlMetrics: PlayerNativeControlMetrics {
        if fullscreenMode?.isLandscape == true || verticalSizeClass == .compact {
            return .landscape
        }
        return .portrait
    }

    private var usesFullscreenStatusChrome: Bool {
        !isAudioOnlyPlayback
    }

    private var showsFullscreenStatusControls: Bool {
        VideoDetailSurfaceChromePolicy.showsFullscreenStatusControls(
            usesFullscreenChrome: usesFullscreenStatusChrome
                && fullscreenMode?.isLandscape == true,
            isPortraitFullscreen: isPortraitFullscreen
        )
    }

    private func surfaceChromeState(
        context: BiliPlayerViewRenderContext,
        renderState: BiliPlayerViewRenderState,
        contentInsets: EdgeInsets
    ) -> BiliPlayerSurfaceChromeState {
        return BiliPlayerSurfaceChromeState(
            presentation: context.configuration.presentation,
            surfaceOverlay: context.configuration.surfaceOverlay,
            rotationSnapshot: nil,
            seekSnapshot: seekTransitionSnapshotModel.snapshot,
            appBackgroundRecoverySnapshot: appBackgroundRecoverySnapshotModel.snapshot,
            rotationFallbackCoverURL: nil,
            rotationSnapshotOpacity: 0,
            seekSnapshotOpacity: seekTransitionSnapshotModel.opacity,
            appBackgroundRecoverySnapshotOpacity: appBackgroundRecoverySnapshotModel.opacity,
            constrainsRotationSnapshotToVideoAspect: false,
            showsPlayerLoadingChrome: renderState.showsPlayerLoadingChrome
                && !overlaySnapshot.isSwitchingPlayQuality,
            isBuffering: context.surfaceState.isBuffering,
            isPlaying: context.surfaceState.isPlaying,
            hasPresentedPlayback: context.surfaceState.hasPresentedPlayback,
            showsInlineLoadingProgress: renderState.showsInlineLoadingProgress,
            isUserSeeking: context.surfaceState.isUserSeeking,
            showsActivePlaybackControls: renderState.showsActivePlaybackControls,
            playbackControlsOpacity: playbackControlsVisibility.opacity,
            playbackControlsAllowsHitTesting: playbackControlsVisibility.acceptsHitTesting,
            topLeadingControlsAccessory: context.configuration.topLeadingControlsAccessory,
            topCenterControlsAccessory: showsFullscreenStatusControls
                ? AnyView(VideoDetailFullscreenClockControl())
                : nil,
            topTrailingControlsAccessory: showsFullscreenStatusControls
                ? AnyView(VideoDetailFullscreenBatteryControl())
                : nil,
            isFullscreenActive: context.configuration.isFullscreenActive,
            controlsBottomLift: context.configuration.controlsBottomLift,
            controlsHorizontalInset: context.configuration.controlsHorizontalInset,
            contentInsets: contentInsets,
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

struct SurfaceOnlyMoreControlsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var detailViewModel: VideoDetailViewModel
    @ObservedObject var viewModel: PlayerStateViewModel
    @ObservedObject var qualityStore: VideoDetailQualityControlRenderStore
    let selectPlayVariant: (PlayVariant) -> Void
    let onToggleDanmaku: () -> Void
    let closeAction: (() -> Void)?

    init(
        detailViewModel: VideoDetailViewModel,
        viewModel: PlayerStateViewModel,
        qualityStore: VideoDetailQualityControlRenderStore,
        selectPlayVariant: @escaping (PlayVariant) -> Void,
        onToggleDanmaku: @escaping () -> Void,
        close: (() -> Void)? = nil
    ) {
        self.detailViewModel = detailViewModel
        self.viewModel = viewModel
        self.qualityStore = qualityStore
        self.selectPlayVariant = selectPlayVariant
        self.onToggleDanmaku = onToggleDanmaku
        self.closeAction = close
    }

    var body: some View {
        SurfaceOnlyMoreControlsNavigationContent(
            detailViewModel: detailViewModel,
            viewModel: viewModel,
            libraryStore: detailViewModel.libraryStore,
            qualityStore: qualityStore,
            selectPlayVariant: selectPlayVariant,
            onToggleDanmaku: onToggleDanmaku,
            close: closeSheet
        )
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func closeSheet() {
        if let closeAction {
            closeAction()
        } else {
            dismiss()
        }
    }
}

private struct SurfaceOnlyVideoListenQuickControls: View {
    @ObservedObject var detailViewModel: VideoDetailViewModel
    @ObservedObject var libraryStore: LibraryStore
    let metrics: PlayerNativeControlMetrics
    let showQueue: () -> Void

    var body: some View {
        HStack(spacing: metrics.controlSpacing) {
            PlayerNativeGlassIconButton(
                systemName: "list.bullet",
                accessibilityLabel: "播放列表，\(detailViewModel.videoListenQueueAccessoryTitle)",
                metrics: metrics,
                action: showQueue
            )

            Menu {
                ForEach(VideoListenPlaybackOrder.allCases) { order in
                    Button {
                        libraryStore.setVideoListenPlaybackOrder(order)
                    } label: {
                        Label(
                            order.title,
                            systemImage: libraryStore.videoListenPlaybackOrder == order
                                ? "checkmark"
                                : order.systemImage
                        )
                    }
                }
            } label: {
                Image(systemName: libraryStore.videoListenPlaybackOrder.systemImage)
                    .font(.system(size: iconSize, weight: .semibold))
                    .frame(width: metrics.controlHeight, height: metrics.controlHeight)
            }
            .biliPlayerCompactGlassCircle(metrics: metrics)
            .accessibilityLabel("播放顺序，\(libraryStore.videoListenPlaybackOrder.title)")

            Menu {
                ForEach(VideoListenSleepTimerOption.allCases) { option in
                    Button {
                        detailViewModel.setVideoListenSleepTimer(option)
                    } label: {
                        Label(
                            option.title,
                            systemImage: detailViewModel.videoListenSleepTimerOption == option
                                ? "checkmark"
                                : option.systemImage
                        )
                    }
                }
            } label: {
                sleepTimerLabel
            }
            .biliPlayerCompactGlassCapsule(metrics: metrics)
            .accessibilityLabel("定时关闭，\(detailViewModel.videoListenSleepTimerAccessoryTitle)")
        }
    }

    @ViewBuilder
    private var sleepTimerLabel: some View {
        if let deadline = detailViewModel.videoListenSleepTimerDeadline {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(VideoListenSleepTimerCountdownFormatter.text(deadline: deadline, now: context.date))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .lineLimit(1)
                    .frame(width: max(48, metrics.controlHeight + 20), height: metrics.controlHeight)
            }
        } else {
            Image(systemName: detailViewModel.videoListenSleepTimerOption.systemImage)
                .font(.system(size: iconSize, weight: .semibold))
                .frame(width: metrics.controlHeight, height: metrics.controlHeight)
        }
    }

    private var iconSize: CGFloat {
        metrics.iconSize
    }
}

private struct VideoListenArtworkLayer: View {
    let video: VideoItem
    let isLandscape: Bool

    private let artworkAspectRatio: CGFloat = 16.0 / 9.0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black

                backgroundArtwork
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                Color.black.opacity(0.52)

                if proxy.size.height < 280 {
                    compactContent(in: proxy.size)
                } else {
                    regularContent(in: proxy.size)
                }
            }
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("听视频中，\(video.title)，\(ownerName)")
    }

    private var backgroundArtwork: some View {
        CachedRemoteImage(
            url: artworkURL,
            targetPixelSize: 1_280,
            animatesAppearance: false
        ) { image in
            image
                .resizable()
                .scaledToFill()
                .scaleEffect(1.12)
                .blur(radius: 24)
        } placeholder: {
            Color.black
        }
    }

    private func compactContent(in size: CGSize) -> some View {
        let horizontalPadding = min(20.0, max(size.width * 0.05, 12.0))
        let spacing = min(14.0, max(size.width * 0.035, 10.0))
        let availableWidth = max(size.width - horizontalPadding * 2 - spacing, 0)
        let artworkMaximumWidth = min(148.0, availableWidth * 0.43)
        let artworkMaximumHeight = max(size.height - 28, 0)
        let artworkSize = fittedArtworkSize(
            maximumWidth: artworkMaximumWidth,
            maximumHeight: artworkMaximumHeight
        )
        let metadataWidth = max(availableWidth - artworkSize.width, 0)

        return HStack(spacing: spacing) {
            foregroundArtwork
                .frame(width: artworkSize.width, height: artworkSize.height)

            metadata(alignment: .leading, textAlignment: .leading, titleLines: 2)
                .frame(width: metadataWidth, alignment: .leading)
                .layoutPriority(1)
        }
        .padding(.horizontal, horizontalPadding)
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private func regularContent(in size: CGSize) -> some View {
        let artworkSize = fittedArtworkSize(
            maximumWidth: min(isLandscape ? 300 : 220, size.width * 0.52),
            maximumHeight: max(size.height * 0.55, 0)
        )

        return VStack(spacing: isLandscape ? 14 : 12) {
            foregroundArtwork
                .frame(width: artworkSize.width, height: artworkSize.height)

            metadata(alignment: .center, textAlignment: .center, titleLines: 2)
                .frame(maxWidth: min(460, size.width * 0.70))
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var foregroundArtwork: some View {
        CachedRemoteImage(
            url: artworkURL,
            targetPixelSize: 960,
            animatesAppearance: true
        ) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            BiliMediaPlaceholder(style: .video, iconSize: 22)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(0.34), radius: 12, x: 0, y: 7)
    }

    private func metadata(
        alignment: HorizontalAlignment,
        textAlignment: TextAlignment,
        titleLines: Int
    ) -> some View {
        VStack(alignment: alignment, spacing: 6) {
            Label("听视频中", systemImage: "headphones")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)

            Text(video.title)
                .font(.headline)
                .foregroundStyle(.white)
                .multilineTextAlignment(textAlignment)
                .lineLimit(titleLines)

            Text(ownerName)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.76))
                .lineLimit(1)
        }
    }

    private var ownerName: String {
        let name = video.owner?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "未知 UP 主" : name
    }

    private var artworkURL: URL? {
        guard let picture = video.pic?.normalizedBiliURL(), !picture.isEmpty else { return nil }
        return URL(string: picture.biliCoverThumbnailURL(width: 1_280, height: 720))
    }

    private func fittedArtworkSize(
        maximumWidth: CGFloat,
        maximumHeight: CGFloat
    ) -> CGSize {
        guard maximumWidth > 0, maximumHeight > 0 else { return .zero }
        let widthFromHeight = maximumHeight * artworkAspectRatio
        let width = min(maximumWidth, widthFromHeight)
        return CGSize(width: width, height: width / artworkAspectRatio)
    }
}

private struct SurfaceOnlyMoreControlsNavigationContent: View {
    @ObservedObject var detailViewModel: VideoDetailViewModel
    @ObservedObject var viewModel: PlayerStateViewModel
    @ObservedObject var libraryStore: LibraryStore
    @ObservedObject var qualityStore: VideoDetailQualityControlRenderStore
    let selectPlayVariant: (PlayVariant) -> Void
    let onToggleDanmaku: () -> Void
    let close: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if detailViewModel.isVideoListenModeEnabled,
                   !detailViewModel.videoListenAudioVariants.isEmpty {
                    NavigationLink {
                        SurfaceOnlyAudioChoicesPage(
                            detailViewModel: detailViewModel,
                            closeSheet: close
                        )
                    } label: {
                        HStack {
                            Label("音质", systemImage: "waveform")
                            Spacer()
                            Text(detailViewModel.videoListenAudioAccessoryTitle)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if qualityStore.hasQualityMenu {
                    NavigationLink {
                        SurfaceOnlyQualityChoicesPage(
                            qualityStore: qualityStore,
                            closeSheet: close,
                            selectPlayVariant: selectPlayVariant
                        )
                    } label: {
                        HStack {
                            Label("清晰度", systemImage: qualityStore.qualityButtonSystemImage)
                            Spacer()
                            Text(qualityStore.qualityAccessoryButtonTitle)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("ui.player.quality")
                }

                if detailViewModel.isVideoListenModeEnabled {
                    NavigationLink {
                        SurfaceOnlyVideoListenQueuePage(
                            detailViewModel: detailViewModel,
                            closeSheet: close
                        )
                    } label: {
                        HStack {
                            Label("播放列表", systemImage: "list.bullet")
                            Spacer()
                            Text(detailViewModel.videoListenQueueAccessoryTitle)
                                .foregroundStyle(.secondary)
                        }
                    }

                    NavigationLink {
                        SurfaceOnlyVideoListenPlaybackOrderPage(
                            libraryStore: libraryStore,
                            closeSheet: close
                        )
                    } label: {
                        HStack {
                            Label("播放顺序", systemImage: libraryStore.videoListenPlaybackOrder.systemImage)
                            Spacer()
                            Text(libraryStore.videoListenPlaybackOrder.title)
                                .foregroundStyle(.secondary)
                        }
                    }

                    NavigationLink {
                        SurfaceOnlyVideoListenSleepTimerPage(
                            detailViewModel: detailViewModel,
                            closeSheet: close
                        )
                    } label: {
                        HStack {
                            Label("定时关闭", systemImage: "timer")
                            Spacer()
                            Text(detailViewModel.videoListenSleepTimerAccessoryTitle)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !detailViewModel.isVideoListenModeEnabled {
                    NavigationLink {
                        SurfaceOnlyDanmakuSettingsPage(
                            detailViewModel: detailViewModel,
                            toggleDanmaku: onToggleDanmaku
                        )
                    } label: {
                        Label("弹幕设置", systemImage: "text.bubble")
                    }
                }

                NavigationLink {
                    SurfaceOnlyRateChoicesPage(
                        viewModel: viewModel,
                        closeSheet: close
                    )
                } label: {
                    HStack {
                        Label("倍速", systemImage: "speedometer")
                        Spacer()
                        Text(viewModel.playbackRate.title)
                            .foregroundStyle(.secondary)
                    }
                }

                if showsVideoListenModeToggle {
                    Toggle(isOn: videoListenModeBinding) {
                        Label {
                            HStack(spacing: 8) {
                                Text("听视频")
                                if detailViewModel.isSwitchingVideoListenMode {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }
                        } icon: {
                            Image(systemName: "headphones")
                        }
                    }
                    .disabled(detailViewModel.isSwitchingVideoListenMode)
                }

                if !detailViewModel.isVideoListenModeEnabled {
                    Toggle(isOn: Binding(
                        get: { libraryStore.pictureInPictureEnabled },
                        set: { libraryStore.setPictureInPictureEnabled($0) }
                    )) {
                        Label("画中画播放", systemImage: "pip")
                    }
                }

                Toggle(isOn: Binding(
                    get: { libraryStore.playerPerformanceOverlayEnabled },
                    set: { libraryStore.setPlayerPerformanceOverlayEnabled($0) }
                )) {
                    Label("播放性能诊断", systemImage: "waveform.path.ecg.rectangle")
                }

                Toggle(isOn: Binding(
                    get: { libraryStore.playerControlEdgeScrimEnabled },
                    set: { libraryStore.setPlayerControlEdgeScrimEnabled($0) }
                )) {
                    Label("播放控件边缘遮罩", systemImage: "rectangle.topthird.inset.filled")
                }

                Label("\(mediaFormatLabel)：\(videoFormatTitle)", systemImage: mediaFormatSystemImage)
                    .foregroundStyle(.secondary)

                Label("解码：\(decodeTitle)", systemImage: "cpu")
                    .foregroundStyle(.secondary)

                Toggle(isOn: Binding(
                    get: { libraryStore.forceHardwareDecodeEnabled },
                    set: { libraryStore.setForceHardwareDecodeEnabled($0) }
                )) {
                    Label("硬解优先", systemImage: "cpu")
                }

                Picker(selection: Binding(
                    get: { libraryStore.dolbyVisionRenderingPolicy },
                    set: { libraryStore.setDolbyVisionRenderingPolicy($0) }
                )) {
                    ForEach(DolbyVisionRenderingPolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                } label: {
                    Label("杜比视界渲染", systemImage: "sparkles.tv")
                }
                .pickerStyle(.navigationLink)
            }
            .scrollContentBackground(.hidden)
            .listRowBackground(Color.clear)
            .listStyle(.plain)
            .background(Color.clear)
            .foregroundStyle(.primary)
            .navigationTitle("播放设置")
            .navigationBarTitleDisplayMode(.inline)
        }
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var decodeTitle: String {
        SurfaceOnlyPlaybackFormatText.decodeTitle(for: viewModel.engineDiagnostics)
    }

    private var videoFormatTitle: String {
        SurfaceOnlyPlaybackFormatText.videoFormatTitle(for: viewModel.engineDiagnostics)
    }

    private var showsVideoListenModeToggle: Bool {
        detailViewModel.isVideoListenModeEnabled || detailViewModel.canUseVideoListenMode
    }

    private var videoListenModeBinding: Binding<Bool> {
        Binding(
            get: { detailViewModel.isVideoListenModeEnabled },
            set: { detailViewModel.setVideoListenModeEnabled($0) }
        )
    }

    private var mediaFormatLabel: String {
        detailViewModel.isVideoListenModeEnabled ? "音频格式" : "视频格式"
    }

    private var mediaFormatSystemImage: String {
        detailViewModel.isVideoListenModeEnabled ? "waveform" : "film"
    }

}

private enum SurfaceOnlyPlaybackFormatText {
    static func decodeTitle(for diagnostics: PlayerEngineDiagnostics) -> String {
        var parts = [diagnostics.decodePath.title]
        if diagnostics.hardwareDecodeRequested {
            parts.append("硬解")
        }
        if let isHardwareDecodeCompatible = diagnostics.isHardwareDecodeCompatible {
            parts.append(isHardwareDecodeCompatible ? "硬解兼容" : "硬解不兼容")
        }
        return parts.joined(separator: " · ")
    }

    static func videoFormatTitle(for diagnostics: PlayerEngineDiagnostics) -> String {
        var parts = [String]()
        if let codec = diagnostics.codec, !codec.isEmpty {
            parts.append(codecDisplayName(codec))
        }
        if let resolution = diagnostics.resolution, !resolution.isEmpty {
            parts.append(resolution)
        }
        if let frameRate = diagnostics.frameRate, !frameRate.isEmpty {
            parts.append(frameRate)
        }
        if let dynamicRangeTitle = dynamicRangeTitle(for: diagnostics.dynamicRange) {
            parts.append(dynamicRangeTitle)
        }
        if !parts.isEmpty {
            return parts.joined(separator: " · ")
        }
        let description = diagnostics.compactDescription
        return description.isEmpty ? "未知" : description
    }

    private static func dynamicRangeTitle(for dynamicRange: BiliVideoDynamicRange) -> String? {
        switch dynamicRange {
        case .sdr:
            return nil
        case .hdr10:
            return "HDR"
        case .hlg:
            return "HLG"
        case .dolbyVision:
            return "杜比视界"
        }
    }

    private static func codecDisplayName(_ codec: String) -> String {
        switch codec.uppercased() {
        case "AVC":
            return "H.264 / AVC"
        case "HEVC":
            return "HEVC / H.265"
        default:
            return codec
        }
    }
}

private struct SurfaceOnlyLandscapeMoreControlsOverlay: View {
    @ObservedObject var detailViewModel: VideoDetailViewModel
    @ObservedObject var viewModel: PlayerStateViewModel
    @ObservedObject var libraryStore: LibraryStore
    @ObservedObject var qualityStore: VideoDetailQualityControlRenderStore
    let selectPlayVariant: (PlayVariant) -> Void
    let onToggleDanmaku: () -> Void
    let contentInsets: EdgeInsets
    let close: () -> Void
    @State private var page: SurfaceOnlyLandscapeMoreControlsPage = .root

    var body: some View {
        GeometryReader { proxy in
            let visibleFrame = visibleVideoFrame(in: proxy.size)
            let panelSize = landscapePanelSize(in: visibleFrame)
            ZStack {
                Color.black.opacity(0.04)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: close)

                landscapePanel(size: panelSize)
                    .position(landscapePanelCenter(panelSize: panelSize, visibleFrame: visibleFrame))
                    .contentShape(Rectangle())
                    .onTapGesture {}
            }
        }
    }

    @ViewBuilder
    private func landscapePanel(size: CGSize) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        VStack(spacing: 0) {
            SurfaceOnlyLandscapeMoreHeader(
                title: page.title,
                canGoBack: page != .root,
                goBack: { page = .root },
                close: close
            )

            Divider()

            SurfaceOnlyLandscapeMoreContent(
                page: $page,
                detailViewModel: detailViewModel,
                viewModel: viewModel,
                libraryStore: libraryStore,
                qualityStore: qualityStore,
                selectPlayVariant: selectPlayVariant,
                onToggleDanmaku: onToggleDanmaku,
                close: close
            )
        }
        .frame(width: size.width, height: size.height)
        .surfaceOnlyLandscapeGlassPanel(in: shape)
        .clipShape(shape)
        .overlay {
            shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.6)
        }
        .shadow(color: .black.opacity(0.24), radius: 18, x: 0, y: 10)
    }

    private func visibleVideoFrame(in size: CGSize) -> CGRect {
        CGRect(
            x: contentInsets.leading,
            y: contentInsets.top,
            width: max(1, size.width - contentInsets.leading - contentInsets.trailing),
            height: max(1, size.height - contentInsets.top - contentInsets.bottom)
        )
    }

    private func landscapePanelSize(in visibleFrame: CGRect) -> CGSize {
        let horizontalMargin: CGFloat = 18
        let verticalMargin: CGFloat = 14
        let topOffset: CGFloat = 58
        let availableWidth = max(1, visibleFrame.width - horizontalMargin * 2)
        let width = min(330, availableWidth)
        let availableHeight = max(1, visibleFrame.height - topOffset - verticalMargin)
        let height = min(318, availableHeight)
        return CGSize(width: width, height: height)
    }

    private func landscapePanelCenter(panelSize: CGSize, visibleFrame: CGRect) -> CGPoint {
        let horizontalMargin: CGFloat = 18
        let verticalMargin: CGFloat = 14
        let preferredTop: CGFloat = visibleFrame.minY + 58
        let preferredX = visibleFrame.maxX - horizontalMargin - panelSize.width / 2
        let preferredY = preferredTop + panelSize.height / 2
        return CGPoint(
            x: clamped(
                preferredX,
                lower: visibleFrame.minX + horizontalMargin + panelSize.width / 2,
                upper: visibleFrame.maxX - horizontalMargin - panelSize.width / 2,
                fallback: visibleFrame.midX
            ),
            y: clamped(
                preferredY,
                lower: visibleFrame.minY + verticalMargin + panelSize.height / 2,
                upper: visibleFrame.maxY - verticalMargin - panelSize.height / 2,
                fallback: visibleFrame.midY
            )
        )
    }

    private func clamped(_ value: CGFloat, lower: CGFloat, upper: CGFloat, fallback: CGFloat) -> CGFloat {
        guard lower <= upper else { return fallback }
        return min(max(value, lower), upper)
    }

}

private enum SurfaceOnlyLandscapeMoreControlsPage {
    case root
    case quality
    case audio
    case queue
    case playbackOrder
    case sleepTimer
    case danmaku
    case rate

    var title: String {
        switch self {
        case .root:
            return "播放设置"
        case .quality:
            return "清晰度"
        case .audio:
            return "音质"
        case .queue:
            return "播放列表"
        case .playbackOrder:
            return "播放顺序"
        case .sleepTimer:
            return "定时关闭"
        case .danmaku:
            return "弹幕设置"
        case .rate:
            return "倍速"
        }
    }
}

private struct SurfaceOnlyLandscapeMoreHeader: View {
    let title: String
    let canGoBack: Bool
    let goBack: () -> Void
    let close: () -> Void

    var body: some View {
        ZStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)

            HStack {
                if canGoBack {
                    Button(action: goBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .contentShape(Circle())
                }

                Spacer()

                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .contentShape(Circle())
            }
        }
        .frame(height: 48)
        .padding(.horizontal, 12)
    }
}

private struct SurfaceOnlyLandscapeMoreContent: View {
    @Binding var page: SurfaceOnlyLandscapeMoreControlsPage
    @ObservedObject var detailViewModel: VideoDetailViewModel
    @ObservedObject var viewModel: PlayerStateViewModel
    @ObservedObject var libraryStore: LibraryStore
    @ObservedObject var qualityStore: VideoDetailQualityControlRenderStore
    let selectPlayVariant: (PlayVariant) -> Void
    let onToggleDanmaku: () -> Void
    let close: () -> Void

    var body: some View {
        Group {
            switch page {
            case .root:
                rootPage
            case .quality:
                qualityPage
            case .audio:
                audioPage
            case .queue:
                queuePage
            case .playbackOrder:
                playbackOrderPage
            case .sleepTimer:
                sleepTimerPage
            case .danmaku:
                SurfaceOnlyDanmakuSettingsPage(
                    detailViewModel: detailViewModel,
                    toggleDanmaku: onToggleDanmaku
                )
                .scrollContentBackground(.hidden)
            case .rate:
                ratePage
            }
        }
    }

    private var rootPage: some View {
        ScrollView {
            VStack(spacing: 10) {
                VStack(spacing: 0) {
                    if detailViewModel.isVideoListenModeEnabled,
                       !detailViewModel.videoListenAudioVariants.isEmpty {
                        SurfaceOnlyLandscapeMenuRow(
                            title: "音质",
                            systemImage: "waveform",
                            accessory: detailViewModel.videoListenAudioAccessoryTitle,
                            showsChevron: true
                        ) {
                            page = .audio
                        }

                        Divider().padding(.leading, 44)
                    } else if qualityStore.hasQualityMenu {
                        SurfaceOnlyLandscapeMenuRow(
                            title: "清晰度",
                            systemImage: qualityStore.qualityButtonSystemImage,
                            accessory: qualityStore.qualityAccessoryButtonTitle,
                            showsChevron: true
                        ) {
                            page = .quality
                        }

                        Divider().padding(.leading, 44)
                    }

                    if detailViewModel.isVideoListenModeEnabled {
                        SurfaceOnlyLandscapeMenuRow(
                            title: "播放列表",
                            systemImage: "list.bullet",
                            accessory: detailViewModel.videoListenQueueAccessoryTitle,
                            showsChevron: true
                        ) {
                            page = .queue
                        }

                        Divider().padding(.leading, 44)

                        SurfaceOnlyLandscapeMenuRow(
                            title: "播放顺序",
                            systemImage: libraryStore.videoListenPlaybackOrder.systemImage,
                            accessory: libraryStore.videoListenPlaybackOrder.title,
                            showsChevron: true
                        ) {
                            page = .playbackOrder
                        }

                        Divider().padding(.leading, 44)

                        SurfaceOnlyLandscapeMenuRow(
                            title: "定时关闭",
                            systemImage: "timer",
                            accessory: detailViewModel.videoListenSleepTimerAccessoryTitle,
                            showsChevron: true
                        ) {
                            page = .sleepTimer
                        }

                        Divider().padding(.leading, 44)
                    }

                    if !detailViewModel.isVideoListenModeEnabled {
                        SurfaceOnlyLandscapeMenuRow(
                            title: "弹幕设置",
                            systemImage: "text.bubble",
                            accessory: nil,
                            showsChevron: true
                        ) {
                            page = .danmaku
                        }

                        Divider().padding(.leading, 44)
                    }

                    SurfaceOnlyLandscapeMenuRow(
                        title: "倍速",
                        systemImage: "speedometer",
                        accessory: viewModel.playbackRate.title,
                        showsChevron: true
                    ) {
                        page = .rate
                    }

                    Divider().padding(.leading, 44)

                    if showsVideoListenModeToggle {
                        SurfaceOnlyLandscapeToggleRow(
                            title: "听视频",
                            systemImage: "headphones",
                            accessory: videoListenModeAccessory,
                            isOn: videoListenModeBinding
                        )
                        .disabled(detailViewModel.isSwitchingVideoListenMode)

                        Divider().padding(.leading, 44)
                    }

                    if !detailViewModel.isVideoListenModeEnabled {
                        SurfaceOnlyLandscapeToggleRow(
                            title: "画中画播放",
                            systemImage: "pip",
                            accessory: pictureInPictureAccessory,
                            isOn: Binding(
                                get: { libraryStore.pictureInPictureEnabled },
                                set: { libraryStore.setPictureInPictureEnabled($0) }
                            )
                        )

                        Divider().padding(.leading, 44)
                    }

                    SurfaceOnlyLandscapeToggleRow(
                        title: "播放性能诊断",
                        systemImage: "waveform.path.ecg.rectangle",
                        accessory: performanceOverlayAccessory,
                        isOn: Binding(
                            get: { libraryStore.playerPerformanceOverlayEnabled },
                            set: { libraryStore.setPlayerPerformanceOverlayEnabled($0) }
                        )
                    )

                    Divider().padding(.leading, 44)

                    SurfaceOnlyLandscapeToggleRow(
                        title: "播放控件边缘遮罩",
                        systemImage: "rectangle.topthird.inset.filled",
                        accessory: controlEdgeScrimAccessory,
                        isOn: Binding(
                            get: { libraryStore.playerControlEdgeScrimEnabled },
                            set: { libraryStore.setPlayerControlEdgeScrimEnabled($0) }
                        )
                    )
                }
                .surfaceOnlyLandscapeGlassGroup()

                VStack(spacing: 0) {
                    SurfaceOnlyLandscapeInfoRow(
                        title: mediaFormatLabel,
                        systemImage: mediaFormatSystemImage,
                        value: videoFormatTitle
                    )

                    Divider().padding(.leading, 44)

                    SurfaceOnlyLandscapeInfoRow(
                        title: "解码",
                        systemImage: "cpu",
                        value: decodeTitle
                    )
                }
                .surfaceOnlyLandscapeGlassGroup()
            }
            .padding(12)
        }
    }

    private var qualityPage: some View {
        ScrollView {
            VStack(spacing: 10) {
                if qualityStore.isSwitchingPlayQuality {
                    SurfaceOnlyQualitySwitchingIndicator()
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .surfaceOnlyLandscapeGlassGroup()
                }

                VStack(spacing: 0) {
                    ForEach(Array(qualityStore.qualityMenuItems.enumerated()), id: \.element.id) { index, item in
                        SurfaceOnlyLandscapeMenuRow(
                            title: item.title,
                            subtitle: item.subtitle,
                            systemImage: item.systemImage,
                            accessory: nil,
                            showsChevron: false
                        ) {
                            selectPlayVariant(item.variant)
                            close()
                        }
                        .disabled(item.isDisabled)
                        .opacity(item.isDisabled ? 0.45 : 1)

                        if index < qualityStore.qualityMenuItems.count - 1 {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
                .surfaceOnlyLandscapeGlassGroup()
            }
            .padding(12)
        }
    }

    private var audioPage: some View {
        ScrollView {
            VStack(spacing: 10) {
                if detailViewModel.isSwitchingVideoListenMode {
                    SurfaceOnlyAudioSwitchingIndicator()
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .surfaceOnlyLandscapeGlassGroup()
                }

                VStack(spacing: 0) {
                    SurfaceOnlyLandscapeMenuRow(
                        title: "自动",
                        subtitle: automaticAudioSubtitle,
                        systemImage: detailViewModel.selectedVideoListenAudioPreferenceKey == nil
                            ? "checkmark"
                            : "wand.and.stars",
                        accessory: nil,
                        showsChevron: false
                    ) {
                        detailViewModel.selectVideoListenAudioVariant(nil)
                        close()
                    }

                    if !detailViewModel.videoListenAudioVariants.isEmpty {
                        Divider().padding(.leading, 44)
                    }

                    ForEach(Array(detailViewModel.videoListenAudioVariants.enumerated()), id: \.element.id) { index, variant in
                        SurfaceOnlyLandscapeMenuRow(
                            title: variant.title,
                            subtitle: variant.subtitle,
                            systemImage: detailViewModel.selectedVideoListenAudioPreferenceKey == variant.preferenceKey
                                ? "checkmark"
                                : variant.systemImage,
                            accessory: nil,
                            showsChevron: false
                        ) {
                            detailViewModel.selectVideoListenAudioVariant(variant)
                            close()
                        }

                        if index < detailViewModel.videoListenAudioVariants.count - 1 {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
                .surfaceOnlyLandscapeGlassGroup()
            }
            .padding(12)
        }
    }

    private var ratePage: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(BiliPlaybackRate.allCases.enumerated()), id: \.element.id) { index, rate in
                    SurfaceOnlyLandscapeMenuRow(
                        title: rate.title,
                        systemImage: rate == viewModel.playbackRate ? "checkmark" : "speedometer",
                        accessory: nil,
                        showsChevron: false
                    ) {
                        viewModel.setPlaybackRate(rate)
                        close()
                    }

                    if index < BiliPlaybackRate.allCases.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .surfaceOnlyLandscapeGlassGroup()
            .padding(12)
        }
    }

    private var queuePage: some View {
        ScrollView {
            if detailViewModel.videoListenQueueEntries.isEmpty {
                VStack(spacing: 10) {
                    if detailViewModel.isLoadingVideoListenQueue {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在载入播放列表")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(detailViewModel.videoListenQueueLoadFailed ? "播放列表载入失败" : "没有可播放内容")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if detailViewModel.videoListenQueueLoadFailed {
                            Button("重新载入") {
                                Task {
                                    await detailViewModel.prepareVideoListenQueue()
                                }
                            }
                            .font(.subheadline.weight(.semibold))
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .surfaceOnlyLandscapeGlassGroup()
                .padding(12)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(detailViewModel.videoListenQueueEntries.enumerated()), id: \.element.id) { index, entry in
                        SurfaceOnlyLandscapeMenuRow(
                            title: entry.title,
                            subtitle: entry.subtitle,
                            systemImage: entry.isCurrent ? "checkmark.circle.fill" : "play.circle",
                            accessory: entry.isCurrent ? "正在播放" : nil,
                            showsChevron: false
                        ) {
                            detailViewModel.selectVideoListenQueueEntry(entry)
                            close()
                        }
                        .task {
                            await detailViewModel.loadMoreVideoListenQueueIfNeeded(current: entry)
                        }

                        if index < detailViewModel.videoListenQueueEntries.count - 1 {
                            Divider().padding(.leading, 44)
                        }
                    }

                    if detailViewModel.isLoadingVideoListenQueue {
                        Divider().padding(.leading, 44)
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("正在载入更多视频")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    } else if detailViewModel.videoListenQueueLoadFailed,
                              detailViewModel.videoListenQueueEntries.count <= 1 {
                        Divider().padding(.leading, 44)
                        Button("重新载入播放列表") {
                            Task {
                                await detailViewModel.prepareVideoListenQueue()
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    } else if detailViewModel.videoListenQueueSession.isLoadingMore {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                }
                .surfaceOnlyLandscapeGlassGroup()
                .padding(12)
            }
        }
        .task {
            await detailViewModel.prepareVideoListenQueue()
        }
    }

    private var playbackOrderPage: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(VideoListenPlaybackOrder.allCases.enumerated()), id: \.element.id) { index, order in
                    SurfaceOnlyLandscapeMenuRow(
                        title: order.title,
                        subtitle: order.subtitle,
                        systemImage: libraryStore.videoListenPlaybackOrder == order
                            ? "checkmark.circle.fill"
                            : order.systemImage,
                        accessory: nil,
                        showsChevron: false
                    ) {
                        libraryStore.setVideoListenPlaybackOrder(order)
                        close()
                    }

                    if index < VideoListenPlaybackOrder.allCases.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .surfaceOnlyLandscapeGlassGroup()
            .padding(12)
        }
    }

    private var sleepTimerPage: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(VideoListenSleepTimerOption.allCases.enumerated()), id: \.element.id) { index, option in
                    SurfaceOnlyLandscapeMenuRow(
                        title: option.title,
                        systemImage: detailViewModel.videoListenSleepTimerOption == option
                            ? "checkmark.circle.fill"
                            : option.systemImage,
                        accessory: nil,
                        showsChevron: false
                    ) {
                        detailViewModel.setVideoListenSleepTimer(option)
                        close()
                    }

                    if index < VideoListenSleepTimerOption.allCases.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .surfaceOnlyLandscapeGlassGroup()
            .padding(12)
        }
    }

    private var decodeTitle: String {
        SurfaceOnlyPlaybackFormatText.decodeTitle(for: viewModel.engineDiagnostics)
    }

    private var videoFormatTitle: String {
        SurfaceOnlyPlaybackFormatText.videoFormatTitle(for: viewModel.engineDiagnostics)
    }

    private var pictureInPictureAccessory: String? {
        return libraryStore.pictureInPictureEnabled ? "已开启" : "已关闭"
    }

    private var showsVideoListenModeToggle: Bool {
        detailViewModel.isVideoListenModeEnabled || detailViewModel.canUseVideoListenMode
    }

    private var videoListenModeBinding: Binding<Bool> {
        Binding(
            get: { detailViewModel.isVideoListenModeEnabled },
            set: { detailViewModel.setVideoListenModeEnabled($0) }
        )
    }

    private var videoListenModeAccessory: String? {
        if detailViewModel.isSwitchingVideoListenMode {
            return "切换中"
        }
        return detailViewModel.isVideoListenModeEnabled ? "已开启" : "已关闭"
    }

    private var automaticAudioSubtitle: String {
        guard let variant = detailViewModel.automaticVideoListenAudioVariant else {
            return "优先选择兼容性较好的音轨"
        }
        return ["当前 \(variant.title)", variant.subtitle]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var mediaFormatLabel: String {
        detailViewModel.isVideoListenModeEnabled ? "音频格式" : "视频格式"
    }

    private var mediaFormatSystemImage: String {
        detailViewModel.isVideoListenModeEnabled ? "waveform" : "film"
    }

    private var performanceOverlayAccessory: String? {
        return libraryStore.playerPerformanceOverlayEnabled ? "已开启" : "已关闭"
    }

    private var controlEdgeScrimAccessory: String? {
        return libraryStore.playerControlEdgeScrimEnabled ? "已开启" : "已关闭"
    }
}

private struct SurfaceOnlyLandscapeToggleRow: View {
    let title: String
    let systemImage: String
    let accessory: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)

                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if let accessory {
                    Text(accessory)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(minHeight: 44)
            .padding(.leading, 12)
        }
        .toggleStyle(.switch)
        .padding(.trailing, 12)
        .contentShape(Rectangle())
    }
}

private struct SurfaceOnlyLandscapeMenuRow: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let accessory: String?
    let showsChevron: Bool
    let action: () -> Void

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        accessory: String?,
        showsChevron: Bool,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.accessory = accessory
        self.showsChevron = showsChevron
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if let accessory {
                    Text(accessory)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SurfaceOnlyLandscapeInfoRow: View {
    let title: String
    let systemImage: String
    let value: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let value {
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 12)
    }
}

private struct SurfaceOnlyQualityChoicesPage: View {
    @ObservedObject var qualityStore: VideoDetailQualityControlRenderStore
    let closeSheet: () -> Void
    let selectPlayVariant: (PlayVariant) -> Void

    var body: some View {
        List {
            if qualityStore.isSwitchingPlayQuality {
                SurfaceOnlyQualitySwitchingIndicator()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            }

            ForEach(qualityStore.qualityMenuItems) { item in
                Button {
                    selectPlayVariant(item.variant)
                    closeSheet()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                            if let subtitle = item.subtitle, !subtitle.isEmpty {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: item.systemImage)
                    }
                }
                .disabled(item.isDisabled)
            }
        }
        .scrollContentBackground(.hidden)
        .listRowBackground(Color.clear)
        .listStyle(.plain)
        .background(Color.clear)
        .foregroundStyle(.primary)
        .navigationTitle("清晰度")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.automatic, for: .navigationBar)
    }
}

private struct SurfaceOnlyAudioChoicesPage: View {
    @ObservedObject var detailViewModel: VideoDetailViewModel
    let closeSheet: () -> Void

    var body: some View {
        List {
            if detailViewModel.isSwitchingVideoListenMode {
                SurfaceOnlyAudioSwitchingIndicator()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            }

            Button {
                detailViewModel.selectVideoListenAudioVariant(nil)
                closeSheet()
            } label: {
                audioChoiceLabel(
                    title: "自动",
                    subtitle: automaticSubtitle,
                    systemImage: detailViewModel.selectedVideoListenAudioPreferenceKey == nil
                        ? "checkmark"
                        : "wand.and.stars"
                )
            }

            ForEach(detailViewModel.videoListenAudioVariants) { variant in
                Button {
                    detailViewModel.selectVideoListenAudioVariant(variant)
                    closeSheet()
                } label: {
                    audioChoiceLabel(
                        title: variant.title,
                        subtitle: variant.subtitle,
                        systemImage: detailViewModel.selectedVideoListenAudioPreferenceKey == variant.preferenceKey
                            ? "checkmark"
                            : variant.systemImage
                    )
                }
            }
        }
        .scrollContentBackground(.hidden)
        .listRowBackground(Color.clear)
        .listStyle(.plain)
        .background(Color.clear)
        .foregroundStyle(.primary)
        .navigationTitle("音质")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.automatic, for: .navigationBar)
    }

    private func audioChoiceLabel(
        title: String,
        subtitle: String,
        systemImage: String
    ) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: systemImage)
        }
    }

    private var automaticSubtitle: String {
        guard let variant = detailViewModel.automaticVideoListenAudioVariant else {
            return "优先选择兼容性较好的音轨"
        }
        return ["当前 \(variant.title)", variant.subtitle]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

private struct SurfaceOnlyVideoListenQueuePage: View {
    @ObservedObject var detailViewModel: VideoDetailViewModel
    let closeSheet: () -> Void

    var body: some View {
        List {
            if detailViewModel.videoListenQueueEntries.isEmpty {
                VStack(spacing: 10) {
                    if detailViewModel.isLoadingVideoListenQueue {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在载入播放列表")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(detailViewModel.videoListenQueueLoadFailed ? "播放列表载入失败" : "没有可播放内容")
                            .foregroundStyle(.secondary)
                        if detailViewModel.videoListenQueueLoadFailed {
                            Button("重新载入") {
                                Task {
                                    await detailViewModel.prepareVideoListenQueue()
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                ForEach(detailViewModel.videoListenQueueEntries) { entry in
                    Button {
                        detailViewModel.selectVideoListenQueueEntry(entry)
                        closeSheet()
                    } label: {
                        Label {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.title)
                                    if let subtitle = entry.subtitle {
                                        Text(subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if entry.isCurrent {
                                    Text("正在播放")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: entry.isCurrent ? "checkmark.circle.fill" : "play.circle")
                        }
                    }
                    .task {
                        await detailViewModel.loadMoreVideoListenQueueIfNeeded(current: entry)
                    }
                }

                if detailViewModel.isLoadingVideoListenQueue {
                    HStack(spacing: 8) {
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                        Text("正在载入更多视频")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                } else if detailViewModel.videoListenQueueLoadFailed,
                          detailViewModel.videoListenQueueEntries.count <= 1 {
                    Button("重新载入播放列表") {
                        Task {
                            await detailViewModel.prepareVideoListenQueue()
                        }
                    }
                    .frame(maxWidth: .infinity)
                } else if detailViewModel.videoListenQueueSession.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                        Spacer()
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .listRowBackground(Color.clear)
        .listStyle(.plain)
        .background(Color.clear)
        .foregroundStyle(.primary)
        .navigationTitle("播放列表")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.automatic, for: .navigationBar)
        .task {
            await detailViewModel.prepareVideoListenQueue()
        }
    }
}

private struct SurfaceOnlyVideoListenPlaybackOrderPage: View {
    @ObservedObject var libraryStore: LibraryStore
    let closeSheet: () -> Void

    var body: some View {
        List {
            ForEach(VideoListenPlaybackOrder.allCases) { order in
                Button {
                    libraryStore.setVideoListenPlaybackOrder(order)
                    closeSheet()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(order.title)
                            Text(order.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: libraryStore.videoListenPlaybackOrder == order
                            ? "checkmark.circle.fill"
                            : order.systemImage)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .listRowBackground(Color.clear)
        .listStyle(.plain)
        .background(Color.clear)
        .foregroundStyle(.primary)
        .navigationTitle("播放顺序")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.automatic, for: .navigationBar)
    }
}

private struct SurfaceOnlyVideoListenSleepTimerPage: View {
    @ObservedObject var detailViewModel: VideoDetailViewModel
    let closeSheet: () -> Void

    var body: some View {
        List {
            ForEach(VideoListenSleepTimerOption.allCases) { option in
                Button {
                    detailViewModel.setVideoListenSleepTimer(option)
                    closeSheet()
                } label: {
                    Label(
                        option.title,
                        systemImage: detailViewModel.videoListenSleepTimerOption == option
                            ? "checkmark.circle.fill"
                            : option.systemImage
                    )
                }
            }
        }
        .scrollContentBackground(.hidden)
        .listRowBackground(Color.clear)
        .listStyle(.plain)
        .background(Color.clear)
        .foregroundStyle(.primary)
        .navigationTitle("定时关闭")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.automatic, for: .navigationBar)
    }
}

private struct SurfaceOnlyQualitySwitchingIndicator: View {
    var body: some View {
        PlayerInlineLoadingIndicator(message: "正在切换清晰度")
            .accessibilityLabel("正在切换清晰度")
    }
}

private struct SurfaceOnlyAudioSwitchingIndicator: View {
    var body: some View {
        PlayerInlineLoadingIndicator(message: "正在切换音质")
            .accessibilityLabel("正在切换音质")
    }
}

private struct SurfaceOnlyDanmakuSettingsPage: View {
    @ObservedObject var detailViewModel: VideoDetailViewModel
    let toggleDanmaku: () -> Void

    var body: some View {
        DanmakuSettingsSheetContent(
            store: detailViewModel.danmakuSettingsRenderStore,
            summary: settingsSummary,
            displayAreaBinding: displayAreaBinding,
            hidesDanmakuInPortraitBinding: hidesDanmakuInPortraitBinding,
            fontScaleBinding: fontScaleBinding,
            fontWeightBinding: fontWeightBinding,
            opacityBinding: opacityBinding,
            toggleDanmaku: toggleDanmaku
        )
        .scrollContentBackground(.hidden)
        .listRowBackground(Color.clear)
        .listStyle(.plain)
        .background(Color.clear)
        .navigationTitle("弹幕设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.automatic, for: .navigationBar)
    }

    private var settingsSummary: String {
        let store = detailViewModel.danmakuSettingsRenderStore
        if store.isDanmakuEnabled {
            return "当前使用 \(store.danmakuSettings.displayArea.title)，字号 \(Int((store.danmakuSettings.fontScale * 100).rounded()))%，不透明度 \(Int((store.danmakuSettings.opacity * 100).rounded()))%。"
        }
        return "弹幕已关闭，播放时不会显示滚动评论。"
    }

    private var displayAreaBinding: Binding<DanmakuDisplayArea> {
        Binding(
            get: { detailViewModel.danmakuSettingsRenderStore.danmakuSettings.displayArea },
            set: { newValue in
                var settings = detailViewModel.danmakuSettingsRenderStore.danmakuSettings
                settings.displayArea = newValue
                detailViewModel.updateDanmakuSettings(settings)
            }
        )
    }

    private var fontScaleBinding: Binding<Double> {
        Binding(
            get: { detailViewModel.danmakuSettingsRenderStore.danmakuSettings.fontScale },
            set: { newValue in
                var settings = detailViewModel.danmakuSettingsRenderStore.danmakuSettings
                settings.fontScale = newValue
                detailViewModel.updateDanmakuSettings(settings)
            }
        )
    }

    private var hidesDanmakuInPortraitBinding: Binding<Bool> {
        Binding(
            get: { detailViewModel.danmakuSettingsRenderStore.danmakuSettings.hidesInPortrait },
            set: { newValue in
                var settings = detailViewModel.danmakuSettingsRenderStore.danmakuSettings
                settings.hidesInPortrait = newValue
                detailViewModel.updateDanmakuSettings(settings)
            }
        )
    }

    private var fontWeightBinding: Binding<DanmakuFontWeightOption> {
        Binding(
            get: { detailViewModel.danmakuSettingsRenderStore.danmakuSettings.fontWeight },
            set: { newValue in
                var settings = detailViewModel.danmakuSettingsRenderStore.danmakuSettings
                settings.fontWeight = newValue
                detailViewModel.updateDanmakuSettings(settings)
            }
        )
    }

    private var opacityBinding: Binding<Double> {
        Binding(
            get: { detailViewModel.danmakuSettingsRenderStore.danmakuSettings.opacity },
            set: { newValue in
                var settings = detailViewModel.danmakuSettingsRenderStore.danmakuSettings
                settings.opacity = newValue
                detailViewModel.updateDanmakuSettings(settings)
            }
        )
    }
}

private struct SurfaceOnlyUIKitMoreControlsButton: UIViewRepresentable {
    let metrics: PlayerNativeControlMetrics
    let systemImageName: String
    let onPressBegan: () -> Void
    let onPressEnded: () -> Void
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onPressBegan: onPressBegan,
            onPressEnded: onPressEnded,
            action: action
        )
    }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(
            configuration: configuration,
            primaryAction: context.coordinator.primaryAction
        )
        configure(button)
        button.addAction(context.coordinator.pressBeganAction, for: .touchDown)
        button.addAction(
            context.coordinator.pressEndedAction,
            for: [.touchUpInside, .touchUpOutside, .touchCancel]
        )
        button.accessibilityLabel = "更多播放设置"
        button.accessibilityIdentifier = "ui.player.more"
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.onPressBegan = onPressBegan
        context.coordinator.onPressEnded = onPressEnded
        context.coordinator.action = action
        configure(button)
    }

    private var configuration: UIButton.Configuration {
        var configuration = UIButton.Configuration.clearGlass()
        configuration.baseForegroundColor = .white
        configuration.contentInsets = .zero
        return configuration
    }

    private func configure(_ button: UIButton) {
        button.configuration = configuration
        button.tintColor = .white

        let iconView: UIImageView
        if let existingIconView = button.viewWithTag(Self.iconViewTag) as? UIImageView {
            iconView = existingIconView
        } else {
            iconView = UIImageView()
            iconView.tag = Self.iconViewTag
            iconView.contentMode = .center
            iconView.tintColor = .white
            iconView.isUserInteractionEnabled = false
            iconView.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(iconView)
            NSLayoutConstraint.activate([
                iconView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                iconView.centerYAnchor.constraint(equalTo: button.centerYAnchor)
            ])
        }

        iconView.image = UIImage(
            systemName: systemImageName,
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: metrics.iconSize + 3,
                weight: .semibold
            )
        )
    }

    private static let iconViewTag = 1_634_081

    final class Coordinator {
        var onPressBegan: () -> Void
        var onPressEnded: () -> Void
        var action: () -> Void

        init(
            onPressBegan: @escaping () -> Void,
            onPressEnded: @escaping () -> Void,
            action: @escaping () -> Void
        ) {
            self.onPressBegan = onPressBegan
            self.onPressEnded = onPressEnded
            self.action = action
        }

        lazy var pressBeganAction = UIAction { [weak self] _ in
            self?.onPressBegan()
        }

        lazy var pressEndedAction = UIAction { [weak self] _ in
            self?.onPressEnded()
        }

        lazy var primaryAction = UIAction { [weak self] _ in
            self?.action()
        }
    }
}

private struct VideoDetailFullscreenClockControl: View {

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Text(context.date, format: .dateTime.hour().minute())
                .font(.caption.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: PlayerNativeControlMetrics.landscape.controlHeight)
        }
        .biliPlayerClearGlass(
            interactive: false,
            in: Capsule(),
            isEnabled: true
        )
        .biliLiquidGlassForeground(shadowOpacity: 0.20)
        .allowsHitTesting(false)
        .accessibilityLabel("系统时间")
    }
}

private struct VideoDetailFullscreenBatteryControl: View {
    @State private var batteryLevel: Float = -1

    var body: some View {
        HStack(spacing: 4) {
            Text(percentageText)
                .monospacedDigit()
            Image(systemName: batterySymbolName)
        }
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(height: PlayerNativeControlMetrics.landscape.controlHeight)
        .biliPlayerClearGlass(
            interactive: false,
            in: Capsule(),
            isEnabled: true
        )
        .biliLiquidGlassForeground(shadowOpacity: 0.20)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("设备电量 \(percentageText)")
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            updateBatteryLevel()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)) { _ in
            updateBatteryLevel()
        }
        .onDisappear {
            UIDevice.current.isBatteryMonitoringEnabled = false
        }
    }

    private var percentage: Int? {
        guard batteryLevel >= 0 else { return nil }
        return min(max(Int((batteryLevel * 100).rounded()), 0), 100)
    }

    private var percentageText: String {
        percentage.map { "\($0)%" } ?? "--%"
    }

    private var batterySymbolName: String {
        guard let percentage else { return "battery.0percent" }
        switch percentage {
        case 76...:
            return "battery.100percent"
        case 51...:
            return "battery.75percent"
        case 26...:
            return "battery.50percent"
        case 1...:
            return "battery.25percent"
        default:
            return "battery.0percent"
        }
    }

    private func updateBatteryLevel() {
        batteryLevel = UIDevice.current.batteryLevel
    }
}

private extension View {
    @ViewBuilder
    func surfaceOnlyLandscapeGlassPanel<S: Shape>(in shape: S) -> some View {
        self
            .background(Color(.systemBackground).opacity(0.22), in: shape)
            .biliGlassEffect(
                interactive: false,
                in: shape
            )
    }

    @ViewBuilder
    func surfaceOnlyLandscapeGlassGroup() -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        self
            .background(Color(.secondarySystemGroupedBackground).opacity(0.34), in: shape)
            .biliPlayerClearGlass(interactive: false, in: shape)
    }
}

private struct SurfaceOnlyRateChoicesPage: View {
    @ObservedObject var viewModel: PlayerStateViewModel
    let closeSheet: () -> Void

    var body: some View {
        List {
            ForEach(BiliPlaybackRate.allCases) { rate in
                Button {
                    viewModel.setPlaybackRate(rate)
                    closeSheet()
                } label: {
                    Label(
                        rate.title,
                        systemImage: rate == viewModel.playbackRate ? "checkmark" : "speedometer"
                    )
                }
            }
        }
        .scrollContentBackground(.hidden)
        .listRowBackground(Color.clear)
        .listStyle(.plain)
        .background(Color.clear)
        .foregroundStyle(.primary)
        .navigationTitle("倍速")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.automatic, for: .navigationBar)
    }
}

import AVFoundation
import Combine
import QuartzCore
import SwiftUI
import UIKit

/// 直播详情的 UIKit 播放外壳。
///
/// 页面结构、播放器挂载和旋转恢复路径与视频详情保持一致；直播专属的
/// 拉流、清晰度、线路和弹幕仍由 `LiveRoomViewModel` 与 surface host 管理。
@MainActor
final class LiveRoomShellViewController: UIViewController {
    private let viewModel: LiveRoomViewModel
    private let dependencies: AppDependencies
    private let onNavigateBack: () -> Void
    private let playerContainer = UIView()
    private let contentState: LiveRoomShellContentView.State
    private let backdropHost: UIHostingController<LiveRoomVisualBackdrop>
    private let contentHost: UIHostingController<LiveRoomShellContentView>
    private let loadingHost: UIHostingController<LiveRoomShellLoadingOverlay>
    private var rotationRecoveryDisplayLink: CADisplayLink?
    private var deferredLiveRenderReleaseTask: Task<Void, Never>?
    private var pendingRotationPreparation: (() -> Void)?
    private var pendingRotationRecovery: (() -> Void)?
    private var pendingRotationGeneration: Int?
    private var rotationRecoveryNotBefore: TimeInterval?
    private var rotationGeneration = 0
    private var rotationProbeGeneration = 0
    private var isSystemRotationTransitioning = false
    private var lastRotationSurfaceLayoutSize: CGSize?
    private var isViewActive = false
    private weak var attachedNavigationController: UINavigationController?
    private var configuredContentPopID: ObjectIdentifier?
    private var configuredScrollPanIDs = Set<ObjectIdentifier>()
    private let rotationFrameProbe = VideoRotationFrameProbe()
    private var cancellables = Set<AnyCancellable>()
    private var activePlayerPresentationSizeCancellable: AnyCancellable?
    private var actualVideoAspectRatio: CGFloat?
    private var surfaceVideoAspectRatio: CGFloat = 16.0 / 9.0
    /// 竖向直播的全屏态：播放器覆盖直播详情，但设备保持竖屏。
    private var isPortraitFullscreen = false

    private lazy var playerSurfaceController: PlayerSurfaceController = {
        PlayerSurfaceController(
            parentViewController: self,
            containerView: playerContainer,
            makeHost: { [weak self] playerViewModel in
                guard let self else { return nil }
                return LiveRoomSurfaceHost(
                    playerViewModel: playerViewModel,
                    viewModel: self.viewModel,
                    dependencies: self.dependencies,
                    onRequestFullscreen: { [weak self] _ in
                        self?.requestFullscreen()
                    },
                    onExitFullscreen: { [weak self] _ in
                        self?.requestExitFullscreen()
                    },
                    onNavigateBack: { [weak self] in
                        self?.handleBackButton()
                    }
                )
            },
            onActivePlayerChange: { [weak self] playerViewModel in
                self?.observeActivePlayerPresentationSize(playerViewModel)
            }
        )
    }()

    init(
        viewModel: LiveRoomViewModel,
        dependencies: AppDependencies,
        onNavigateBack: @escaping () -> Void
    ) {
        let contentState = LiveRoomShellContentView.State(
            chatStore: viewModel.liveDanmakuRenderStore,
            rotationState: viewModel.liveRotationSurfaceAlignmentState
        )
        self.viewModel = viewModel
        self.dependencies = dependencies
        self.onNavigateBack = onNavigateBack
        self.contentState = contentState
        self.backdropHost = UIHostingController(
            rootView: LiveRoomVisualBackdrop()
        )
        self.contentHost = UIHostingController(
            rootView: LiveRoomShellContentView(
                viewModel: viewModel,
                state: contentState,
                onNavigateBack: onNavigateBack
            )
        )
        self.loadingHost = UIHostingController(
            rootView: LiveRoomShellLoadingOverlay(viewModel: viewModel)
        )
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        AppOrientationLock.supportedOrientations
    }

    override var prefersStatusBarHidden: Bool {
        hidesSystemChrome
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        guard !hidesSystemChrome,
              traitCollection.userInterfaceStyle != .dark
        else {
            return .lightContent
        }
        return .darkContent
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        hidesSystemChrome
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        applyAppearanceMode(dependencies.libraryStore.appearanceMode)
        view.backgroundColor = .systemGroupedBackground
        playerContainer.backgroundColor = .black

        backdropHost.view.backgroundColor = .systemGroupedBackground
        backdropHost.view.isOpaque = true
        backdropHost.view.isUserInteractionEnabled = false
        contentHost.view.backgroundColor = .clear
        loadingHost.view.backgroundColor = .clear
        loadingHost.view.isOpaque = false
        if #available(iOS 16.4, *) {
            backdropHost.safeAreaRegions = []
            contentHost.safeAreaRegions = []
            loadingHost.safeAreaRegions = []
        }

        addChild(backdropHost)
        view.addSubview(backdropHost.view)
        backdropHost.didMove(toParent: self)

        addChild(contentHost)
        view.addSubview(contentHost.view)
        contentHost.didMove(toParent: self)

        view.addSubview(playerContainer)
        addChild(loadingHost)
        playerContainer.addSubview(loadingHost.view)
        loadingHost.didMove(toParent: self)

        viewModel.$playerViewModel
            .receive(on: RunLoop.main)
            .sink { [weak self] playerViewModel in
                self?.loadingHost.view.isUserInteractionEnabled = playerViewModel == nil
            }
            .store(in: &cancellables)

        dependencies.libraryStore.$appearanceMode
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] mode in
                self?.applyAppearanceMode(mode)
            }
            .store(in: &cancellables)

        registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
            (viewController: LiveRoomShellViewController, _) in
            viewController.updatePlaybackSystemChrome()
        }

        bindPlayerSurface()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isViewActive = true
        updatePlaybackSystemChrome()
        updateOrientationLock()
        restoreSystemBackGestures()
        restoreSystemBackGesturesSoon()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isViewActive = false
        cancelPendingRotationRecovery()
        cancelActiveRotationPresentationIfNeeded()
        resumeDeferredLiveRenderUpdates()
        playerSurfaceController.cancelRotationChromePrewarm()
        rotationFrameProbe.cancel()
        AppOrientationLock.restorePortrait(in: view.window?.windowScene)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        isViewActive = false
        cancelPendingRotationRecovery()
        cancelActiveRotationPresentationIfNeeded()
        resumeDeferredLiveRenderUpdates()
        playerSurfaceController.cancelRotationChromePrewarm()
        AppOrientationLock.restorePortrait(in: view.window?.windowScene)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if isSystemRotationTransitioning {
            applyRotationSurfaceLayout()
        } else {
            applyLayout()
        }
        restoreSystemBackGestures()
    }

    override func viewWillTransition(
        to size: CGSize,
        with coordinator: UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)
        let toLandscape = size.width > size.height
        let targetUsesLandscapeFullscreen = usesLandscapeLiveFullscreen(forLandscape: toLandscape)
        rotationGeneration &+= 1
        let generation = rotationGeneration
        cancelPendingRotationRecovery()
        cancelDeferredLiveRenderRelease()
        playerSurfaceController.cancelRotationChromePrewarm()
        lastRotationSurfaceLayoutSize = nil
        startRotationFrameProbe(
            toLandscape: toLandscape,
            coordinator: coordinator
        )
        PlaybackDetailPerformanceMonitor.shared.mark(
            .fullscreenTransitionStarted,
            context: performanceContext,
            detail: "to=\(toLandscape ? "landscape" : "portrait")"
        )

        let rotationPolicy = LiveRotationSurfaceStabilityPolicy()
        let retainsChromeTree = rotationPolicy.retainsChromeTree()
        // Both directions must keep the live chat host out of the system
        // transaction. On landscape -> portrait, revealing it here used to
        // re-layout the blurred background and chat list on rotation frames.
        contentHost.view.isHidden = rotationPolicy.hidesContentHost(
            duringTransitionToLandscape: toLandscape
        )
        contentHost.view.isUserInteractionEnabled = rotationPolicy.allowsContentHostInteraction(
            duringTransitionToLandscape: toLandscape
        )
        isSystemRotationTransitioning = true
        contentState.setChatUpdatesDeferred(true)
        viewModel.liveDanmakuRenderStore.setRenderedUpdatesDeferred(true)
        setBareSurfaceTransitionActive(true, retainsChromeTree: retainsChromeTree)
        // 提前切换隐藏的控件树，把首次布局成本移出系统结束帧。
        playerSurfaceController.setLandscape(targetUsesLandscapeFullscreen)
        playerSurfaceController.setPortraitFullscreen(isPortraitFullscreen)
        rotationFrameProbe.mark("旋转开始：目标方向控件已预热")

        coordinator.animate(alongsideTransition: { [weak self] _ in
            guard let self else { return }
            self.rotationFrameProbe.mark("系统动画布局开始")
            self.applyRotationSurfaceLayout(forBoundsSize: size)
            self.playerContainer.layoutIfNeeded()
            self.refreshSurfaceLayoutImmediately()
            self.setNeedsStatusBarAppearanceUpdate()
            self.setNeedsUpdateOfHomeIndicatorAutoHidden()
            self.rotationFrameProbe.mark("系统动画布局完成")
        }, completion: { [weak self] _ in
            guard let self, self.rotationGeneration == generation else { return }
            self.finishSystemRotation(toLandscape: toLandscape, generation: generation)
        })
    }

    private var isLandscape: Bool {
        view.bounds.width > view.bounds.height
    }

    private var usesLandscapeLiveFullscreen: Bool {
        usesLandscapeLiveFullscreen(forLandscape: isLandscape)
    }

    private var isLiveFullscreenActive: Bool {
        usesLandscapeLiveFullscreen || isPortraitFullscreen
    }

    private var hidesSystemChrome: Bool {
        isLiveFullscreenActive
    }

    private var isPortraitLiveVideo: Bool {
        LiveRoomVideoDetailLayoutPolicy.supportsPortraitFullscreen(
            videoAspectRatio: actualVideoAspectRatio
        )
    }

    private func usesLandscapeLiveFullscreen(forLandscape landscape: Bool) -> Bool {
        return LiveRoomVideoDetailLayoutPolicy.usesLandscapeFullscreen(
            isLandscape: landscape,
            videoAspectRatio: actualVideoAspectRatio
        )
    }

    private var performanceContext: PlaybackDetailPerformanceContext {
        .live(roomID: viewModel.roomID, title: viewModel.title)
    }

    private func updateOrientationLock() {
        guard isViewActive else { return }
        let scene = view.window?.windowScene
        if isPortraitLiveVideo {
            AppOrientationLock.update(to: .portrait, in: scene)
            if isLandscape {
                AppOrientationLock.requestGeometryUpdate(to: .portrait, in: scene)
            }
        } else {
            AppOrientationLock.update(to: .allButUpsideDown, in: scene)
        }
    }

    private func updatePlaybackSystemChrome() {
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
    }

    private func applyAppearanceMode(_ mode: AppAppearanceMode) {
        let style: UIUserInterfaceStyle
        switch mode {
        case .system:
            style = .unspecified
        case .light:
            style = .light
        case .dark:
            style = .dark
        }
        guard overrideUserInterfaceStyle != style else { return }
        overrideUserInterfaceStyle = style
        backdropHost.overrideUserInterfaceStyle = style
        contentHost.overrideUserInterfaceStyle = style
        loadingHost.overrideUserInterfaceStyle = style
        setNeedsStatusBarAppearanceUpdate()
    }

    private func observeActivePlayerPresentationSize(_ playerViewModel: PlayerStateViewModel?) {
        activePlayerPresentationSizeCancellable = nil
        actualVideoAspectRatio = nil
        applyLiveVideoPresentationSize(.zero)

        guard let playerViewModel else { return }
        activePlayerPresentationSizeCancellable = playerViewModel.$videoPresentationSize
            .receive(on: RunLoop.main)
            .sink { [weak self] size in
                self?.applyLiveVideoPresentationSize(size)
            }
    }

    private func applyLiveVideoPresentationSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else {
            actualVideoAspectRatio = nil
            viewModel.liveRotationSurfaceAlignmentState.updatePresentationSize(.zero)
            surfaceVideoAspectRatio = 16.0 / 9.0
            if isPortraitFullscreen {
                setPortraitFullscreen(false)
            }
            updateOrientationLock()
            if isViewLoaded {
                refreshLivePresentationLayout()
            }
            return
        }

        let nextAspectRatio = size.width / size.height
        guard nextAspectRatio.isFinite, nextAspectRatio > 0.1 else { return }
        actualVideoAspectRatio = nextAspectRatio
        viewModel.liveRotationSurfaceAlignmentState.updatePresentationSize(size)
        surfaceVideoAspectRatio = nextAspectRatio
        if isPortraitFullscreen, !isPortraitLiveVideo {
            setPortraitFullscreen(false)
        }
        updateOrientationLock()
        guard isViewLoaded else { return }
        refreshLivePresentationLayout()
    }

    private func refreshLivePresentationLayout() {
        applyLayout()
        updatePlaybackSystemChrome()
    }

    private func applyLayout(
        forBoundsSize size: CGSize? = nil,
        publishesContentLayout: Bool = true
    ) {
        let bounds = CGRect(origin: .zero, size: size ?? view.bounds.size)
        let landscape = bounds.width > bounds.height
        let safeAreaTop = min(max(view.safeAreaInsets.top, 0), bounds.height)
        let safeAreaBottom = min(max(view.safeAreaInsets.bottom, 0), bounds.height)
        let usesFullscreenLayout = usesLandscapeLiveFullscreen(forLandscape: landscape)
            || isPortraitFullscreen

        backdropHost.view.frame = bounds
        contentHost.view.frame = bounds
        if usesFullscreenLayout {
            playerContainer.frame = bounds
        } else {
            playerContainer.frame = liveRoomPlayerFrame(
                in: bounds,
                safeAreaTop: safeAreaTop,
                safeAreaBottom: safeAreaBottom
            )
        }
        if publishesContentLayout {
            contentState.update(
                layoutWidth: bounds.width,
                layoutHeight: bounds.height,
                topSafeAreaInset: usesFullscreenLayout ? 0 : safeAreaTop,
                bottomSafeAreaInset: usesFullscreenLayout ? 0 : safeAreaBottom,
                playerHeight: !usesFullscreenLayout
                    ? playerContainer.bounds.height
                    : 0
            )
        }
        loadingHost.view.frame = playerContainer.bounds
        updateSurfaceLayout(
            usesLandscapeChrome: usesLandscapeLiveFullscreen(forLandscape: landscape)
        )
        if !isSystemRotationTransitioning {
            contentHost.view.isHidden = usesFullscreenLayout
            contentHost.view.isUserInteractionEnabled = !usesFullscreenLayout
        }
    }

    /// During a system rotation the native video surface needs fresh geometry,
    /// while the hidden SwiftUI chat hierarchy must not receive layout state.
    private func applyRotationSurfaceLayout(forBoundsSize size: CGSize? = nil) {
        let resolvedSize = size ?? view.bounds.size
        guard lastRotationSurfaceLayoutSize != resolvedSize else { return }
        lastRotationSurfaceLayoutSize = resolvedSize
        applyLayout(forBoundsSize: resolvedSize, publishesContentLayout: false)
    }

    private func liveRoomPlayerFrame(
        in bounds: CGRect,
        safeAreaTop: CGFloat,
        safeAreaBottom: CGFloat
    ) -> CGRect {
        let height = LiveRoomSimpleLiveLayoutPolicy.playerHeight(
            containerSize: bounds.size,
            safeAreaTop: safeAreaTop,
            safeAreaBottom: safeAreaBottom,
            videoAspectRatio: actualVideoAspectRatio
        )
        return CGRect(
            x: bounds.minX,
            y: bounds.minY + safeAreaTop + LiveRoomSimpleLiveLayoutPolicy.headerContentHeight,
            width: bounds.width,
            height: height
        )
    }

    private func bindPlayerSurface() {
        playerSurfaceController.bind(
            to: viewModel.playbackSession,
            layout: currentSurfaceLayout(
                usesLandscapeChrome: usesLandscapeLiveFullscreen
            )
        )
    }

    private func currentSurfaceLayout(usesLandscapeChrome: Bool) -> PlayerSurfaceLayout {
        PlayerSurfaceLayout(
            frame: playerContainer.bounds,
            videoAspectRatio: surfaceVideoAspectRatio,
            videoGravity: .resizeAspect,
            usesLandscapeChrome: usesLandscapeChrome,
            usesPortraitFullscreen: isPortraitFullscreen,
            isTransitioning: isSystemRotationTransitioning
        )
    }

    private func updateSurfaceLayout(usesLandscapeChrome: Bool) {
        playerSurfaceController.updateLayout(
            currentSurfaceLayout(usesLandscapeChrome: usesLandscapeChrome)
        )
    }

    private func setBareSurfaceTransitionActive(_ active: Bool, retainsChromeTree: Bool = false) {
        playerSurfaceController.setBareSurfaceTransitionActive(
            active,
            retainsChromeTree: active && retainsChromeTree
        )
    }

    private func refreshSurfaceLayoutImmediately() {
        playerSurfaceController.refreshLayoutImmediately()
    }

    private func requestFullscreen() {
        switch LiveRoomVideoDetailLayoutPolicy.fullscreenMode(
            videoAspectRatio: actualVideoAspectRatio
        ) {
        case .portrait:
            setPortraitFullscreen(true)
        case .landscape:
            let scene = view.window?.windowScene
            AppOrientationLock.update(to: .allButUpsideDown, in: scene)
            AppOrientationLock.requestGeometryUpdate(to: .landscapeRight, in: scene)
        case .unavailable:
            return
        }
    }

    private func requestExitFullscreen() {
        if isPortraitFullscreen {
            setPortraitFullscreen(false)
        } else if usesLandscapeLiveFullscreen {
            let scene = view.window?.windowScene
            AppOrientationLock.update(to: .allButUpsideDown, in: scene)
            AppOrientationLock.requestGeometryUpdate(to: .portrait, in: scene)
        }
    }

    private func setPortraitFullscreen(_ active: Bool) {
        guard isPortraitFullscreen != active else { return }
        guard !active || isPortraitLiveVideo else { return }

        isPortraitFullscreen = active
        playerSurfaceController.setPortraitFullscreen(active)
        updatePlaybackSystemChrome()
        UIView.animate(
            withDuration: PlaybackDetailRotationTiming.portraitFullscreenDuration,
            delay: 0,
            options: [.curveEaseInOut]
        ) {
            self.applyLayout()
            self.setNeedsStatusBarAppearanceUpdate()
            self.setNeedsUpdateOfHomeIndicatorAutoHidden()
        }
    }

    private func handleBackButton() {
        if isLiveFullscreenActive {
            requestExitFullscreen()
        } else {
            onNavigateBack()
        }
    }

    private func startRotationFrameProbe(
        toLandscape: Bool,
        coordinator: UIViewControllerTransitionCoordinator
    ) {
        guard dependencies.libraryStore.videoRotationFrameReportOverlayEnabled else { return }
        let roomID = viewModel.roomID
        guard roomID > 0 else { return }
        rotationProbeGeneration &+= 1
        let durationMs = Int((coordinator.transitionDuration * 1000).rounded())
        rotationFrameProbe.start(
            metricsID: "live-\(roomID)",
            title: viewModel.title,
            mode: "liveDetailShell",
            generation: rotationProbeGeneration,
            toLandscape: toLandscape,
            coordinatorSummary: "coordinatorDuration=\(durationMs)ms animated=\(coordinator.isAnimated) interactive=\(coordinator.isInteractive) completionRecovery=retainedChromeStagedDisplayFrames",
            maximumFrameRate: view.window?.windowScene?.screen.maximumFramesPerSecond ?? 60
        )
    }

    private func finishSystemRotation(toLandscape: Bool, generation: Int) {
        rotationFrameProbe.mark("系统完成：保持视频层与已挂载控件树")
        let targetUsesLandscapeFullscreen = usesLandscapeLiveFullscreen(forLandscape: toLandscape)
        let targetUsesFullscreenLayout = targetUsesLandscapeFullscreen || isPortraitFullscreen
        // Keep the chat hierarchy hidden for the two staged recovery frames.
        // Returning to portrait otherwise makes the chat draw on the exact
        // frame where the player surface is settling.
        contentHost.view.isHidden = true
        contentHost.view.isUserInteractionEnabled = false

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lastRotationSurfaceLayoutSize = nil
        applyLayout()
        CATransaction.commit()
        rotationFrameProbe.mark("视频层几何已提交，等待下一帧")

        scheduleRotationRecovery(
            generation: generation,
            preparation: { [weak self] in
                guard let self, self.rotationGeneration == generation else { return }
                self.rotationFrameProbe.mark("第一帧：预热已挂载控件状态")
                self.playerSurfaceController.setLandscape(targetUsesLandscapeFullscreen)
                self.playerSurfaceController.setPortraitFullscreen(self.isPortraitFullscreen)
                self.rotationFrameProbe.mark("第一帧：控件方向已就绪")
            },
            recovery: { [weak self] in
                guard let self, self.rotationGeneration == generation else { return }
                self.rotationFrameProbe.mark("第二帧：恢复内容开始")
                self.isSystemRotationTransitioning = false
                self.updateSurfaceLayout(
                    usesLandscapeChrome: targetUsesLandscapeFullscreen
                )
                let hidesContent = targetUsesFullscreenLayout
                self.contentHost.view.isHidden = hidesContent
                self.contentHost.view.isUserInteractionEnabled = !hidesContent
                self.updatePlaybackSystemChrome()
                self.rotationFrameProbe.mark("第二帧：内容已恢复")
                self.setBareSurfaceTransitionActive(false)
                self.contentState.setChatUpdatesDeferred(false)
                self.scheduleDeferredLiveRenderRelease(generation: generation)
                self.rotationFrameProbe.mark("第二帧：叠层和手势已恢复，弹幕待下一帧合并")
                PlaybackDetailPerformanceMonitor.shared.mark(
                    .fullscreenLayoutUpdated,
                    context: self.performanceContext,
                    detail: "landscape=\(toLandscape) strategy=retainedChromeStagedDisplayFrames"
                )
                self.rotationFrameProbe.finish(
                    reason: "系统旋转完成 landscape=\(toLandscape) strategy=retainedChromeStagedDisplayFrames"
                )
            }
        )
    }

    private func scheduleRotationRecovery(
        generation: Int,
        preparation: @escaping () -> Void,
        recovery: @escaping () -> Void
    ) {
        cancelPendingRotationRecovery()
        pendingRotationPreparation = preparation
        pendingRotationRecovery = recovery
        pendingRotationGeneration = generation
        rotationRecoveryNotBefore = CACurrentMediaTime()
            + PlaybackDetailRotationTiming.recoverySettleDelay
        let displayLink = CADisplayLink(
            target: self,
            selector: #selector(runPendingRotationRecovery(_:))
        )
        if #available(iOS 15.0, *) {
            let maximumFrameRate = Float(max(view.window?.windowScene?.screen.maximumFramesPerSecond ?? 60, 60))
            displayLink.preferredFrameRateRange = CAFrameRateRange(
                minimum: 30,
                maximum: maximumFrameRate,
                preferred: maximumFrameRate
            )
        }
        displayLink.add(to: .main, forMode: .common)
        rotationRecoveryDisplayLink = displayLink
    }

    @objc private func runPendingRotationRecovery(_ displayLink: CADisplayLink) {
        guard rotationRecoveryDisplayLink === displayLink,
              let generation = pendingRotationGeneration,
              let recovery = pendingRotationRecovery
        else { return }

        guard generation == rotationGeneration else {
            cancelPendingRotationRecovery()
            return
        }
        if let notBefore = rotationRecoveryNotBefore,
           CACurrentMediaTime() < notBefore {
            return
        }
        rotationRecoveryNotBefore = nil
        if let preparation = pendingRotationPreparation {
            pendingRotationPreparation = nil
            preparation()
            return
        }

        cancelPendingRotationRecovery()
        recovery()
    }

    private func cancelPendingRotationRecovery() {
        rotationRecoveryDisplayLink?.invalidate()
        rotationRecoveryDisplayLink = nil
        pendingRotationPreparation = nil
        pendingRotationRecovery = nil
        pendingRotationGeneration = nil
        rotationRecoveryNotBefore = nil
    }

    private func scheduleDeferredLiveRenderRelease(generation: Int) {
        cancelDeferredLiveRenderRelease()
        deferredLiveRenderReleaseTask = Task { @MainActor [weak self] in
            await Task.yield()
            await Task.yield()
            guard let self,
                  !Task.isCancelled,
                  self.rotationGeneration == generation,
                  !self.isSystemRotationTransitioning
            else { return }
            self.viewModel.liveDanmakuRenderStore.setRenderedUpdatesDeferred(false)
            self.deferredLiveRenderReleaseTask = nil
            self.rotationFrameProbe.mark("旋转稳定后：恢复直播弹幕合批更新")
        }
    }

    private func cancelDeferredLiveRenderRelease() {
        deferredLiveRenderReleaseTask?.cancel()
        deferredLiveRenderReleaseTask = nil
    }

    private func resumeDeferredLiveRenderUpdates() {
        cancelDeferredLiveRenderRelease()
        viewModel.liveDanmakuRenderStore.setRenderedUpdatesDeferred(false)
        contentState.setChatUpdatesDeferred(false)
    }

    private func cancelActiveRotationPresentationIfNeeded() {
        guard isSystemRotationTransitioning else { return }
        isSystemRotationTransitioning = false
        lastRotationSurfaceLayoutSize = nil
        setBareSurfaceTransitionActive(false)
    }

    private func restoreSystemBackGestures() {
        guard let navigationController = enclosingNavigationController() else { return }
        attachedNavigationController = navigationController

        if let popGesture = navigationController.interactivePopGestureRecognizer {
            popGesture.isEnabled = true
            popGesture.delegate = self
        }

        if let contentPopGesture = navigationController.interactiveContentPopGestureRecognizer {
            contentPopGesture.isEnabled = true
            contentPopGesture.delegate = self
            prioritizeSystemContentPopGesture(contentPopGesture)
        }
    }

    private func isSystemBackGesture(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let navigationController = attachedNavigationController ?? enclosingNavigationController() else {
            return false
        }
        if let popGesture = navigationController.interactivePopGestureRecognizer,
           gestureRecognizer === popGesture {
            return true
        }
        if let contentPopGesture = navigationController.interactiveContentPopGestureRecognizer,
           gestureRecognizer === contentPopGesture {
            return true
        }
        return false
    }

    private func restoreSystemBackGesturesSoon() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.parent != nil else { return }
            self.restoreSystemBackGestures()
        }
    }

    private func enclosingNavigationController() -> UINavigationController? {
        if let navigationController {
            return navigationController
        }

        var current = parent
        while let viewController = current {
            if let navigationController = viewController as? UINavigationController {
                return navigationController
            }
            if let navigationController = viewController.navigationController {
                return navigationController
            }
            current = viewController.parent
        }

        var responder: UIResponder? = view
        while let current = responder {
            if let viewController = current as? UIViewController,
               let navigationController = viewController.navigationController {
                return navigationController
            }
            responder = current.next
        }
        return nil
    }

    private func prioritizeSystemContentPopGesture(_ contentPopGesture: UIGestureRecognizer) {
        let contentPopID = ObjectIdentifier(contentPopGesture)
        if configuredContentPopID != contentPopID {
            configuredContentPopID = contentPopID
            configuredScrollPanIDs.removeAll()
        }

        for scrollView in scrollViews(in: contentHost.view) {
            let panGesture = scrollView.panGestureRecognizer
            let panID = ObjectIdentifier(panGesture)
            guard configuredScrollPanIDs.insert(panID).inserted else { continue }
            panGesture.require(toFail: contentPopGesture)
        }
    }

    private func scrollViews(in rootView: UIView) -> [UIScrollView] {
        var result = [UIScrollView]()
        var stack = rootView.subviews
        while let view = stack.popLast() {
            if let scrollView = view as? UIScrollView {
                result.append(scrollView)
            }
            stack.append(contentsOf: view.subviews)
        }
        return result
    }
}

extension LiveRoomShellViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard isSystemBackGesture(gestureRecognizer) else { return true }
        guard !isLiveFullscreenActive,
              let navigationController = attachedNavigationController ?? enclosingNavigationController(),
              navigationController.viewControllers.count > 1,
              navigationController.transitionCoordinator == nil
        else {
            return false
        }

        guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer else {
            return true
        }
        let velocity = panGesture.velocity(in: navigationController.view)
        return velocity.x > 0 && abs(velocity.x) > abs(velocity.y)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive _: UITouch
    ) -> Bool {
        guard isSystemBackGesture(gestureRecognizer) else { return true }
        return !isLiveFullscreenActive
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard isSystemBackGesture(gestureRecognizer) || isSystemBackGesture(otherGestureRecognizer) else {
            return true
        }
        return !(gestureRecognizer is UITapGestureRecognizer || otherGestureRecognizer is UITapGestureRecognizer)
    }
}

private struct LiveRoomShellLoadingOverlay: View {
    @ObservedObject var viewModel: LiveRoomViewModel

    var body: some View {
        Group {
            if viewModel.playerViewModel == nil {
                ZStack {
                    Color.black

                    switch viewModel.state {
                    case .failed(let message):
                        LivePlayerFailurePlaceholder(message: message, retry: viewModel.reload)
                    default:
                        LivePlayerLoadingPlaceholder(
                            title: viewModel.title.nilIfEmpty ?? "正在进入直播间",
                            subtitle: viewModel.currentQualityTitle
                                ?? viewModel.currentStreamTitle
                                ?? "正在拉取直播流"
                        )
                    }
                }
            } else {
                Color.clear
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

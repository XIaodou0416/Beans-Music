import Combine
import SwiftUI
import UIKit

/// 详情页保留的最小 UIKit 边界：方向锁、系统旋转和生命周期恢复。
/// SwiftUI 容器宿主负责内容树和播放器布局，surface 由其内部的 representable 保持稳定。
@MainActor
final class VideoDetailRotationBridgeViewController: UIViewController {
    private let rotationPolicy = VideoDetailRotationPolicy()
    private let rotationCoordinator: PlaybackRotationCoordinator
    private let contentController: VideoDetailSwiftUIContainerViewController
    private let systemBackGestureDelegateLease = SystemBackGestureDelegateLease()
    private var cancellables = Set<AnyCancellable>()
    private var isViewActive = false
    private var rotationCompletionTask: Task<Void, Never>?
    private var rotationWatchdogTask: Task<Void, Never>?
    private var rotationGeneration = 0
    private var didPrepareForDismantle = false

    init(
        initialVideo: VideoItem,
        viewModel: VideoDetailViewModel,
        runtimeSettings: VideoDetailRuntimeSettingsStore,
        dependencies: AppDependencies,
        openVideoOwnerRoute: ((VideoOwner) -> Void)?,
        selectedContentTab: Binding<VideoDetailContentTab>,
        onShowNetworkDiagnostics: @escaping () -> Void,
        onShowFavoriteFolders: @escaping () -> Void,
        onShowCoinPicker: @escaping () -> Void,
        onOpenCommentComposer: @escaping (Comment?) -> Void,
        onShowDanmakuSettings: @escaping () -> Void,
        onPresentPlayerMoreControls: @escaping (PlayerStateViewModel, @escaping () -> Void) -> Void,
        onDismissPlayerMoreControls: @escaping () -> Void,
        onReply: @escaping (Comment) -> Void,
        onNavigateBack: @escaping () -> Void
    ) {
        let rotationCoordinator = PlaybackRotationCoordinator()
        self.rotationCoordinator = rotationCoordinator
        contentController = VideoDetailSwiftUIContainerViewController(
            initialVideo: initialVideo,
            viewModel: viewModel,
            runtimeSettings: runtimeSettings,
            dependencies: dependencies,
            rotationCoordinator: rotationCoordinator,
            openVideoOwnerRoute: openVideoOwnerRoute,
            selectedContentTab: selectedContentTab,
            onShowNetworkDiagnostics: onShowNetworkDiagnostics,
            onShowFavoriteFolders: onShowFavoriteFolders,
            onShowCoinPicker: onShowCoinPicker,
            onOpenCommentComposer: onOpenCommentComposer,
            onShowDanmakuSettings: onShowDanmakuSettings,
            onPresentPlayerMoreControls: onPresentPlayerMoreControls,
            onDismissPlayerMoreControls: onDismissPlayerMoreControls,
            onReply: onReply,
            onToggleDanmaku: viewModel.toggleDanmaku,
            onNavigateBack: onNavigateBack
        )
        super.init(nibName: nil, bundle: nil)
        contentController.rotationDelegate = self
        bindApplicationLifecycleForRotationRecovery()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        AppOrientationLock.supportedOrientations
    }

    override var prefersStatusBarHidden: Bool {
        rotationCoordinator.isLandscape || rotationCoordinator.isPortraitFullscreen
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        rotationCoordinator.isLandscape || rotationCoordinator.isPortraitFullscreen
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        addChild(contentController)
        contentController.view.backgroundColor = .clear
        contentController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentController.view)
        NSLayoutConstraint.activate([
            contentController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentController.view.topAnchor.constraint(equalTo: view.topAnchor),
            contentController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        contentController.didMove(toParent: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
#if DEBUG
        print(
            "[VideoDetailGeometry] stage=rotationBridgeLayout window=\(view.window?.bounds as Any) root=\(view.bounds) safeArea=\(view.safeAreaInsets) playerFrame=\(contentController.playerFrame)"
        )
#endif
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isViewActive = true
        rotationCoordinator.activate(
            isLandscape: resolvedLandscapeForRecovery,
            isPortraitFullscreen: rotationCoordinator.isPortraitFullscreen
        )
        contentController.setSecondaryContentMounted(true)
        if rotationCoordinator.isTransitioning {
            recoverInterruptedRotationIfNeeded(reason: "viewDidAppear")
        } else {
            contentController.recoverStableLayout()
        }
        updateOrientationLock()
        restoreSystemBackGestures()
        contentController.setBackgroundRenderFreezeActive(false)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isViewActive = false
        contentController.dismissPlayerMoreControls()
        recoverInterruptedRotationIfNeeded(reason: "viewWillDisappear")
        cancelRotationTasks()
        rotationCoordinator.deactivate(in: view.window?.windowScene)
        contentController.setBackgroundRenderFreezeActive(
            !isMovingFromParent
                && !isBeingDismissed
                && navigationController?.isBeingDismissed != true
        )
        releaseSystemBackGestureOwnership()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        contentController.markPageDisappeared()
        isViewActive = false
        cancelRotationTasks()
        rotationCoordinator.deactivate(in: view.window?.windowScene)
        rotationCoordinator.restorePortrait(in: view.window?.windowScene)
        releaseSystemBackGestureOwnership()
        if isMovingFromParent || isBeingDismissed || navigationController?.isBeingDismissed == true {
            contentController.setBackgroundRenderFreezeActive(false)
        } else {
            contentController.setBackgroundRenderFreezeActive(true)
        }
    }

    func prepareForDismantle() {
        guard !didPrepareForDismantle else { return }
        didPrepareForDismantle = true
        recoverInterruptedRotationIfNeeded(reason: "dismantle")
        cancelRotationTasks()
        rotationCoordinator.deactivate(in: view.window?.windowScene)
        contentController.prepareForDismantle()
        releaseSystemBackGestureOwnership()
    }

    override func viewWillTransition(
        to size: CGSize,
        with transitionCoordinator: UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: transitionCoordinator)
        let toLandscape = size.width > size.height
        rotationGeneration += 1
        let generation = rotationGeneration
        cancelRotationTasks()
        rotationCoordinator.beginSystemTransition(toLandscape: toLandscape)
        contentController.beginSystemRotation(toLandscape: toLandscape)
        contentController.markRotationStarted(toLandscape: toLandscape)
        scheduleRotationWatchdog(
            generation: generation,
            coordinatorDuration: transitionCoordinator.transitionDuration
        )
        if toLandscape {
            contentController.dismissPlayerMoreControls()
        }
        transitionCoordinator.animate(alongsideTransition: { [weak self] _ in
            self?.contentController.view.layoutIfNeeded()
            self?.setNeedsStatusBarAppearanceUpdate()
            self?.setNeedsUpdateOfHomeIndicatorAutoHidden()
        }, completion: { [weak self] _ in
            guard let self, self.rotationGeneration == generation else { return }
            self.scheduleRotationCompletion(
                generation: generation,
                toLandscape: toLandscape,
                settleDelay: PlaybackDetailRotationTiming.recoverySettleDelay
            )
        })
    }

    private func requestFullscreen() {
        if contentController.isPortraitVideo {
            rotationCoordinator.setPortraitFullscreen(true)
            updateOrientationLock()
            setNeedsStatusBarAppearanceUpdate()
            setNeedsUpdateOfHomeIndicatorAutoHidden()
            return
        }
        let scene = view.window?.windowScene
        rotationCoordinator.allowLandscape(in: scene)
        let target = rotationPolicy.preferredLandscapeInterfaceOrientation(
            currentInterfaceOrientation: scene?.effectiveGeometry.interfaceOrientation,
            deviceOrientation: UIDevice.current.orientation
        )
        rotationCoordinator.requestGeometryUpdate(to: target, in: scene)
    }

    private func requestExitFullscreen() {
        if rotationCoordinator.isPortraitFullscreen {
            rotationCoordinator.setPortraitFullscreen(false)
            contentController.recoverStableLayout()
            updateOrientationLock()
            setNeedsStatusBarAppearanceUpdate()
            setNeedsUpdateOfHomeIndicatorAutoHidden()
            return
        }
        let scene = view.window?.windowScene
        rotationCoordinator.allowLandscape(in: scene)
        rotationCoordinator.requestGeometryUpdate(to: .portrait, in: scene)
    }

    private func handleBackButton() {
        if rotationCoordinator.isLandscape || rotationCoordinator.isPortraitFullscreen {
            requestExitFullscreen()
        } else {
            contentController.recoverStableLayout()
            contentController.navigateBack()
        }
    }

    private func updateOrientationLock() {
        guard isViewActive else { return }
        rotationCoordinator.updateOrientationLock(
            isPortraitVideo: contentController.isPortraitVideo,
            isCurrentlyLandscape: rotationCoordinator.isLandscape,
            in: view.window?.windowScene
        )
    }

    private func bindApplicationLifecycleForRotationRecovery() {
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isViewActive else { return }
                    self.recoverInterruptedRotationIfNeeded(reason: "applicationWillResignActive")
                }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isViewActive else { return }
                    if !self.recoverInterruptedRotationIfNeeded(reason: "applicationDidBecomeActive") {
                        self.contentController.recoverStableLayout()
                    }
                    self.updateOrientationLock()
                }
            }
            .store(in: &cancellables)
    }

    private func scheduleRotationWatchdog(
        generation: Int,
        coordinatorDuration: TimeInterval
    ) {
        rotationWatchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(
                VideoDetailRotationRecoveryPolicy().watchdogDelay(
                    coordinatorDuration: coordinatorDuration
                )
            ))
            guard let self,
                  !Task.isCancelled,
                  self.rotationGeneration == generation,
                  self.rotationCoordinator.isTransitioning
            else { return }
            self.recoverInterruptedRotationIfNeeded(reason: "watchdogTimeout")
        }
    }

    private func scheduleRotationCompletion(
        generation: Int,
        toLandscape: Bool,
        settleDelay: TimeInterval
    ) {
        rotationCompletionTask = Task { @MainActor [weak self] in
            if settleDelay > 0 {
                try? await Task.sleep(for: .seconds(settleDelay))
            }
            try? await Task.sleep(for: .milliseconds(34))
            guard let self,
                  !Task.isCancelled,
                  self.rotationGeneration == generation
            else { return }
            let currentOrientation = self.view.window?.windowScene?.effectiveGeometry.interfaceOrientation
                ?? (toLandscape ? .landscapeRight : .portrait)
            if let pending = self.rotationCoordinator.finishSystemTransition(
                toLandscape: toLandscape,
                currentOrientation: currentOrientation
            ) {
                self.rotationCoordinator.requestGeometryUpdate(
                    to: pending,
                    in: self.view.window?.windowScene
                )
            }
            self.contentController.finishSystemRotation()
            self.contentController.markRotationFinished(toLandscape: toLandscape)
            self.rotationWatchdogTask?.cancel()
            self.rotationWatchdogTask = nil
            self.setNeedsStatusBarAppearanceUpdate()
            self.setNeedsUpdateOfHomeIndicatorAutoHidden()
        }
    }

    @discardableResult
    private func recoverInterruptedRotationIfNeeded(reason: String) -> Bool {
        guard rotationCoordinator.isTransitioning else { return false }
        rotationGeneration += 1
        cancelRotationTasks()
        let landscape = VideoDetailRotationRecoveryPolicy().resolvesLandscape(
            interfaceOrientation: view.window?.windowScene?.effectiveGeometry.interfaceOrientation,
            fallbackBounds: view.bounds.size
        )
        rotationCoordinator.recover(
            isLandscape: landscape,
            isPortraitFullscreen: rotationCoordinator.isPortraitFullscreen
        )
        contentController.recoverStableLayout()
        contentController.markRotationRecovered(reason: reason)
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        return true
    }

    private var resolvedLandscapeForRecovery: Bool {
        VideoDetailRotationRecoveryPolicy().resolvesLandscape(
            interfaceOrientation: view.window?.windowScene?.effectiveGeometry.interfaceOrientation,
            fallbackBounds: view.bounds.size
        )
    }

    private func cancelRotationTasks() {
        rotationCompletionTask?.cancel()
        rotationCompletionTask = nil
        rotationWatchdogTask?.cancel()
        rotationWatchdogTask = nil
    }

    private func restoreSystemBackGestures() {
        guard let navigationController else { return }
        systemBackGestureDelegateLease.acquire(in: navigationController, owner: self)
    }

    private func releaseSystemBackGestureOwnership() {
        systemBackGestureDelegateLease.release()
    }

    private func isSystemBackGesture(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let navigationController else { return false }
        return gestureRecognizer === navigationController.interactivePopGestureRecognizer
            || gestureRecognizer === navigationController.interactiveContentPopGestureRecognizer
    }
}

extension VideoDetailRotationBridgeViewController: VideoDetailRotationBridgeDelegate {
    func requestVideoDetailFullscreen() {
        requestFullscreen()
    }

    func requestVideoDetailExitFullscreen() {
        requestExitFullscreen()
    }

    func navigateBackFromVideoDetail() {
        handleBackButton()
    }
}

extension VideoDetailRotationBridgeViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard isSystemBackGesture(gestureRecognizer) else { return true }
        guard !rotationCoordinator.isLandscape else { return false }
        guard let navigationController,
              navigationController.viewControllers.count > 1
        else { return false }
        contentController.suppressContentActionsDuringSystemBackGesture()
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        guard isSystemBackGesture(gestureRecognizer) else { return true }
        guard !rotationCoordinator.isLandscape else { return false }
        return !contentController.playerFrame.contains(touch.location(in: view))
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard isSystemBackGesture(gestureRecognizer)
            || isSystemBackGesture(otherGestureRecognizer)
        else { return true }
        return !(gestureRecognizer is UITapGestureRecognizer
            || otherGestureRecognizer is UITapGestureRecognizer)
    }
}

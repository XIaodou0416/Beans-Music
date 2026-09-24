import AVKit
import SwiftUI
import UIKit

struct VideoSurfaceView: UIViewRepresentable {
    @ObservedObject var viewModel: PlayerStateViewModel
    let prefersNativePlaybackControls: Bool
    let isPictureInPictureEnabled: Bool
    var disablesImplicitLayoutAnimations = false
    var usesLiveSurfaceDuringLayoutTransition = false
    var isLayoutTransitioningForSurfaceHandoff: Bool?

    func makeUIView(context _: Context) -> VideoSurfaceContainerView {
        let view = VideoSurfaceContainerView()
        view.backgroundColor = .black
        view.disablesImplicitLayoutAnimations = disablesImplicitLayoutAnimations
        view.configureSurfaceHandoff(
            usesLiveSurfaceDuringLayoutTransition: usesLiveSurfaceDuringLayoutTransition,
            isLayoutTransitioning: isLayoutTransitioningForSurfaceHandoff ?? disablesImplicitLayoutAnimations
        )
        view.configureBoundsRefresh(for: viewModel)
        view.setPictureInPictureEnabled(isPictureInPictureEnabled)
        view.setPlayerViewModel(viewModel, prefersNativePlaybackControls: prefersNativePlaybackControls)
        viewModel.setPictureInPictureEnabled(isPictureInPictureEnabled)
        viewModel.attachSurface(
            view,
            prefersNativePlaybackControls: prefersNativePlaybackControls,
            preservesReadinessDuringSurfaceHandoff: view.isLiveSurfaceHandoffActive
        )
        return view
    }

    func updateUIView(_ uiView: VideoSurfaceContainerView, context _: Context) {
        uiView.disablesImplicitLayoutAnimations = disablesImplicitLayoutAnimations
        uiView.configureSurfaceHandoff(
            usesLiveSurfaceDuringLayoutTransition: usesLiveSurfaceDuringLayoutTransition,
            isLayoutTransitioning: isLayoutTransitioningForSurfaceHandoff ?? disablesImplicitLayoutAnimations
        )
        guard !viewModel.isTerminated else {
            uiView.detachPlayerSurface()
            return
        }
        if uiView.isPreparingForSurfaceDetach {
            guard uiView.cancelPendingSurfaceDetachIfPossible(for: viewModel) else { return }
        }
        uiView.configureBoundsRefresh(for: viewModel)
        uiView.setPictureInPictureEnabled(isPictureInPictureEnabled)
        uiView.setPlayerViewModel(viewModel, prefersNativePlaybackControls: prefersNativePlaybackControls)
        viewModel.setPictureInPictureEnabled(isPictureInPictureEnabled)
        viewModel.attachSurface(
            uiView,
            prefersNativePlaybackControls: prefersNativePlaybackControls,
            preservesReadinessDuringSurfaceHandoff: uiView.isLiveSurfaceHandoffActive
        )
        viewModel.endSurfaceMigrationHold()
        uiView.setNeedsLayout()
        uiView.invalidateVideoLayout()
        if disablesImplicitLayoutAnimations || usesLiveSurfaceDuringLayoutTransition {
            uiView.scheduleCoordinatedSurfaceLayoutRefresh(for: viewModel)
        } else {
            uiView.cancelCoordinatedSurfaceLayoutRefresh()
        }
    }

    static func dismantleUIView(_ uiView: VideoSurfaceContainerView, coordinator _: ()) {
        PlayerMetricsLog.diagnostic("surface dismantle view=\(ObjectIdentifier(uiView).hashValue)")
        uiView.detachPlayerSurfaceAfterCurrentTransitionIfNeeded()
    }
}

enum PlayerFullscreenMode: Equatable {
    case landscape(UIDeviceOrientation)
    case portrait

    var isLandscape: Bool {
        if case .landscape = self { return true }
        return false
    }

    var isPortrait: Bool {
        if case .portrait = self { return true }
        return false
    }

    var playbackDetailInterfaceOrientationMask: UIInterfaceOrientationMask {
        switch self {
        case .portrait:
            return .portrait
        case .landscape(let orientation):
            switch orientation {
            case .landscapeLeft:
                return .landscapeRight
            case .landscapeRight:
                return .landscapeLeft
            default:
                return .landscapeRight
            }
        }
    }
}

final class VideoSurfaceContainerView: UIView {
    let drawableView = UIView()
    let nativePlayerViewController = AVPlayerViewController()
    var onBoundsChange: (() -> Void)?
    var disablesImplicitLayoutAnimations = false

    private weak var playerViewModel: PlayerStateViewModel?
    private let nativeSurfaceGestureController = NativePlayerSurfaceGestureController()
    private(set) var prefersNativePlaybackControls = true
    private var showsSystemPlaybackControls = false
    private var isPictureInPictureEnabled = false
    private var isNativePlaybackControllerEnabled = false
    private var usesLiveSurfaceDuringLayoutTransition = false
    private var isLayoutTransitioningForSurfaceHandoff = false
    private var lastReportedBounds = CGRect.null
    private var isPendingSurfaceDetach = false
    private var surfaceBindingGeneration = 0
    private var coordinatedSurfaceLayoutTask: Task<Void, Never>?
    private var deferredSurfaceDetachTask: Task<Void, Never>?
    private var deferredBoundSurfaceLayoutRefreshTask: Task<Void, Never>?

    var isLiveSurfaceHandoffActive: Bool {
        usesLiveSurfaceDuringLayoutTransition && isLayoutTransitioningForSurfaceHandoff
    }

    func isBound(to viewModel: PlayerStateViewModel) -> Bool {
        !isPendingSurfaceDetach && playerViewModel === viewModel && !viewModel.isTerminated
    }

    var isPreparingForSurfaceDetach: Bool {
        isPendingSurfaceDetach
    }

    func cancelPendingSurfaceDetachIfPossible(for viewModel: PlayerStateViewModel) -> Bool {
        guard playerViewModel === viewModel, !viewModel.isTerminated else { return false }
        cancelDeferredSurfaceDetach()
        isPendingSurfaceDetach = false
        configureBoundsRefresh(for: viewModel)
        return true
    }

    func configureSurfaceHandoff(
        usesLiveSurfaceDuringLayoutTransition: Bool,
        isLayoutTransitioning: Bool
    ) {
        self.usesLiveSurfaceDuringLayoutTransition = usesLiveSurfaceDuringLayoutTransition
        isLayoutTransitioningForSurfaceHandoff = isLayoutTransitioning
    }

    func configureBoundsRefresh(for viewModel: PlayerStateViewModel) {
        onBoundsChange = { [weak self, weak viewModel] in
            guard let self,
                  let viewModel,
                  self.isBound(to: viewModel)
            else { return }
            self.scheduleDeferredBoundSurfaceLayoutRefresh(for: viewModel)
        }
    }

    func setPlayerViewModel(_ viewModel: PlayerStateViewModel, prefersNativePlaybackControls: Bool) {
        cancelDeferredSurfaceDetach()
        if playerViewModel !== viewModel || isPendingSurfaceDetach {
            surfaceBindingGeneration &+= 1
        }
        isPendingSurfaceDetach = false
        playerViewModel = viewModel
        self.prefersNativePlaybackControls = prefersNativePlaybackControls
        if !prefersNativePlaybackControls {
            setNativePlaybackControllerEnabled(false)
        }
        configureNativeSurfaceGestures()
    }

    func setPictureInPictureEnabled(_ isEnabled: Bool) {
        guard isPictureInPictureEnabled != isEnabled else {
            configureNativePlayerViewController()
            return
        }
        isPictureInPictureEnabled = isEnabled
        configureNativePlayerViewController()
    }

    func setShowsSystemPlaybackControls(_ showsPlaybackControls: Bool) {
        guard showsSystemPlaybackControls != showsPlaybackControls else {
            configureNativePlayerViewController()
            configureNativeSurfaceGestures()
            return
        }
        showsSystemPlaybackControls = showsPlaybackControls
        configureNativePlayerViewController()
        configureNativeSurfaceGestures()
    }

    func makePlaybackTransitionSnapshotView() -> UIView? {
        drawableView.layoutIfNeeded()
        guard drawableView.bounds.width > 1, drawableView.bounds.height > 1 else { return nil }

        if let snapshotView = drawableView.snapshotView(afterScreenUpdates: false) {
            snapshotView.frame = CGRect(origin: .zero, size: drawableView.bounds.size)
            snapshotView.backgroundColor = .black
            snapshotView.isOpaque = true
            snapshotView.clipsToBounds = true
            return snapshotView
        }

        let renderer = UIGraphicsImageRenderer(bounds: drawableView.bounds)
        let image = renderer.image { context in
            drawableView.layer.render(in: context.cgContext)
        }
        let imageView = UIImageView(image: image)
        imageView.frame = CGRect(origin: .zero, size: drawableView.bounds.size)
        imageView.backgroundColor = .black
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.isOpaque = true
        return imageView
    }

    func makePlaybackTransitionSnapshotImage() -> UIImage? {
        drawableView.layoutIfNeeded()
        guard drawableView.bounds.width > 1, drawableView.bounds.height > 1 else { return nil }

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(bounds: drawableView.bounds, format: format)
        return renderer.image { context in
            UIColor.black.setFill()
            context.fill(drawableView.bounds)
            if !drawableView.drawHierarchy(in: drawableView.bounds, afterScreenUpdates: false) {
                drawableView.layer.render(in: context.cgContext)
            }
        }
    }

    func detachPlayerSurface(preservingReadinessDuringSurfaceHandoff: Bool = false) {
        cancelDeferredSurfaceDetach()
        cancelCoordinatedSurfaceLayoutRefresh()
        cancelDeferredBoundSurfaceLayoutRefresh()
        surfaceBindingGeneration &+= 1
        isPendingSurfaceDetach = true
        onBoundsChange = nil
        playerViewModel?.detachSurface(
            self,
            preservesReadinessDuringSurfaceHandoff: preservingReadinessDuringSurfaceHandoff
        )
        setNativePlaybackControllerEnabled(false)
        playerViewModel = nil
    }

    func detachPlayerSurfaceAfterCurrentTransitionIfNeeded() {
        cancelCoordinatedSurfaceLayoutRefresh()
        cancelDeferredBoundSurfaceLayoutRefresh()
        surfaceBindingGeneration &+= 1
        let detachGeneration = surfaceBindingGeneration
        let pendingPlayerViewModel = playerViewModel
        let shouldKeepLiveSurfaceForHandoff = (isLiveSurfaceHandoffActive || pendingPlayerViewModel?.hasPresentedPlayback == true)
            && pendingPlayerViewModel?.hasPresentedPlayback == true
            && pendingPlayerViewModel?.isTerminated == false
        PlayerMetricsLog.diagnostic(
            "surface pendingDetach view=\(ObjectIdentifier(self).hashValue) liveHandoff=\(isLiveSurfaceHandoffActive) keep=\(shouldKeepLiveSurfaceForHandoff)"
        )
        isPendingSurfaceDetach = true
        onBoundsChange = nil
        if shouldKeepLiveSurfaceForHandoff {
            pendingPlayerViewModel?.beginSurfaceMigrationHold()
            deferPlayerSurfaceDetachAfterLayoutHandoff(
                generation: detachGeneration,
                pendingPlayerViewModel: pendingPlayerViewModel,
                delayNanoseconds: Self.liveSurfaceHandoffDetachDelayNanoseconds,
                preservingReadinessDuringSurfaceHandoff: true
            )
            return
        }
        guard let coordinator = enclosingNavigationController()?.transitionCoordinator else {
            deferPlayerSurfaceDetachAfterLayoutHandoff(
                generation: detachGeneration,
                pendingPlayerViewModel: pendingPlayerViewModel,
                delayNanoseconds: Self.deferredSurfaceDetachDelayNanoseconds,
                preservingReadinessDuringSurfaceHandoff: false
            )
            return
        }

        coordinator.animate(alongsideTransition: nil) { [weak self] context in
            guard let self else { return }
            guard self.surfaceBindingGeneration == detachGeneration,
                  self.playerViewModel === pendingPlayerViewModel
            else { return }
            if context.isCancelled {
                self.isPendingSurfaceDetach = false
                if let playerViewModel = self.playerViewModel,
                   !playerViewModel.isTerminated {
                    self.configureBoundsRefresh(for: playerViewModel)
                    playerViewModel.refreshSurfaceLayout()
                    self.scheduleCoordinatedSurfaceLayoutRefresh(for: playerViewModel)
                } else {
                    self.detachPlayerSurface()
                }
            } else {
                self.detachPlayerSurface()
            }
        }
    }

    private func deferPlayerSurfaceDetachAfterLayoutHandoff(
        generation: Int,
        pendingPlayerViewModel: PlayerStateViewModel?,
        delayNanoseconds: UInt64,
        preservingReadinessDuringSurfaceHandoff: Bool
    ) {
        deferredSurfaceDetachTask?.cancel()
        deferredSurfaceDetachTask = Task { @MainActor [weak pendingPlayerViewModel] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled,
                  self.surfaceBindingGeneration == generation,
                  self.playerViewModel === pendingPlayerViewModel
            else { return }
            self.detachPlayerSurface(
                preservingReadinessDuringSurfaceHandoff: preservingReadinessDuringSurfaceHandoff
            )
        }
    }

    func scheduleCoordinatedSurfaceLayoutRefresh(for viewModel: PlayerStateViewModel) {
        coordinatedSurfaceLayoutTask?.cancel()
        let refreshGeneration = surfaceBindingGeneration
        coordinatedSurfaceLayoutTask = Task { @MainActor [weak self, weak viewModel] in
            for delay in Self.coordinatedSurfaceLayoutRefreshDelays {
                if delay == 0 {
                    await Task.yield()
                } else {
                    try? await Task.sleep(nanoseconds: delay)
                }
                guard let self,
                      let viewModel,
                      !Task.isCancelled,
                      self.surfaceBindingGeneration == refreshGeneration,
                      self.isBound(to: viewModel)
                else { return }
                viewModel.refreshSurfaceLayout()
            }
            guard let self,
                  self.surfaceBindingGeneration == refreshGeneration
            else { return }
            self.coordinatedSurfaceLayoutTask = nil
        }
    }

    private static let coordinatedSurfaceLayoutRefreshDelays: [UInt64] = [
        0,
        80_000_000,
        180_000_000,
        320_000_000,
        520_000_000
    ]

    private static let deferredSurfaceDetachDelayNanoseconds: UInt64 = 220_000_000
    private static let liveSurfaceHandoffDetachDelayNanoseconds: UInt64 = 900_000_000

    private func cancelDeferredSurfaceDetach() {
        deferredSurfaceDetachTask?.cancel()
        deferredSurfaceDetachTask = nil
    }

    private func cancelDeferredBoundSurfaceLayoutRefresh() {
        deferredBoundSurfaceLayoutRefreshTask?.cancel()
        deferredBoundSurfaceLayoutRefreshTask = nil
    }

    func cancelCoordinatedSurfaceLayoutRefresh() {
        coordinatedSurfaceLayoutTask?.cancel()
        coordinatedSurfaceLayoutTask = nil
    }

    func setNativePlaybackControllerEnabled(_ isEnabled: Bool) {
        let resolvedIsEnabled = isEnabled && prefersNativePlaybackControls
        guard isNativePlaybackControllerEnabled != resolvedIsEnabled else {
            if resolvedIsEnabled {
                installNativePlayerViewControllerIfPossible()
                configureNativeSurfaceGestures()
            }
            return
        }

        isNativePlaybackControllerEnabled = resolvedIsEnabled
        if resolvedIsEnabled {
            configureNativePlayerViewController()
            installNativePlayerViewControllerIfPossible()
            configureNativeSurfaceGestures()
        } else {
            nativeSurfaceGestureController.detach()
            removeNativePlayerViewController()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isOpaque = true
        clipsToBounds = true
        drawableView.backgroundColor = .black
        drawableView.isOpaque = true
        drawableView.clipsToBounds = true
        addSubview(drawableView)
        configureNativePlayerViewController()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        deferredSurfaceDetachTask?.cancel()
        coordinatedSurfaceLayoutTask?.cancel()
        deferredBoundSurfaceLayoutRefreshTask?.cancel()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let previousBounds = lastReportedBounds
        performLayoutUpdates {
            applyVideoSurfaceLayout()
        }
        guard bounds.width > 1, bounds.height > 1 else { return }
        guard previousBounds != bounds else { return }
        lastReportedBounds = bounds
#if DEBUG
        let layer = drawableView.layer.sublayers?.compactMap { $0 as? AVPlayerLayer }.first
        print(
            "[VideoDetailGeometry] stage=surfaceLayout surfaceFrame(parent)=\(frame) surfaceBounds(local)=\(bounds) surfaceWindow=\(convert(bounds, to: window)) drawableFrame(surface)=\(drawableView.frame) drawableBounds(local)=\(drawableView.bounds) nativeFrame(drawable)=\(isNativePlaybackControllerEnabled ? String(describing: nativePlayerViewController.view.frame) : "unused") layerFrame(drawable)=\(layer?.frame as Any) videoRect(layer)=\(layer?.videoRect as Any) gravity=\(layer?.videoGravity.rawValue as Any) presentationSize=\(layer?.player?.currentItem?.presentationSize as Any)"
        )
#endif
        onBoundsChange?()
    }

    func invalidateVideoLayout() {
        performLayoutUpdates {
            applyVideoSurfaceLayout()
        }
        scheduleDeferredBoundSurfaceLayoutRefresh()
    }

    private func applyVideoSurfaceLayout() {
        drawableView.frame = bounds
        if isNativePlaybackControllerEnabled {
            installNativePlayerViewControllerIfPossible()
            applyNativePlayerLayout()
        }
        drawableView.setNeedsLayout()
    }

    private func scheduleDeferredBoundSurfaceLayoutRefresh(for viewModel: PlayerStateViewModel? = nil) {
        guard deferredBoundSurfaceLayoutRefreshTask == nil else { return }
        let refreshGeneration = surfaceBindingGeneration
        deferredBoundSurfaceLayoutRefreshTask = Task { @MainActor [weak self, weak viewModel] in
            await Task.yield()
            guard let self,
                  !Task.isCancelled,
                  self.surfaceBindingGeneration == refreshGeneration
            else { return }

            let resolvedViewModel = viewModel ?? self.playerViewModel
            guard let resolvedViewModel else {
                if self.surfaceBindingGeneration == refreshGeneration {
                    self.deferredBoundSurfaceLayoutRefreshTask = nil
                }
                return
            }

            self.refreshBoundPlayerSurfaceLayout(for: resolvedViewModel)
            if self.surfaceBindingGeneration == refreshGeneration {
                self.deferredBoundSurfaceLayoutRefreshTask = nil
            }
        }
    }

    private func refreshBoundPlayerSurfaceLayout(for playerViewModel: PlayerStateViewModel) {
        guard isBound(to: playerViewModel),
              bounds.width > 1,
              bounds.height > 1
        else { return }
        playerViewModel.refreshSurfaceLayout()
    }

    private func performLayoutUpdates(_ updates: () -> Void) {
        guard disablesImplicitLayoutAnimations else {
            updates()
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        UIView.performWithoutAnimation(updates)
        CATransaction.commit()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            removeNativePlayerViewController()
        } else if isNativePlaybackControllerEnabled {
            installNativePlayerViewControllerIfPossible()
        }
    }

    private func enclosingNavigationController() -> UINavigationController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let viewController = current as? UIViewController,
               let navigationController = viewController.navigationController {
                return navigationController
            }
            responder = current.next
        }
        return nil
    }

    private func configureNativePlayerViewController() {
        nativePlayerViewController.showsPlaybackControls = showsSystemPlaybackControls
        nativePlayerViewController.allowsVideoFrameAnalysis = !showsSystemPlaybackControls
        nativePlayerViewController.speeds = showsSystemPlaybackControls
            ? []
            : AVPlaybackSpeed.systemDefaultSpeeds
        nativePlayerViewController.videoGravity = .resizeAspect
        let isPictureInPictureAllowed = isPictureInPictureEnabled
            && AVPictureInPictureController.isPictureInPictureSupported()
        nativePlayerViewController.allowsPictureInPicturePlayback = isPictureInPictureAllowed
        nativePlayerViewController.canStartPictureInPictureAutomaticallyFromInline = isPictureInPictureAllowed
        nativePlayerViewController.requiresLinearPlayback = false
        nativePlayerViewController.updatesNowPlayingInfoCenter = false
        nativePlayerViewController.view.backgroundColor = .black
        nativePlayerViewController.view.isOpaque = true
    }

    private func configureNativeSurfaceGestures() {
        guard isNativePlaybackControllerEnabled,
              showsSystemPlaybackControls,
              let playerViewModel,
              !playerViewModel.isTerminated
        else {
            nativeSurfaceGestureController.detach()
            return
        }
        nativeSurfaceGestureController.attach(
            to: nativePlayerViewController,
            viewModel: playerViewModel
        )
    }

    private func installNativePlayerViewControllerIfPossible() {
        guard isNativePlaybackControllerEnabled else { return }
        guard let parentController = nearestViewController else { return }

        if nativePlayerViewController.parent !== parentController {
            removeNativePlayerViewController()
            parentController.addChild(nativePlayerViewController)
            drawableView.insertSubview(nativePlayerViewController.view, at: 0)
            nativePlayerViewController.didMove(toParent: parentController)
        } else if nativePlayerViewController.view.superview !== drawableView {
            nativePlayerViewController.view.removeFromSuperview()
            drawableView.insertSubview(nativePlayerViewController.view, at: 0)
        }

        applyNativePlayerLayout()
        nativePlayerViewController.view.isHidden = false
    }

    private func applyNativePlayerLayout() {
        AVPlayerLayoutCoordinator.shared.apply(
            playerController: nativePlayerViewController,
            in: drawableView,
            gravity: nativePlayerViewController.videoGravity
        )
    }

    private func removeNativePlayerViewController() {
        guard nativePlayerViewController.parent != nil || nativePlayerViewController.view.superview != nil else { return }
        nativePlayerViewController.willMove(toParent: nil)
        nativePlayerViewController.view.removeFromSuperview()
        nativePlayerViewController.removeFromParent()
    }
}

private extension UIView {
    var nearestViewController: UIViewController? {
        var responder: UIResponder? = self
        while let currentResponder = responder {
            if let viewController = currentResponder as? UIViewController {
                return viewController
            }
            responder = currentResponder.next
        }
        return nil
    }
}

import AVKit
import Combine
import MediaPlayer
import SwiftUI
import UIKit

@MainActor
final class NativePlayerSurfaceGestureController: NSObject {
    private enum PanMode {
        case undecided
        case seeking(startProgress: Double, duration: TimeInterval)
        case adjusting(target: PlayerSurfaceVerticalAdjustmentTarget, initialValue: Float)
        case ignored
    }

    private weak var playerViewController: AVPlayerViewController?
    private weak var viewModel: PlayerStateViewModel?
    private let hudModel = NativePlayerSurfaceGestureHUDModel()
    private let systemControlsController = PlayerSystemControlsController()
    private let volumeView = MPVolumeView(frame: .zero)
    private lazy var hostingController = UIHostingController(
        rootView: NativePlayerSurfaceGestureHUD(model: hudModel)
    )
    private lazy var doubleTapGesture = UITapGestureRecognizer(
        target: self,
        action: #selector(handleDoubleTap(_:))
    )
    private lazy var panGesture = UIPanGestureRecognizer(
        target: self,
        action: #selector(handlePan(_:))
    )

    private var panMode = PanMode.undecided
    private var panStartLocation: CGPoint?
    private var currentSeekProgress: Double?

    func attach(to playerViewController: AVPlayerViewController, viewModel: PlayerStateViewModel) {
        if self.viewModel !== viewModel {
            cancelActiveInteraction()
            self.viewModel = viewModel
        }

        guard let containerView = playerViewController.contentOverlayView else { return }
        if self.playerViewController === playerViewController,
           hostingController.view.superview === containerView {
            refreshSystemControlsAttachment()
            return
        }

        removeHostedViews()
        self.playerViewController = playerViewController
        containerView.backgroundColor = .clear
        containerView.isOpaque = false
        containerView.isUserInteractionEnabled = true

        configureGestureRecognizersIfNeeded()
        let hostedView = hostingController.view!
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        hostedView.backgroundColor = .clear
        hostedView.isOpaque = false
        hostedView.isUserInteractionEnabled = true

        playerViewController.addChild(hostingController)
        containerView.addSubview(hostedView)
        NSLayoutConstraint.activate([
            hostedView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
        ])
        hostingController.didMove(toParent: playerViewController)

        volumeView.translatesAutoresizingMaskIntoConstraints = false
        volumeView.showsVolumeSlider = true
        volumeView.isUserInteractionEnabled = false
        volumeView.alpha = 0.01
        containerView.addSubview(volumeView)
        NSLayoutConstraint.activate([
            volumeView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            volumeView.topAnchor.constraint(equalTo: containerView.topAnchor),
            volumeView.widthAnchor.constraint(equalToConstant: 1),
            volumeView.heightAnchor.constraint(equalToConstant: 1),
        ])
        refreshSystemControlsAttachment()
    }

    func detach() {
        cancelActiveInteraction()
        removeHostedViews()
        playerViewController = nil
        viewModel = nil
    }

    private func configureGestureRecognizersIfNeeded() {
        let hostedView = hostingController.view!
        guard doubleTapGesture.view == nil else { return }

        doubleTapGesture.numberOfTapsRequired = 2
        doubleTapGesture.cancelsTouchesInView = false
        doubleTapGesture.delegate = self
        hostedView.addGestureRecognizer(doubleTapGesture)

        panGesture.maximumNumberOfTouches = 1
        panGesture.cancelsTouchesInView = false
        panGesture.delegate = self
        hostedView.addGestureRecognizer(panGesture)
    }

    private func refreshSystemControlsAttachment() {
        let screen = hostingController.view.window?.windowScene?.screen
        systemControlsController.attach(volumeView: volumeView, screen: screen)
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended,
              let view = gesture.view,
              let viewModel,
              !viewModel.isTerminated
        else { return }
        let location = gesture.location(in: view)
        guard PlayerDoubleTapGesturePolicy.shouldTogglePlayback(
            locationX: location.x,
            width: view.bounds.width
        ) else { return }
        viewModel.togglePlayback()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let view = gesture.view,
              let viewModel,
              !viewModel.isTerminated
        else {
            cancelActiveInteraction()
            return
        }

        switch gesture.state {
        case .began:
            panMode = .undecided
            panStartLocation = gesture.location(in: view)
            currentSeekProgress = nil
        case .changed:
            let translation = gesture.translation(in: view)
            if case .undecided = panMode {
                beginPanInteractionIfNeeded(
                    translation: translation,
                    startLocation: panStartLocation ?? gesture.location(in: view),
                    size: view.bounds.size,
                    viewModel: viewModel
                )
            }
            updatePanInteraction(
                translation: translation,
                size: view.bounds.size,
                viewModel: viewModel
            )
        case .ended:
            finishPanInteraction(commitsSeek: true)
        case .cancelled, .failed:
            finishPanInteraction(commitsSeek: false)
        default:
            break
        }
    }

    private func beginPanInteractionIfNeeded(
        translation: CGPoint,
        startLocation: CGPoint,
        size: CGSize,
        viewModel: PlayerStateViewModel
    ) {
        guard let axis = PlayerSurfaceGestureAxisPolicy.axis(
            translation: CGSize(width: translation.x, height: translation.y),
            activationDistance: 8,
            dominanceRatio: 3
        ) else { return }

        switch axis {
        case .horizontal:
            guard viewModel.canSeek,
                  let duration = resolvedDuration(for: viewModel),
                  duration > 0,
                  size.width > 0
            else {
                panMode = .ignored
                return
            }
            let startProgress = min(
                max(viewModel.playbackClock.currentTime / duration, 0),
                1
            )
            panMode = .seeking(startProgress: startProgress, duration: duration)
            currentSeekProgress = startProgress
            viewModel.playbackClock.updateSeekPreview(progress: startProgress, force: true)
            viewModel.beginUserScrubInteraction(source: .surfaceGesture)
        case .vertical:
            guard let target = PlayerSurfaceVerticalAdjustmentPolicy.target(
                startLocationX: startLocation.x,
                width: size.width
            ) else {
                panMode = .ignored
                return
            }
            refreshSystemControlsAttachment()
            guard let initialValue = systemValue(for: target) else {
                panMode = .ignored
                return
            }
            panMode = .adjusting(target: target, initialValue: initialValue)
        }
    }

    private func updatePanInteraction(
        translation: CGPoint,
        size: CGSize,
        viewModel: PlayerStateViewModel
    ) {
        switch panMode {
        case let .seeking(startProgress, duration):
            guard size.width > 0 else { return }
            let secondsPerWidth = PlayerHorizontalSeekSensitivity.secondsPerFullWidth(
                duration: duration
            )
            let progressDelta = Double(translation.x / size.width) * secondsPerWidth / duration
            let progress = min(max(startProgress + progressDelta, 0), 1)
            currentSeekProgress = progress
            viewModel.playbackClock.updateSeekPreview(progress: progress)
            hudModel.presentation = .seek(progress: progress, duration: duration)
        case let .adjusting(target, initialValue):
            let value = PlayerSurfaceVerticalAdjustmentPolicy.adjustedValue(
                initialValue: initialValue,
                verticalTranslation: translation.y,
                height: size.height
            )
            applySystemValue(value, for: target)
            hudModel.presentation = .adjustment(target: target, value: value)
        case .undecided, .ignored:
            break
        }
    }

    private func finishPanInteraction(commitsSeek: Bool) {
        if case .seeking = panMode {
            if commitsSeek, let currentSeekProgress {
                viewModel?.seekAfterSliderCommit(to: currentSeekProgress)
            } else {
                viewModel?.cancelUserScrubInteraction()
            }
            viewModel?.playbackClock.clearSeekPreview()
        }
        panMode = .undecided
        panStartLocation = nil
        currentSeekProgress = nil
        hudModel.presentation = nil
    }

    private func cancelActiveInteraction() {
        finishPanInteraction(commitsSeek: false)
    }

    private func resolvedDuration(for viewModel: PlayerStateViewModel) -> TimeInterval? {
        viewModel.playbackClock.duration ?? viewModel.displayDuration
    }

    private func systemValue(for target: PlayerSurfaceVerticalAdjustmentTarget) -> Float? {
        switch target {
        case .brightness:
            return systemControlsController.displayBrightness
        case .volume:
            return systemControlsController.outputVolume
        }
    }

    private func applySystemValue(_ value: Float, for target: PlayerSurfaceVerticalAdjustmentTarget) {
        switch target {
        case .brightness:
            systemControlsController.setDisplayBrightness(value)
        case .volume:
            systemControlsController.setOutputVolume(value)
        }
    }

    private func removeHostedViews() {
        volumeView.removeFromSuperview()
        guard hostingController.parent != nil || hostingController.view.superview != nil else { return }
        hostingController.willMove(toParent: nil)
        hostingController.view.removeFromSuperview()
        hostingController.removeFromParent()
    }
}

extension NativePlayerSurfaceGestureController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panGesture,
              let view = gestureRecognizer.view
        else { return true }
        let location = gestureRecognizer.location(in: view)
        let leftInset = max(view.safeAreaInsets.left, 24)
        let rightInset = max(view.safeAreaInsets.right, 24)
        return location.x > leftInset && location.x < view.bounds.width - rightInset
    }

    func gestureRecognizer(
        _: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
    ) -> Bool {
        true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var touchedView = touch.view
        while let currentView = touchedView, currentView !== gestureRecognizer.view {
            if currentView is UIControl { return false }
            touchedView = currentView.superview
        }
        return true
    }
}

@MainActor
private final class NativePlayerSurfaceGestureHUDModel: ObservableObject {
    enum Presentation {
        case seek(progress: Double, duration: TimeInterval)
        case adjustment(target: PlayerSurfaceVerticalAdjustmentTarget, value: Float)
    }

    @Published var presentation: Presentation?
}

private struct NativePlayerSurfaceGestureHUD: View {
    @ObservedObject var model: NativePlayerSurfaceGestureHUDModel

    var body: some View {
        ZStack {
            switch model.presentation {
            case let .seek(progress, duration):
                PlayerSeekPreviewOverlay(
                    presentation: PlayerSeekPreviewPresentation(
                        progress: progress,
                        duration: duration,
                        image: nil,
                        imageAspectRatio: nil,
                        isLoading: false,
                        isCancelPending: false
                    )
                )
            case let .adjustment(target, value):
                PlayerSurfaceVerticalAdjustmentIndicator(target: target, value: value)
            case nil:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

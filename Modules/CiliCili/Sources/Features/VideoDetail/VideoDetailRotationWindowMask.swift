import UIKit

@MainActor
enum VideoDetailRotationWindowMask {
    private static weak var overlayView: UIView?
    private static weak var imageView: UIImageView?
    private static var removalTask: Task<Void, Never>?
    private static var generation = 0

    @discardableResult
    static func hold(
        snapshot: PlaybackTransitionSnapshot?,
        frame: CGRect? = nil
    ) -> Bool {
        removalTask?.cancel()
        generation &+= 1

        guard let window = UIApplication.shared.videoDetailKeyWindow
            ?? UIApplication.shared.playbackDetailForegroundKeyWindow
        else { return false }

        let overlay = overlayView ?? makeOverlayView()
        let image = imageView ?? makeImageView()
        if overlay.superview !== window {
            overlay.removeFromSuperview()
            overlay.frame = window.bounds
            overlay.autoresizingMask = []
            window.addSubview(overlay)
        }
        if image.superview == nil {
            overlay.addSubview(image)
        }

        overlay.frame = window.bounds
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.backgroundColor = .black
        overlay.isOpaque = true
        image.layer.removeAllAnimations()
        if let frame, frame.isUsable {
            image.frame = frame
            image.autoresizingMask = []
        } else {
            image.frame = overlay.bounds
            image.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        }
        image.image = snapshot?.image
        image.alpha = 1
        image.contentMode = .scaleAspectFit
        overlay.alpha = 1
        overlay.isHidden = false

        overlayView = overlay
        imageView = image
        PlayerMetricsLog.diagnostic(
            "rotationWindowMask hold hasImage=\(snapshot?.image != nil) snapshotVideo=\(snapshot?.isVideoFrame == true) frame=\(image.frame) window=\(window.bounds)"
        )
        return snapshot?.image != nil
    }

    @discardableResult
    static func animateHeldSnapshot(
        from sourceFrame: CGRect? = nil,
        to targetFrame: CGRect,
        duration: TimeInterval,
        releasesOnCompletion: Bool = true,
        fadeOutDelay: TimeInterval = 0.24,
        fadeOutDuration: TimeInterval = 0.14
    ) -> Bool {
        removalTask?.cancel()
        generation &+= 1
        let animationGeneration = generation

        guard let window = UIApplication.shared.videoDetailKeyWindow
            ?? UIApplication.shared.playbackDetailForegroundKeyWindow,
            let overlay = overlayView,
            let image = imageView,
            image.image != nil,
            targetFrame.width > 1,
            targetFrame.height > 1
        else { return false }

        if overlay.superview !== window {
            overlay.removeFromSuperview()
            overlay.frame = window.bounds
            overlay.autoresizingMask = []
            window.addSubview(overlay)
        }

        if let sourceFrame, sourceFrame.isUsable {
            overlay.frame = window.bounds
            image.frame = sourceFrame
        } else if !overlay.frame.isUsable {
            overlay.frame = window.bounds
        }
        overlay.backgroundColor = .black
        overlay.isOpaque = true
        overlay.alpha = 1
        overlay.isHidden = false

        image.layer.removeAllAnimations()
        let resolvedSourceFrame = sourceFrame?.isUsable == true
            ? sourceFrame!
            : (image.frame.isUsable ? image.frame : window.bounds)
        image.frame = resolvedSourceFrame
        image.alpha = 1
        image.contentMode = .scaleAspectFit

        animateImage(
            image,
            from: resolvedSourceFrame,
            to: targetFrame,
            duration: duration
        ) {
            Task { @MainActor in
                guard animationGeneration == generation else { return }
                guard releasesOnCompletion else { return }
                UIView.animate(
                    withDuration: fadeOutDuration,
                    delay: fadeOutDelay,
                    options: [.beginFromCurrentState, .curveLinear, .allowUserInteraction]
                ) {
                    overlay.alpha = 0
                } completion: { _ in
                    Task { @MainActor in
                        guard animationGeneration == generation else { return }
                        remove()
                    }
                }
            }
        }
        return true
    }

    static func animateSnapshot(
        _ snapshot: PlaybackTransitionSnapshot?,
        from sourceFrame: CGRect,
        to targetFrame: CGRect,
        duration: TimeInterval,
        fadeOutDelay: TimeInterval = 0.04,
        fadeOutDuration: TimeInterval = 0.12
    ) {
        removalTask?.cancel()
        generation &+= 1
        let animationGeneration = generation

        guard let window = UIApplication.shared.videoDetailKeyWindow
            ?? UIApplication.shared.playbackDetailForegroundKeyWindow,
            let snapshot,
            sourceFrame.width > 1,
            sourceFrame.height > 1,
            targetFrame.width > 1,
            targetFrame.height > 1
        else { return }

        let overlay = overlayView ?? makeOverlayView()
        let image = imageView ?? makeImageView()
        if overlay.superview !== window {
            overlay.removeFromSuperview()
            overlay.frame = window.bounds
            overlay.autoresizingMask = []
            window.addSubview(overlay)
        }
        if image.superview == nil {
            overlay.addSubview(image)
        }

        overlay.frame = window.bounds
        overlay.backgroundColor = .black
        overlay.isOpaque = true
        overlay.alpha = 1
        overlay.isHidden = false

        image.image = snapshot.image
        image.frame = sourceFrame
        image.alpha = 1
        image.contentMode = .scaleAspectFit

        overlayView = overlay
        imageView = image

        animateImage(
            image,
            from: sourceFrame,
            to: targetFrame,
            duration: duration
        ) {
            Task { @MainActor in
                guard animationGeneration == generation else { return }
                UIView.animate(
                    withDuration: fadeOutDuration,
                    delay: fadeOutDelay,
                    options: [.beginFromCurrentState, .curveLinear, .allowUserInteraction]
                ) {
                    overlay.alpha = 0
                } completion: { _ in
                    Task { @MainActor in
                        guard animationGeneration == generation else { return }
                        remove()
                    }
                }
            }
        }
    }

    static func release(after delay: UInt64, fadeDuration: UInt64) {
        guard overlayView != nil else { return }
        PlayerMetricsLog.diagnostic(
            "rotationWindowMask release delayMs=\(delay / 1_000_000) fadeMs=\(fadeDuration / 1_000_000)"
        )
        removalTask?.cancel()
        generation &+= 1
        let releaseGeneration = generation
        removalTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled, releaseGeneration == generation else { return }
            UIView.animate(
                withDuration: TimeInterval(fadeDuration) / 1_000_000_000,
                delay: 0,
                options: [.beginFromCurrentState, .curveLinear, .allowUserInteraction]
            ) {
                overlayView?.alpha = 0
            } completion: { _ in
                Task { @MainActor in
                    guard releaseGeneration == generation else { return }
                    remove()
                }
            }
        }
    }

    static func remove() {
        PlayerMetricsLog.diagnostic("rotationWindowMask remove hadOverlay=\(overlayView != nil)")
        removalTask?.cancel()
        removalTask = nil
        generation &+= 1
        overlayView?.removeFromSuperview()
        overlayView = nil
        imageView = nil
    }

    private static func makeOverlayView() -> UIView {
        let overlay = UIView()
        overlay.backgroundColor = .black
        overlay.isOpaque = true
        overlay.isUserInteractionEnabled = false
        overlay.clipsToBounds = true
        overlay.layer.zPosition = CGFloat.greatestFiniteMagnitude
        return overlay
    }

    private static func makeImageView() -> UIImageView {
        let imageView = UIImageView()
        imageView.backgroundColor = .black
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.isOpaque = true
        imageView.autoresizingMask = []
        imageView.layer.magnificationFilter = .linear
        imageView.layer.minificationFilter = .trilinear
        imageView.layer.allowsEdgeAntialiasing = true
        return imageView
    }

    private static func animateImage(
        _ image: UIImageView,
        from sourceFrame: CGRect,
        to targetFrame: CGRect,
        duration: TimeInterval,
        completion: @escaping () -> Void
    ) {
        image.center = CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)
        image.bounds = CGRect(origin: .zero, size: sourceFrame.size)
        let animator = UIViewPropertyAnimator(duration: duration, dampingRatio: 1)
        animator.addAnimations {
            image.center = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
            image.bounds = CGRect(origin: .zero, size: targetFrame.size)
        }
        animator.addCompletion { _ in
            image.center = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
            image.bounds = CGRect(origin: .zero, size: targetFrame.size)
            completion()
        }
        animator.startAnimation()
    }
}

private extension CGRect {
    var isUsable: Bool {
        width > 1 && height > 1 && !isNull && !isInfinite
    }
}

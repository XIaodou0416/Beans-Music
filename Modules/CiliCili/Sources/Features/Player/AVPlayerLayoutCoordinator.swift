import AVFoundation
import AVKit
import UIKit

@MainActor
final class AVPlayerLayoutCoordinator {
    static let shared = AVPlayerLayoutCoordinator()

    private init() {}

#if DEBUG
    private weak var diagnosticItem: AVPlayerItem?
    private var lastGeometry = ""
#endif

    func apply(
        playerLayer: AVPlayerLayer?,
        in containerView: UIView?,
        gravity: AVLayerVideoGravity
    ) {
        guard let playerLayer, let containerView else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.videoGravity = gravity
        playerLayer.frame = containerView.bounds
        playerLayer.position = CGPoint(x: containerView.bounds.midX, y: containerView.bounds.midY)
        playerLayer.setNeedsLayout()
        playerLayer.setNeedsDisplay()
        playerLayer.layoutIfNeeded()
        CATransaction.commit()
#if DEBUG
        let geometry = "[VideoDetailGeometry] stage=avPlayerLayerLayout coordinates=drawable-local layerFrame=\(playerLayer.frame) layerBounds=\(playerLayer.bounds) videoRect=\(playerLayer.videoRect) gravity=\(gravity.rawValue) presentationSize=\(playerLayer.player?.currentItem?.presentationSize as Any)"
        if geometry != lastGeometry {
            lastGeometry = geometry
            print(geometry)
        }
        if let item = playerLayer.player?.currentItem, diagnosticItem !== item {
            diagnosticItem = item
            Task { @MainActor [weak item] in
                guard let item else { return }
                do {
                    let tracks = try await item.asset.loadTracks(withMediaType: .video)
                    if let track = tracks.first {
                        let size = try await track.load(.naturalSize)
                        print("[VideoDetailGeometry] item=\(ObjectIdentifier(item)) naturalSize=\(size)")
                    }
                } catch {
                    print("[VideoDetailGeometry] naturalSizeUnavailable=\(error.localizedDescription)")
                }
            }
        }
#endif
    }

    func apply(
        playerController: AVPlayerViewController,
        in containerView: UIView,
        gravity: AVLayerVideoGravity
    ) {
        apply(
            playerController: playerController,
            bounds: containerView.bounds,
            gravity: gravity
        )
    }

    func apply(
        playerController: AVPlayerViewController,
        bounds: CGRect,
        gravity: AVLayerVideoGravity
    ) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        UIView.performWithoutAnimation {
            playerController.videoGravity = gravity
            playerController.view.frame = bounds
            playerController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            playerController.view.setNeedsLayout()
        }
        CATransaction.commit()
    }

    func transition(
        to _: CGSize,
        coordinator: UIViewControllerTransitionCoordinator,
        layout: @escaping @MainActor () -> Void
    ) {
        layout()
        coordinator.animate(alongsideTransition: { _ in
            Task { @MainActor in
                layout()
            }
        }, completion: { _ in
            Task { @MainActor in
                layout()
            }
        })
    }
}

import SwiftUI
import UIKit

extension GeometryProxy {
    var fullscreenContainerGeometry: PlaybackDetailFullscreenGeometry {
        playbackDetailFullscreenGeometry(
            window: UIApplication.shared.playbackDetailForegroundKeyWindow
        ) { window, rootView in
            Self.resolvedFullscreenSize(
                windowSize: window.bounds.size,
                rootSize: rootView.bounds.size,
                orientation: window.windowScene?.effectiveGeometry.interfaceOrientation
            )
        }
    }

    private static func resolvedFullscreenSize(
        windowSize: CGSize,
        rootSize: CGSize,
        orientation: UIInterfaceOrientation?
    ) -> CGSize {
        let candidates = [rootSize, windowSize].filter { $0.width > 1 && $0.height > 1 }
        guard let orientation else {
            return candidates.first ?? windowSize
        }

        if orientation.isLandscape {
            if let landscapeSize = candidates.first(where: { $0.width >= $0.height }) {
                return landscapeSize
            }
            let fallback = candidates.first ?? windowSize
            return CGSize(width: max(fallback.width, fallback.height), height: min(fallback.width, fallback.height))
        }

        if orientation.isPortrait {
            if let portraitSize = candidates.first(where: { $0.height >= $0.width }) {
                return portraitSize
            }
            let fallback = candidates.first ?? windowSize
            return CGSize(width: min(fallback.width, fallback.height), height: max(fallback.width, fallback.height))
        }

        return candidates.first ?? windowSize
    }
}

import SwiftUI
import UIKit

struct PlaybackDetailFullscreenGeometry: Equatable {
    let size: CGSize
    let offset: CGSize

    static func resolve(
        containerSize: CGSize,
        safeAreaInsets: EdgeInsets,
        localFrame: CGRect,
        window: UIWindow?,
        resolveSize: (_ window: UIWindow, _ rootView: UIView) -> CGSize
    ) -> PlaybackDetailFullscreenGeometry {
        if let window,
           let rootView = window.rootViewController?.view {
            let frameInWindow = rootView.convert(localFrame, from: nil)
            return PlaybackDetailFullscreenGeometry(
                size: resolveSize(window, rootView),
                offset: CGSize(width: -frameInWindow.minX, height: -frameInWindow.minY)
            )
        }

        let expandedSize = CGSize(
            width: containerSize.width + safeAreaInsets.leading + safeAreaInsets.trailing,
            height: containerSize.height + safeAreaInsets.top + safeAreaInsets.bottom
        )
        return PlaybackDetailFullscreenGeometry(
            size: expandedSize,
            offset: CGSize(width: -safeAreaInsets.leading, height: -safeAreaInsets.top)
        )
    }
}

extension GeometryProxy {
    func playbackDetailFullscreenGeometry(
        window: UIWindow?,
        resolveSize: (_ window: UIWindow, _ rootView: UIView) -> CGSize
    ) -> PlaybackDetailFullscreenGeometry {
        PlaybackDetailFullscreenGeometry.resolve(
            containerSize: size,
            safeAreaInsets: safeAreaInsets,
            localFrame: frame(in: .global),
            window: window,
            resolveSize: resolveSize
        )
    }
}

import SwiftUI
import UIKit

struct VideoDetailInitialPlaybackLayout {
    let width: CGFloat
    let playerHeight: CGFloat

    init(proxy: GeometryProxy, isPortraitVideo: Bool) {
        let fullscreenSize = proxy.fullscreenContainerGeometry.size
        width = PlaybackDetailStableLayout.portraitWidth(
            containerSize: proxy.size,
            fullscreenSize: fullscreenSize,
            windowSize: UIApplication.shared.playbackDetailForegroundKeyWindow?.bounds.size
        )

        let standardHeight = PlaybackDetailPlayerMetrics.standardHeight(for: width)
        if isPortraitVideo {
            let proposedHeight = max(proxy.size.height * 0.65, width)
            let maximumHeight = max(standardHeight, proxy.size.height * 0.72)
            playerHeight = max(standardHeight, min(proposedHeight, maximumHeight))
        } else {
            playerHeight = standardHeight
        }
    }
}

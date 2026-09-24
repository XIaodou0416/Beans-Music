import SwiftUI
import UIKit

extension GeometryProxy {
    var liveDetailFullscreenContainerGeometry: PlaybackDetailFullscreenGeometry {
        playbackDetailFullscreenGeometry(
            window: UIApplication.shared.playbackDetailForegroundKeyWindow
        ) { window, _ in
            window.bounds.size
        }
    }
}

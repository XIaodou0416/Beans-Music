import UIKit

extension UIApplication {
    var playbackDetailForegroundKeyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .first { $0.isPlaybackDetailPrimaryKeyWindow }
    }

    var playbackDetailForegroundWindowScene: UIWindowScene? {
        playbackDetailForegroundKeyWindow?.windowScene
    }
}

extension UIWindow {
    var isPlaybackDetailPrimaryKeyWindow: Bool {
        isKeyWindow
            && !isHidden
            && alpha > 0
            && !(self is PlayerHostWindow)
    }
}

extension AppOrientationLock {
    static func requestPlaybackDetailGeometry(
        for mode: PlayerFullscreenMode,
        in scene: UIWindowScene?
    ) {
        update(
            to: mode.playbackDetailInterfaceOrientationMask,
            in: scene,
            requestsGeometryUpdate: true
        )
    }
}

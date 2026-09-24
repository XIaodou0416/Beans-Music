import UIKit

extension UIApplication {
    var videoDetailKeyWindow: UIWindow? {
        playbackDetailForegroundKeyWindow ?? connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isPlaybackDetailPrimaryKeyWindow }
    }
}

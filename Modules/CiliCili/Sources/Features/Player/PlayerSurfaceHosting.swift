import AVFoundation
import UIKit

/// 各播放场景接入 UIKit 视频层协调器时需要提供的最小能力。
///
/// 视频详情、番剧和直播可以保留各自的 SwiftUI 控件与弹幕叠层，只共享
/// surface 的挂载、播放器替换、布局和转场冻结行为。
@MainActor
protocol PlayerSurfaceHosting: AnyObject {
    var surfaceView: UIView { get }
    var isRotationChromePrewarmed: Bool { get }

    func attach(to parent: UIViewController)
    func setPlayerViewModel(_ playerViewModel: PlayerStateViewModel)
    func setVideoGravity(_ gravity: AVLayerVideoGravity)
    func setVideoAspectRatio(_ aspectRatio: CGFloat)
    func setLandscape(_ landscape: Bool)
    func setPortraitFullscreen(_ active: Bool)
    func setBareSurfaceTransitionActive(_ active: Bool, retainsChromeTree: Bool)
    func prewarmRotationChrome()
    func cancelRotationChromePrewarm()
    func refreshLayoutImmediately()
}

extension PlayerSurfaceHosting {
    var isRotationChromePrewarmed: Bool { false }
}

/// UIKit 容器提交给视频层的展示状态。后续直播宿主接入时复用同一份几何描述。
struct PlayerSurfaceLayout {
    var frame: CGRect
    var videoAspectRatio: CGFloat
    var videoGravity: AVLayerVideoGravity
    var usesLandscapeChrome: Bool
    var usesPortraitFullscreen: Bool
    var isTransitioning: Bool
}

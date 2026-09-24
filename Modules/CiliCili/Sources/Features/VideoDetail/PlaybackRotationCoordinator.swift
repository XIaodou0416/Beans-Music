import Combine
import UIKit

@MainActor
enum PlaybackRotationPhase: Equatable {
    case embedded
    case preparingLandscape
    case landscape
    case preparingPortrait
    case portraitFullscreen
    case recovering
}

/// 视频详情页唯一的旋转状态源。
///
/// UIKit 负责接收系统转场回调，但方向状态、请求合并和恢复路径都由这个
/// coordinator 持有。播放器 surface 不参与状态切换，因此旋转只会改变几何
/// 和控件状态，不会重新创建 AVPlayer 或 AVPlayerItem。
@MainActor
final class PlaybackRotationCoordinator: ObservableObject {
    @Published private(set) var phase: PlaybackRotationPhase = .embedded
    @Published private(set) var isSystemRotationTransitioning = false
    @Published private(set) var isLandscape = false
    @Published private(set) var isPortraitFullscreen = false
    @Published private(set) var prewarmLandscape: Bool?

    private var requestCoalescer = VideoDetailRotationRequestCoalescer()
    private(set) var isViewActive = false

    var isTransitioning: Bool {
        isSystemRotationTransitioning || requestCoalescer.isTransitioning
    }

    var chromeLandscape: Bool {
        if let prewarmLandscape {
            return prewarmLandscape
        }
        switch phase {
        case .preparingLandscape, .landscape:
            return true
        case .preparingPortrait, .embedded, .portraitFullscreen, .recovering:
            return isLandscape
        }
    }

    /// 几何布局在系统转场期间使用目标方向；播放器控件树则继续使用
    /// `chromeLandscape`，直到系统完成转场后再切换，避免控件闪烁。
    var layoutLandscape: Bool {
        switch phase {
        case .preparingLandscape:
            return true
        case .preparingPortrait:
            return false
        case .embedded, .landscape, .portraitFullscreen, .recovering:
            return isLandscape
        }
    }

    var pendingTarget: UIInterfaceOrientationMask? {
        requestCoalescer.pendingTarget
    }

    func activate(isLandscape: Bool, isPortraitFullscreen: Bool = false) {
        isViewActive = true
        self.isLandscape = isLandscape
        self.isPortraitFullscreen = isPortraitFullscreen
        prewarmLandscape = nil
        isSystemRotationTransitioning = false
        requestCoalescer.reset()
        setStablePhase(isLandscape: isLandscape, isPortraitFullscreen: isPortraitFullscreen)
    }

    func beginSystemTransition(toLandscape: Bool) {
        requestCoalescer.beginTransition()
        isSystemRotationTransitioning = true
        phase = toLandscape ? .preparingLandscape : .preparingPortrait
    }

    @discardableResult
    func finishSystemTransition(
        toLandscape: Bool,
        currentOrientation: UIInterfaceOrientation
    ) -> UIInterfaceOrientationMask? {
        isSystemRotationTransitioning = false
        isLandscape = toLandscape
        prewarmLandscape = nil
        setStablePhase(isLandscape: toLandscape, isPortraitFullscreen: isPortraitFullscreen)
        return requestCoalescer.completeTransition(currentOrientation: currentOrientation)
    }

    func recover(
        isLandscape: Bool,
        isPortraitFullscreen: Bool = false
    ) {
        phase = .recovering
        isSystemRotationTransitioning = false
        self.isLandscape = isLandscape
        self.isPortraitFullscreen = isPortraitFullscreen
        prewarmLandscape = nil
        requestCoalescer.reset()
        setStablePhase(isLandscape: isLandscape, isPortraitFullscreen: isPortraitFullscreen)
    }

    func reconcileStableState(
        isLandscape: Bool,
        isPortraitFullscreen: Bool = false
    ) {
        isSystemRotationTransitioning = false
        self.isLandscape = isLandscape
        self.isPortraitFullscreen = isPortraitFullscreen
        prewarmLandscape = nil
        setStablePhase(isLandscape: isLandscape, isPortraitFullscreen: isPortraitFullscreen)
    }

    func setPortraitFullscreen(_ active: Bool) {
        guard isPortraitFullscreen != active else { return }
        isLandscape = false
        isPortraitFullscreen = active
        setStablePhase(isLandscape: false, isPortraitFullscreen: active)
    }

    func beginChromePrewarm(for landscape: Bool) {
        prewarmLandscape = landscape
    }

    func endChromePrewarm() {
        prewarmLandscape = nil
    }

    /// 提交一次几何请求。转场中只保留最后一个请求，转场完成后由调用方再次
    /// 提交返回值，避免快速点击横竖屏造成反向请求竞态。
    @discardableResult
    func requestGeometryUpdate(
        to target: UIInterfaceOrientationMask,
        in scene: UIWindowScene?
    ) -> Bool {
        guard let target = requestCoalescer.submit(target) else { return false }
        AppOrientationLock.requestGeometryUpdate(to: target, in: scene)
        return true
    }

    func updateOrientationLock(
        isPortraitVideo: Bool,
        isCurrentlyLandscape: Bool,
        in scene: UIWindowScene?
    ) {
        if isPortraitVideo {
            AppOrientationLock.update(to: .portrait, in: scene)
            if isCurrentlyLandscape {
                requestGeometryUpdate(to: .portrait, in: scene)
            }
        } else {
            AppOrientationLock.update(to: .allButUpsideDown, in: scene)
        }
    }

    func allowLandscape(in scene: UIWindowScene?) {
        AppOrientationLock.update(to: .allButUpsideDown, in: scene)
    }

    func restorePortrait(in scene: UIWindowScene?) {
        isViewActive = false
        requestCoalescer.reset()
        isSystemRotationTransitioning = false
        isLandscape = false
        isPortraitFullscreen = false
        prewarmLandscape = nil
        AppOrientationLock.restorePortrait(in: scene)
    }

    func deactivate(in scene: UIWindowScene?) {
        phase = .recovering
        restorePortrait(in: scene)
        phase = .embedded
    }

    private func setStablePhase(isLandscape: Bool, isPortraitFullscreen: Bool) {
        if isPortraitFullscreen {
            phase = .portraitFullscreen
        } else if isLandscape {
            phase = .landscape
        } else {
            phase = .embedded
        }
    }
}

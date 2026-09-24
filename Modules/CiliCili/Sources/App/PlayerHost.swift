import UIKit

/// 预留的常驻播放器宿主基础设施。
///
/// 当前视频详情页采用系统方向切换，播放器仍由页面内的 `VideoSurfaceView` 承载；
/// 这个宿主窗口默认不安装，避免额外 UIWindow 参与状态栏和方向决策。
@MainActor
final class PlayerHostManager {
    static let shared = PlayerHostManager()
    private init() {}

    private(set) var window: PlayerHostWindow?
    var hostView: PlayerHostView? { window?.hostView }

    /// 在拿到 windowScene 后安装常驻宿主窗口（幂等）。
    func installIfNeeded(in scene: UIWindowScene) {
        guard window == nil else {
            // 场景变化时同步 frame
            window?.frame = scene.effectiveGeometry.coordinateSpace.bounds
            return
        }
        let w = PlayerHostWindow(windowScene: scene)
        w.frame = scene.effectiveGeometry.coordinateSpace.bounds
        w.isHidden = false
        window = w
    }
}

/// 常驻播放器宿主窗口。windowLevel 略高于主 window，使播放器盖在内容上；
/// 通过 hitTest 让非播放器区域的触摸穿透回主 window。
@MainActor
final class PlayerHostWindow: UIWindow {
    let hostView = PlayerHostView()
    private let hostController: PlayerHostRootController

    override init(windowScene: UIWindowScene) {
        hostController = PlayerHostRootController(hostView: hostView)
        super.init(windowScene: windowScene)
        windowLevel = .normal + 1
        backgroundColor = .clear
        rootViewController = hostController
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 触摸穿透：命中宿主背景/空白区域时返回 nil，让事件交回下层主 window。
    /// 命中播放器容器内部（控件等）时正常返回。
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else { return nil }
        if hit === self || hit === rootViewController?.view || hit === hostView {
            return nil
        }
        return hit
    }
}

/// 宿主窗口的根控制器。默认不参与主播放器的系统旋转路径。
@MainActor
final class PlayerHostRootController: UIViewController {
    private let hostView: PlayerHostView

    init(hostView: PlayerHostView) {
        self.hostView = hostView
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let container = ClearPassthroughContainer()
        container.backgroundColor = .clear
        hostView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hostView)
        NSLayoutConstraint.activate([
            hostView.topAnchor.constraint(equalTo: container.topAnchor),
            hostView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            hostView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        view = container
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    override var shouldAutorotate: Bool { false }
    override var prefersStatusBarHidden: Bool { false }
}

/// 自身透明且不接收触摸的容器（触摸穿透）。
@MainActor
final class ClearPassthroughContainer: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else { return nil }
        return hit === self ? nil : hit
    }
}

/// 常驻宿主视图。承载当前活跃播放器的 `VideoSurfaceContainerView`。
///
/// 仅实现“竖屏内联”：把容器定位到 SwiftUI 占位视图上报的屏幕 frame。
@MainActor
final class PlayerHostView: UIView {
    /// 当前挂载的播放器容器（即 VideoSurfaceContainerView，用 UIView 弱类型避免循环依赖编译顺序问题）。
    private weak var mountedContainer: UIView?
    /// 竖屏内联目标 frame（屏幕坐标系），由占位视图上报。
    private var inlineFrameInScreen: CGRect = .zero
    private(set) var isFullscreen = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 把容器挂到宿主上（若已挂载同一个则忽略）。
    func mount(_ container: UIView) {
        guard mountedContainer !== container else { return }
        mountedContainer?.removeFromSuperview()
        mountedContainer = container
        container.translatesAutoresizingMaskIntoConstraints = true
        addSubview(container)
        applyInlineLayout()
    }

    /// 卸载容器（仅当当前挂载的就是它）。容器离开播放页时调用。
    func unmount(_ container: UIView) {
        guard mountedContainer === container else { return }
        container.removeFromSuperview()
        mountedContainer = nil
    }

    /// 占位视图上报它在屏幕上的 frame（竖屏小窗位置）。
    func updateInlineFrame(_ frameInScreen: CGRect, for container: UIView) {
        guard mountedContainer === container else { return }
        inlineFrameInScreen = frameInScreen
        guard !isFullscreen else { return }
        applyInlineLayout()
    }

    private func applyInlineLayout() {
        guard let container = mountedContainer, inlineFrameInScreen.width > 1 else { return }
        // 把屏幕坐标系的 frame 转换到本视图坐标系。host 与主 window 共享同一屏幕。
        let target: CGRect
        if let window {
            let inWindow = window.screen.coordinateSpace.convert(inlineFrameInScreen, to: window.coordinateSpace)
            target = convert(inWindow, from: window)
        } else {
            target = inlineFrameInScreen
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.transform = .identity
        container.frame = target
        container.setNeedsLayout()
        container.layoutIfNeeded()
        CATransaction.commit()
    }
}

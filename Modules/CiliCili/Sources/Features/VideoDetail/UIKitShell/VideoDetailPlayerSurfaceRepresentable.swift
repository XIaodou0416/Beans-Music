import AVFoundation
import SwiftUI

/// SwiftUI 对稳定 UIKit 视频画面的最小桥接。
///
/// 该桥接只负责 `VideoSurfaceContainerView` 的生命周期和原位换绑；播放器
/// 控件、弹幕和详情内容仍由 SwiftUI 管理。旋转或布局更新不会重建 surface。
@MainActor
struct VideoDetailPlayerSurfaceRepresentable: UIViewRepresentable {
    let viewModel: PlayerStateViewModel
    let isPictureInPictureEnabled: Bool
    let videoGravity: AVLayerVideoGravity

    func makeUIView(context _: Context) -> DirectUIKitPlayerSurfaceHostView {
        DirectUIKitPlayerSurfaceHostView(
            viewModel: viewModel,
            isPictureInPictureEnabled: isPictureInPictureEnabled
        )
    }

    func updateUIView(
        _ uiView: DirectUIKitPlayerSurfaceHostView,
        context _: Context
    ) {
        uiView.setPictureInPictureEnabled(isPictureInPictureEnabled)
        uiView.setVideoGravity(videoGravity)
        uiView.setPlayerViewModel(viewModel)
        uiView.refreshLayoutImmediately()
    }

    static func dismantleUIView(
        _ uiView: DirectUIKitPlayerSurfaceHostView,
        coordinator _: ()
    ) {
        uiView.tearDown()
    }
}

/// 把 surface representable 挂到现有播放器协调器所需的 UIKit 容器中。
/// 外层 view 的 identity 在详情页生命周期内保持不变，SwiftUI 只更新
/// representable 的输入值，因此清晰度切换不会拆掉承载 AVPlayerLayer 的 view。
@MainActor
final class VideoDetailSwiftUISurfaceHostingView: UIView, VideoDetailPlayerSurfaceHostingView {
    private let hostingController: UIHostingController<VideoDetailPlayerSurfaceRepresentable>
    private var viewModel: PlayerStateViewModel
    private var isPictureInPictureEnabled: Bool
    private var videoGravity: AVLayerVideoGravity = .resizeAspect
    private var isTornDown = false

    var hostedView: UIView { self }

    init(viewModel: PlayerStateViewModel, isPictureInPictureEnabled: Bool) {
        self.viewModel = viewModel
        self.isPictureInPictureEnabled = isPictureInPictureEnabled
        self.hostingController = UIHostingController(
            rootView: VideoDetailPlayerSurfaceRepresentable(
                viewModel: viewModel,
                isPictureInPictureEnabled: isPictureInPictureEnabled,
                videoGravity: .resizeAspect
            )
        )
        super.init(frame: .zero)

        backgroundColor = .black
        hostingController.safeAreaRegions = []
        hostingController.view.backgroundColor = .clear
        hostingController.view.isOpaque = false
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func attach(to parent: UIViewController) {
        guard !isTornDown, hostingController.parent == nil else { return }
        parent.addChild(hostingController)
        hostingController.didMove(toParent: parent)
    }

    func setPlayerViewModel(_ playerViewModel: PlayerStateViewModel) {
        guard !isTornDown, viewModel !== playerViewModel else { return }
        viewModel = playerViewModel
        updateRootView()
    }

    func setPictureInPictureEnabled(_ isEnabled: Bool) {
        guard !isTornDown, isPictureInPictureEnabled != isEnabled else { return }
        isPictureInPictureEnabled = isEnabled
        updateRootView()
    }

    func setVideoGravity(_ gravity: AVLayerVideoGravity) {
        guard !isTornDown, videoGravity != gravity else { return }
        videoGravity = gravity
        updateRootView()
    }

    func refreshLayoutImmediately() {
        guard !isTornDown else { return }
        hostingController.view.setNeedsLayout()
        hostingController.view.layoutIfNeeded()
    }

    func tearDown() {
        guard !isTornDown else { return }
        isTornDown = true
        hostingController.willMove(toParent: nil)
        hostingController.view.removeFromSuperview()
        hostingController.removeFromParent()
    }

    private func updateRootView() {
        hostingController.rootView = VideoDetailPlayerSurfaceRepresentable(
            viewModel: viewModel,
            isPictureInPictureEnabled: isPictureInPictureEnabled,
            videoGravity: videoGravity
        )
    }
}

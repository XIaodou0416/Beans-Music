import SwiftUI

/// 将直播详情正式接入与视频详情一致的 UIKit 播放外壳。
struct LiveRoomShellRepresentable: UIViewControllerRepresentable {
    @EnvironmentObject private var dependencies: AppDependencies
    @ObservedObject var viewModel: LiveRoomViewModel
    let onNavigateBack: () -> Void

    func makeUIViewController(context _: Context) -> LiveRoomShellViewController {
        LiveRoomShellViewController(
            viewModel: viewModel,
            dependencies: dependencies,
            onNavigateBack: onNavigateBack
        )
    }

    func updateUIViewController(_: LiveRoomShellViewController, context _: Context) {}
}

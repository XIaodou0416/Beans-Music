import SwiftUI

/// 把 SwiftUI 详情页和最小 UIKit 旋转桥接包回父级 SwiftUI 页面。
///
/// binding 与内容区回调从 SwiftUI 侧透传；播放器竖屏“更多”菜单由详情页
/// 最外层 SwiftUI sheet 宿主呈现，与评论回复共用同一条路由。
struct VideoDetailShellRepresentable: UIViewControllerRepresentable {
    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.openVideoOwnerRouteAction) private var openVideoOwnerRoute
    let seedVideo: VideoItem
    @ObservedObject var viewModel: VideoDetailViewModel
    @ObservedObject var runtimeSettings: VideoDetailRuntimeSettingsStore
    @Binding var selectedContentTab: VideoDetailContentTab
    @Binding var sheetRoute: VideoDetailSheetRoute?
    @Binding var isShowingDanmakuSettings: Bool
    @Binding var isShowingFavoriteFolders: Bool
    @Binding var isShowingCoinPicker: Bool
    @Binding var isShowingNetworkDiagnostics: Bool
    let onOpenCommentComposer: (Comment?) -> Void
    let onNavigateBack: () -> Void

    func makeUIViewController(context: Context) -> VideoDetailRotationBridgeViewController {
        // 新路径绕过 PlaybackScene，需自己 bind runtimeSettings，
        // 否则内容区设置（诊断按钮/进度条等）取默认值。
        runtimeSettings.bind(dependencies.libraryStore)
        return VideoDetailRotationBridgeViewController(
            initialVideo: seedVideo,
            viewModel: viewModel,
            runtimeSettings: runtimeSettings,
            dependencies: dependencies,
            openVideoOwnerRoute: openVideoOwnerRoute,
            selectedContentTab: $selectedContentTab,
            onShowNetworkDiagnostics: { isShowingNetworkDiagnostics = true },
            onShowFavoriteFolders: { isShowingFavoriteFolders = true },
            onShowCoinPicker: { isShowingCoinPicker = true },
            onOpenCommentComposer: onOpenCommentComposer,
            onShowDanmakuSettings: { isShowingDanmakuSettings = true },
            onPresentPlayerMoreControls: { playerViewModel, onDismiss in
                guard sheetRoute == nil else {
                    onDismiss()
                    return
                }
                sheetRoute = .moreControls(
                    VideoDetailMoreControlsSheetPresentation(
                        playerViewModel: playerViewModel,
                        onDismiss: onDismiss
                    )
                )
            },
            onDismissPlayerMoreControls: {
                guard case .some(.moreControls(let presentation)) = sheetRoute else { return }
                presentation.finish()
                sheetRoute = nil
            },
            onReply: { comment in
                guard sheetRoute == nil else { return }
                sheetRoute = .commentThread(
                    VideoDetailCommentThreadSheetPresentation(
                        rootComment: comment,
                        secondaryID: nil
                    )
                )
            },
            onNavigateBack: onNavigateBack
        )
    }

    func updateUIViewController(
        _: VideoDetailRotationBridgeViewController,
        context _: Context
    ) {}

    static func dismantleUIViewController(
        _ uiViewController: VideoDetailRotationBridgeViewController,
        coordinator _: Void
    ) {
        uiViewController.prepareForDismantle()
    }
}

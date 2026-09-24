import Combine
import SwiftUI

/// 详情页 UIKit 外壳：竖屏内容区。
///
/// 复用现有 SwiftUI 内容组件（`VideoDetailNativeContentTabView` + 每个 tab 的
/// `VideoDetailContentPage`），不重写。由容器 VC 用 `UIHostingController` 承载。
///
/// 布局对齐原项目「叠放」结构：内容区始终全屏高度，顶部用 `topInset` 留白，
/// 播放器盖在上层收缩。滚动时只有播放器高度变、内容区尺寸不变 → 无反馈抽搐。
struct VideoDetailShellContentView: View {
    @MainActor
    final class State: ObservableObject {
        /// 内容顶部留白 = 播放器最大（expanded）高度。仅在旋转/比例变化时更新，
        /// 滚动时不变（滚动只改播放器实际高度，不动内容区）。
        @Published var topInset: CGFloat = 0
        @Published var bottomInset: CGFloat = 0
        @Published var scrollAdjustment: VideoDetailScrollAdjustment?
        @Published var suppressesInteractiveContentActions = false
        @Published var mountsSecondaryContent = false
        @Published var hidesBottomToolbar = false
        private var scrollAdjustmentToken = 0

        func requestScrollAdjustment(tab: VideoDetailContentTab, offset: CGFloat) {
            scrollAdjustmentToken += 1
            scrollAdjustment = VideoDetailScrollAdjustment(
                tab: tab,
                offset: offset,
                token: scrollAdjustmentToken
            )
        }
    }

    let viewModel: VideoDetailViewModel
    @ObservedObject var updateGate: VideoDetailContentUpdateGate
    @ObservedObject var runtimeSettings: VideoDetailRuntimeSettingsStore
    @ObservedObject var state: State
    let layoutWidth: CGFloat
    let placesTopInsetInScrollContent: Bool
    let interactiveMinimumPlayerHeight: CGFloat
    @Binding var selectedContentTab: VideoDetailContentTab
    let onShowNetworkDiagnostics: () -> Void
    let onShowFavoriteFolders: () -> Void
    let onShowCoinPicker: () -> Void
    let onOpenCommentComposer: (Comment?) -> Void
    let onRefreshComments: () -> Void
    let onReply: (Comment) -> Void
    let openVideoOwnerRoute: ((VideoOwner) -> Void)?
    let onSelectedTabChange: (VideoDetailContentTab) -> Void
    let onSelectionWillChange: (VideoDetailContentTab) -> Void
    let onScrollOffsetChange: (VideoDetailContentTab, CGFloat) -> Void
    let onScrollPhaseChange: (VideoDetailContentTab, ScrollPhase) -> Void

    var body: some View {
        let _ = updateGate.revision
        VideoDetailShellContentBody(
            viewModel: viewModel,
            runtimeSettings: runtimeSettings,
            state: state,
            layoutWidth: layoutWidth,
            placesTopInsetInScrollContent: placesTopInsetInScrollContent,
            interactiveMinimumPlayerHeight: interactiveMinimumPlayerHeight,
            contentRevision: updateGate.revision,
            selectedContentTab: $selectedContentTab,
            onShowNetworkDiagnostics: onShowNetworkDiagnostics,
            onShowFavoriteFolders: onShowFavoriteFolders,
            onShowCoinPicker: onShowCoinPicker,
            onOpenCommentComposer: onOpenCommentComposer,
            onRefreshComments: onRefreshComments,
            onReply: onReply,
            openVideoOwnerRoute: openVideoOwnerRoute,
            onSelectedTabChange: onSelectedTabChange,
            onSelectionWillChange: onSelectionWillChange,
            onScrollOffsetChange: onScrollOffsetChange,
            onScrollPhaseChange: onScrollPhaseChange
        )
    }
}

private struct VideoDetailShellContentBody: View {
    let viewModel: VideoDetailViewModel
    @ObservedObject var runtimeSettings: VideoDetailRuntimeSettingsStore
    @ObservedObject var state: VideoDetailShellContentView.State
    let layoutWidth: CGFloat
    let placesTopInsetInScrollContent: Bool
    let interactiveMinimumPlayerHeight: CGFloat
    let contentRevision: Int
    @Binding var selectedContentTab: VideoDetailContentTab
    let onShowNetworkDiagnostics: () -> Void
    let onShowFavoriteFolders: () -> Void
    let onShowCoinPicker: () -> Void
    let onOpenCommentComposer: (Comment?) -> Void
    let onRefreshComments: () -> Void
    let onReply: (Comment) -> Void
    let openVideoOwnerRoute: ((VideoOwner) -> Void)?
    let onSelectedTabChange: (VideoDetailContentTab) -> Void
    let onSelectionWillChange: (VideoDetailContentTab) -> Void
    let onScrollOffsetChange: (VideoDetailContentTab, CGFloat) -> Void
    let onScrollPhaseChange: (VideoDetailContentTab, ScrollPhase) -> Void

    var body: some View {
        let contentActionsSuppressed = state.suppressesInteractiveContentActions
        VideoDetailNativeContentTabView(
            selection: $selectedContentTab,
            layoutWidth: layoutWidth,
            topInset: state.topInset,
            bottomInset: state.bottomInset,
            scrollAdjustment: state.scrollAdjustment,
            mountsSecondaryContent: !runtimeSettings.defersVideoDetailSecondaryContent
            || state.mountsSecondaryContent,
            hidesBottomToolbar: state.hidesBottomToolbar,
            placesTopInsetInScrollContent: placesTopInsetInScrollContent,
            interactiveMinimumPlayerHeight: interactiveMinimumPlayerHeight,
            contentRevision: contentRevision,
            onOpenCommentComposer: { onOpenCommentComposer(nil) },
            onRefreshComments: onRefreshComments,
            onSelectionWillChange: onSelectionWillChange,
            onScrollOffsetChange: onScrollOffsetChange,
            onScrollPhaseChange: onScrollPhaseChange,
            summary: AnyView(
                VideoDetailLoadedDetailContentPage(
                    viewModel: viewModel,
                    layoutWidth: layoutWidth,
                    mountsSecondaryContent: false,
                    runtimeSettings: runtimeSettings.snapshot,
                    onShowNetworkDiagnostics: onShowNetworkDiagnostics,
                    onShowFavoriteFolders: onShowFavoriteFolders,
                    onShowCoinPicker: onShowCoinPicker,
                    showsRecommendations: false
                )
                .accessibilityIdentifier("video.detail.summary")
            ),
            content: { tab, mountsSecondaryContent in
                VideoDetailContentPage(
                    viewModel: viewModel,
                    layoutWidth: layoutWidth,
                    tab: tab,
                    mountsSecondaryContent: mountsSecondaryContent,
                    runtimeSettings: runtimeSettings.snapshot,
                    onShowNetworkDiagnostics: onShowNetworkDiagnostics,
                    onShowFavoriteFolders: onShowFavoriteFolders,
                    onShowCoinPicker: onShowCoinPicker,
                    onReply: { comment in
                        guard !contentActionsSuppressed else { return }
                        onReply(comment)
                    },
                    showsSummary: false,
                    onComposeReply: { onOpenCommentComposer($0) }
                )
            }
        )
        .allowsHitTesting(!contentActionsSuppressed)
        .environment(\.openVideoOwnerRouteAction, openVideoOwnerRoute)
        .environment(\.commentContentOwnerMID, viewModel.detail.owner?.mid)
        .onChange(of: selectedContentTab) { _, tab in
            onSelectedTabChange(tab)
        }
        .background(VideoDetailTheme.background)
    }
}

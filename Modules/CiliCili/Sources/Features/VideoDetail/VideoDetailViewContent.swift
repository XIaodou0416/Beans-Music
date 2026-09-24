import SwiftUI

struct VideoDetailViewContent: View {
    let seedVideo: VideoItem
    @ObservedObject var holder: VideoDetailViewModelHolder
    @ObservedObject var runtimeSettings: VideoDetailRuntimeSettingsStore
    @Binding var selectedContentTab: VideoDetailContentTab
    @Binding var sheetRoute: VideoDetailSheetRoute?
    @Binding var pendingCommentAnchor: VideoCommentAnchor?
    @Binding var isShowingDanmakuSettings: Bool
    @Binding var isShowingFavoriteFolders: Bool
    @Binding var isShowingCoinPicker: Bool
    @Binding var isShowingNetworkDiagnostics: Bool
    let onNavigateBack: () -> Void
    let lifecycleActions: VideoDetailViewContentLifecycleActions

    var body: some View {
        PlaybackDetailLoadedStatePage(
            holder.viewModel,
            performanceContext: .video(seedVideo)
        ) { viewModel in
            VideoDetailViewContentResolver(
                seedVideo: seedVideo,
                runtimeSettings: runtimeSettings,
                viewModel: viewModel,
                selectedContentTab: $selectedContentTab,
                sheetRoute: $sheetRoute,
                pendingCommentAnchor: $pendingCommentAnchor,
                isShowingDanmakuSettings: $isShowingDanmakuSettings,
                isShowingFavoriteFolders: $isShowingFavoriteFolders,
                isShowingCoinPicker: $isShowingCoinPicker,
                isShowingNetworkDiagnostics: $isShowingNetworkDiagnostics,
                onNavigateBack: onNavigateBack
            )
        } initialContent: {
            VideoDetailInitialContentResolver(
                seedVideo: seedVideo,
                selectedContentTab: $selectedContentTab,
                runtimeSettings: runtimeSettings.snapshot,
                onNavigateBack: onNavigateBack,
                lifecycleActions: lifecycleActions
            )
        }
    }
}

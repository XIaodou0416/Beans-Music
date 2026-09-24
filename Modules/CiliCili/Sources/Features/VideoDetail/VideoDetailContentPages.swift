import SwiftUI

struct VideoDetailContentPage: View {
    let viewModel: VideoDetailViewModel
    let layoutWidth: CGFloat
    let tab: VideoDetailContentTab
    let mountsSecondaryContent: Bool
    let runtimeSettings: VideoDetailRuntimeSettingsSnapshot
    let onShowNetworkDiagnostics: () -> Void
    let onShowFavoriteFolders: () -> Void
    let onShowCoinPicker: () -> Void
    let onReply: (Comment) -> Void
    var showsSummary = true
    var onComposeReply: ((Comment) -> Void)? = nil

    var body: some View {
        PlaybackDetailContentPage(
            layoutWidth: layoutWidth,
            topPadding: PlaybackDetailContentMetrics.topPadding,
            spacing: PlaybackDetailContentMetrics.spacing,
            background: VideoDetailTheme.background
        ) { _ in
            VideoDetailContentPageBody(
                viewModel: viewModel,
                layoutWidth: layoutWidth,
                tab: tab,
                mountsSecondaryContent: mountsSecondaryContent,
                runtimeSettings: runtimeSettings,
                onShowNetworkDiagnostics: onShowNetworkDiagnostics,
                onShowFavoriteFolders: onShowFavoriteFolders,
                onShowCoinPicker: onShowCoinPicker,
                onReply: onReply,
                showsSummary: showsSummary,
                onComposeReply: onComposeReply
            )
        }
        .commentLikeTarget(
            oid: viewModel.commentTarget?.oid,
            type: viewModel.commentTarget?.type,
            referer: videoReferer
        )
    }

    private var videoReferer: String {
        let bvid = viewModel.detail.bvid.trimmingCharacters(in: .whitespacesAndNewlines)
        return bvid.isEmpty ? "https://www.bilibili.com" : "https://www.bilibili.com/video/\(bvid)"
    }
}

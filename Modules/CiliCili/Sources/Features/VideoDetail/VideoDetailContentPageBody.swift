import SwiftUI

struct VideoDetailContentPageBody: View {
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
        switch tab {
        case .detail:
            VideoDetailLoadedDetailContentPage(
                viewModel: viewModel,
                layoutWidth: layoutWidth,
                mountsSecondaryContent: mountsSecondaryContent,
                runtimeSettings: runtimeSettings,
                onShowNetworkDiagnostics: onShowNetworkDiagnostics,
                onShowFavoriteFolders: onShowFavoriteFolders,
                onShowCoinPicker: onShowCoinPicker,
                showsSummary: showsSummary
            )

        case .comments:
            if mountsSecondaryContent {
                VideoDetailLoadedCommentsContentPage(
                    viewModel: viewModel,
                    onReply: onReply,
                    onComposeReply: onComposeReply
                )
            } else {
                Color.clear
                    .frame(minHeight: 320)
                    .accessibilityHidden(true)
            }
        }
    }
}

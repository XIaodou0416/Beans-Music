import SwiftUI

struct VideoDetailInitialPlaybackStage: View {
    let seedVideo: VideoItem
    let layout: VideoDetailInitialPlaybackLayout
    let containerHeight: CGFloat
    @Binding var selectedContentTab: VideoDetailContentTab
    let runtimeSettings: VideoDetailRuntimeSettingsSnapshot
    let onNavigateBack: () -> Void

    var body: some View {
        PlaybackDetailPlayerStage(
            screenSize: CGSize(width: layout.width, height: containerHeight),
            background: VideoDetailTheme.background
        ) {
            VideoDetailNativeContentTabView(
                selection: $selectedContentTab,
                layoutWidth: layout.width,
                topInset: layout.playerHeight,
                mountsSecondaryContent: !runtimeSettings.defersVideoDetailSecondaryContent,
                onScrollOffsetChange: nil
            ) { tab, mountsSecondaryContent in
                InitialVideoDetailContentPage(
                    seedVideo: seedVideo,
                    layoutWidth: layout.width,
                    tab: tab,
                    mountsSecondaryContent: mountsSecondaryContent
                )
            }
        } player: {
            VideoDetailInitialPlayerPlaceholder(
                width: layout.width,
                height: layout.playerHeight,
                showsPinnedProgressBar: runtimeSettings.showsPinnedProgressBar,
                onNavigateBack: onNavigateBack
            )
        }
        .overlay(alignment: .top) {
            VideoDetailStatusBarBackdrop(isHidden: false)
        }
        .background(VideoDetailTheme.background)
    }
}

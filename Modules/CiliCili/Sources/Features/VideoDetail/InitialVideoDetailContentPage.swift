import SwiftUI

struct InitialVideoDetailContentPage: View {
    let seedVideo: VideoItem
    let layoutWidth: CGFloat
    let tab: VideoDetailContentTab
    let mountsSecondaryContent: Bool

    var body: some View {
        PlaybackDetailContentPage(
            layoutWidth: layoutWidth,
            topPadding: PlaybackDetailContentMetrics.topPadding,
            spacing: PlaybackDetailContentMetrics.spacing,
            background: VideoDetailTheme.background
        ) { _ in
            InitialVideoDetailContentPageBody(
                seedVideo: seedVideo,
                layoutWidth: layoutWidth,
                tab: tab,
                mountsSecondaryContent: mountsSecondaryContent
            )
        }
    }
}

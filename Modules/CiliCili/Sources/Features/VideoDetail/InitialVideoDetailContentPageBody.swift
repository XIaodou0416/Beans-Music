import SwiftUI

struct InitialVideoDetailContentPageBody: View {
    let seedVideo: VideoItem
    let layoutWidth: CGFloat
    let tab: VideoDetailContentTab
    let mountsSecondaryContent: Bool

    var body: some View {
        switch tab {
        case .detail:
            InitialVideoDetailDetailContentPage(
                seedVideo: seedVideo,
                layoutWidth: layoutWidth,
                mountsSecondaryContent: mountsSecondaryContent
            )

        case .comments:
            if mountsSecondaryContent {
                InitialVideoDetailCommentsContentPage()
            } else {
                Color.clear
                    .frame(minHeight: 320)
                    .accessibilityHidden(true)
            }
        }
    }
}

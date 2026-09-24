import SwiftUI

struct HomeFeedVideoCardButton: View {
    let metrics: HomeFeedLayoutMetrics
    let video: VideoItem
    let display: VideoCardDisplayModel
    let actions: HomeFeedContentActions

    var body: some View {
        if let onVideoSelect = actions.onVideoSelect {
            Button {
                onVideoSelect(video)
            } label: {
                HomeFeedVideoCardLabel(
                    metrics: metrics,
                    display: display
                )
            }
            .buttonStyle(.plain)
            .buttonStyle(PressPreloadButtonStyle {
                actions.onVideoPress(video)
            })
        } else {
            Button {
                actions.onVideoTap(video)
            } label: {
                HomeFeedVideoCardLabel(
                    metrics: metrics,
                    display: display
                )
            }
            .buttonStyle(PressPreloadButtonStyle {
                actions.onVideoPress(video)
            })
        }
    }
}

import SwiftUI

extension LiveRoomContentView {
    func detailScrollPage(_ viewModel: LiveRoomViewModel, layoutWidth: CGFloat) -> some View {
        PlaybackDetailContentPage(
            layoutWidth: layoutWidth,
            horizontalPadding: PlaybackDetailContentMetrics.horizontalPadding,
            topPadding: PlaybackDetailContentMetrics.topPadding,
            bottomPadding: 28,
            spacing: PlaybackDetailContentMetrics.spacing,
            background: VideoDetailTheme.background
        ) { contentWidth in
            liveDetailControls(viewModel, contentWidth: contentWidth)
        }
    }

    func liveDetailControls(_ viewModel: LiveRoomViewModel, contentWidth: CGFloat) -> some View {
        LiveRoomMinimalDetailHeader(viewModel: viewModel)
        .frame(width: contentWidth, alignment: .leading)
    }
}

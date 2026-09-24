import SwiftUI

struct VideoDetailInitialPlayerPlaceholderProgressLayer: View {
    let width: CGFloat

    var body: some View {
        VideoDetailPinnedProgressPlaceholder()
            .frame(width: width, height: VideoDetailPinnedProgressBar.height)
    }
}

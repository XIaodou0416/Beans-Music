import SwiftUI

struct VideoDetailPinnedProgressPlaceholder: View {
    var body: some View {
        VideoDetailPinnedStaticProgressTrack(progress: 0)
            .accessibilityHidden(true)
    }
}

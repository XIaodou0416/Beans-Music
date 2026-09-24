import SwiftUI

struct VideoDetailPinnedStaticProgressTrack: View {
    let progress: Double

    var body: some View {
        let clampedProgress = min(max(progress, 0), 1)

        ZStack(alignment: .bottomLeading) {
            Color.clear

            Capsule()
                .fill(Color.white.opacity(0.24))
                .frame(height: VideoDetailPinnedProgressBar.visibleHeight)

            Capsule()
                .fill(Color(red: 1.0, green: 0.36, blue: 0.58))
                .frame(maxWidth: .infinity)
                .frame(height: VideoDetailPinnedProgressBar.visibleHeight)
                .scaleEffect(x: clampedProgress, y: 1, anchor: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .frame(height: VideoDetailPinnedProgressBar.height)
    }
}

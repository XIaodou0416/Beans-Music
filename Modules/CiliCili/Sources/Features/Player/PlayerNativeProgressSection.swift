import SwiftUI

struct PlayerNativeProgressSection: View {
    let metrics: PlayerNativeControlMetrics
    let clock: PlayerPlaybackClock
    let canSeek: Bool
    let sliderVisualScale: CGFloat
    let style: PlayerNativeProgressStyle
    let onScrubStart: (Double) -> Void
    let onScrubChanged: (Double) -> Void
    let onScrubEnded: (Double) -> Void
    let onScrubCancelled: () -> Void

    var body: some View {
        PlayerNativeProgressSlider(
            clock: clock,
            canSeek: canSeek,
            sliderVisualScale: sliderVisualScale,
            style: style,
            onScrubStart: onScrubStart,
            onScrubChanged: onScrubChanged,
            onScrubEnded: onScrubEnded,
            onScrubCancelled: onScrubCancelled
        )
        .padding(.horizontal, metrics.sliderHorizontalPadding)
        .frame(maxWidth: .infinity)
        .frame(height: metrics.progressControlHeight)
    }
}

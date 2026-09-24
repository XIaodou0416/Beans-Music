import SwiftUI

struct PlayerNativeTimeLabel: View {
    @ObservedObject var clock: PlayerPlaybackClock
    let metrics: PlayerNativeControlMetrics

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Text(fullTimeText)
            Text(currentText)
        }
        .font(metrics.timeFont)
        .biliLiquidGlassForeground(shadowOpacity: 0.20)
        .lineLimit(1)
        .minimumScaleFactor(0.82)
        .accessibilityLabel("播放时间 \(fullTimeText)")
    }

    private var currentText: String {
        BiliFormatters.duration(Int(clock.displayCurrentTime.rounded()))
    }

    private var fullTimeText: String {
        guard let duration = clock.duration, duration > 0 else {
            return "\(currentText) / --:--"
        }
        return "\(currentText) / \(BiliFormatters.duration(Int(duration.rounded())))"
    }
}

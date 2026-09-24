import SwiftUI

struct PlayerPerformanceOverlayStartupWaterfallTrack: View {
    let milliseconds: Int
    let maxMilliseconds: Int

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.secondary.opacity(0.13))
                .frame(width: 70, height: 5)

            Capsule()
                .fill(PlayerPerformanceOverlayFormatting.metricColor(milliseconds).opacity(0.88))
                .frame(
                    width: PlayerPerformanceOverlayFormatting.startupWaterfallBarWidth(
                        milliseconds: milliseconds,
                        maxMilliseconds: maxMilliseconds
                    ),
                    height: 5
                )
        }
    }
}

import SwiftUI

struct PlayerPerformanceOverlayMetricsGrid: View {
    let session: PlayerPerformanceSession

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.fixed(74), spacing: 8),
                GridItem(.fixed(74), spacing: 8)
            ],
            alignment: .leading,
            spacing: 6
        ) {
            PlayerPerformanceOverlayMetricCell(title: "总首帧", milliseconds: session.firstFrameTotalMilliseconds)
            PlayerPerformanceOverlayMetricCell(title: "播放器", milliseconds: session.firstFramePlayerMilliseconds)
            PlayerPerformanceOverlayMetricCell(title: "Detail", milliseconds: session.detailLoadMilliseconds)
            PlayerPerformanceOverlayMetricCell(title: "取流", milliseconds: session.playURLMilliseconds)
            PlayerPerformanceOverlayMetricCell(title: "Prepare", milliseconds: session.prepareMilliseconds)
            PlayerPerformanceOverlayMetricCell(title: "续播", milliseconds: session.resumeApplyMilliseconds)
            PlayerPerformanceOverlayMetricCell(title: "续验", milliseconds: session.lastResumeRecoveryMilliseconds)
        }
    }
}

private struct PlayerPerformanceOverlayMetricCell: View {
    let title: String
    let milliseconds: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(PlayerPerformanceOverlayFormatting.millisecondsText(milliseconds))
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(PlayerPerformanceOverlayFormatting.metricColor(milliseconds))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

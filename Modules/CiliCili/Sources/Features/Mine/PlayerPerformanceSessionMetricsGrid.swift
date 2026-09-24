import SwiftUI

struct PlayerPerformanceSessionMetricsGrid: View {
    let session: PlayerPerformanceSession

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ],
            alignment: .leading,
            spacing: 8
        ) {
            PlayerPerformanceSessionMetric(title: "总首帧", milliseconds: session.firstFrameTotalMilliseconds, icon: "bolt.fill")
            PlayerPerformanceSessionMetric(title: "播放器首帧", milliseconds: session.firstFramePlayerMilliseconds, icon: "play.rectangle")
            PlayerPerformanceSessionMetric(title: "详情", milliseconds: session.detailLoadMilliseconds, icon: "doc.text.magnifyingglass")
            PlayerPerformanceSessionMetric(title: "播放地址", milliseconds: session.playURLMilliseconds, icon: "link")
            PlayerPerformanceSessionMetric(title: "Prepare", milliseconds: session.prepareMilliseconds, icon: "gearshape")
            PlayerPerformanceSessionMetric(title: "续播 Seek", milliseconds: session.resumeApplyMilliseconds, icon: "clock.arrow.circlepath")
            PlayerPerformanceSessionMetric(title: "续播落点", milliseconds: session.lastResumeRecoveryMilliseconds, icon: "checkmark.circle")
        }
    }
}

private struct PlayerPerformanceSessionMetric: View {
    let title: String
    let milliseconds: Int?
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(PlayerPerformanceMetricText.millisecondsText(milliseconds))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(PlayerPerformanceMetricText.metricColor(milliseconds))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

import SwiftUI

struct PlayerPerformanceMetricGrid: View {
    let group: PlayerPerformanceSampleGroup

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ],
            alignment: .leading,
            spacing: 8
        ) {
            PlayerPerformanceMillisecondsMetric(title: "平均首帧", milliseconds: group.averageFirstFrameMilliseconds, icon: "bolt.fill")
            PlayerPerformanceMillisecondsMetric(title: "首帧 P50", milliseconds: group.p50FirstFrameMilliseconds, icon: "chart.bar")
            PlayerPerformanceMillisecondsMetric(title: "首帧 P90", milliseconds: group.p90FirstFrameMilliseconds, icon: "chart.bar.fill")
            PlayerPerformanceMillisecondsMetric(title: "播放器首帧", milliseconds: group.averagePlayerFirstFrameMilliseconds, icon: "play.rectangle")
            PlayerPerformanceMillisecondsMetric(title: "播放地址", milliseconds: group.averagePlayURLMilliseconds, icon: "link")
            PlayerPerformanceMillisecondsMetric(title: "Prepare", milliseconds: group.averagePrepareMilliseconds, icon: "gearshape")
            PlayerPerformanceMillisecondsMetric(title: "Seek 恢复", milliseconds: group.averageSeekRecoveryMilliseconds, icon: "speedometer")
            PlayerPerformanceSeekCoverageMetric(coverage: group.averageSeekBufferReadyCoveragePercent)
            PlayerPerformanceBitrateMetric(kilobitsPerSecond: group.averageObservedBitrateKilobitsPerSecond)
        }
    }
}

private struct PlayerPerformanceMillisecondsMetric: View {
    let title: String
    let milliseconds: Int?
    let icon: String

    var body: some View {
        PlayerPerformanceMetricCell(
            title: title,
            value: PlayerPerformanceMetricText.millisecondsText(milliseconds),
            color: PlayerPerformanceMetricText.metricColor(milliseconds),
            icon: icon
        )
    }
}

private struct PlayerPerformanceSeekCoverageMetric: View {
    let coverage: Int?

    var body: some View {
        PlayerPerformanceMetricCell(
            title: "Seek 缓冲",
            value: coverageText,
            color: coverageColor,
            icon: "gauge.with.dots.needle.67percent"
        )
    }

    private var coverageText: String {
        guard let coverage else { return "-" }
        return "\(coverage)%"
    }

    private var coverageColor: Color {
        guard let coverage else { return .secondary }
        if coverage < 70 {
            return .orange
        }
        return .green
    }
}

private struct PlayerPerformanceBitrateMetric: View {
    let kilobitsPerSecond: Int?

    var body: some View {
        PlayerPerformanceMetricCell(
            title: "实际码率",
            value: bitrateText,
            color: bitrateColor,
            icon: "dot.radiowaves.left.and.right"
        )
    }

    private var bitrateText: String {
        guard let kbps = kilobitsPerSecond, kbps > 0 else { return "-" }
        if kbps >= 1_000 {
            return String(format: "%.1fMbps", Double(kbps) / 1_000)
        }
        return "\(kbps)Kbps"
    }

    private var bitrateColor: Color {
        guard let kbps = kilobitsPerSecond, kbps > 0 else { return .secondary }
        if kbps < 900 {
            return .orange
        }
        return .green
    }
}

private struct PlayerPerformanceMetricCell: View {
    let title: String
    let value: String
    let color: Color
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

                Text(value)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

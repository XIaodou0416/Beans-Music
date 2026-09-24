import SwiftUI

struct PlayerPerformanceOverlayStartupLines: View {
    let session: PlayerPerformanceSession

    var body: some View {
        Group {
            if let startupBreakdownMessage = session.startupBreakdownMessage {
                PlayerPerformanceOverlayStartupBreakdownSection(message: startupBreakdownMessage)
            }

            if let prepareStageMessage = session.prepareStageMessage {
                PlayerPerformanceOverlayPrepareStagesSection(message: prepareStageMessage)
            }

            if let startupGapMessage = session.startupGapMessage {
                PlayerPerformanceOverlayStartupGapsSection(message: startupGapMessage)
            }
        }
    }
}

private struct PlayerPerformanceOverlayStartupBreakdownSection: View {
    let message: String

    private var metrics: [PrepareStageMetric] {
        PlayerPerformanceOverlayFormatting.startupBreakdownMetrics(from: message)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Startup breakdown", systemImage: "chart.bar.xaxis")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            if metrics.isEmpty {
                Text(message)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 6),
                        GridItem(.flexible(), spacing: 6)
                    ],
                    alignment: .leading,
                    spacing: 4
                ) {
                    ForEach(metrics, id: \.name) { metric in
                        PlayerPerformanceOverlayStartupBreakdownMetricRow(metric: metric)
                    }
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(
            PlayerPerformanceOverlayFormatting.sectionBackground,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
    }
}

private struct PlayerPerformanceOverlayStartupBreakdownMetricRow: View {
    let metric: PrepareStageMetric

    var body: some View {
        HStack(spacing: 3) {
            Text(metric.name)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 2)

            Text(metric.value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(
                    PlayerPerformanceOverlayFormatting.metricColor(
                        PlayerPerformanceOverlayFormatting.millisecondsValue(from: metric.value)
                    )
                )
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
    }
}

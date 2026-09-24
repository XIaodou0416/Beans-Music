import SwiftUI

struct PlayerPerformanceOverlayPrepareStageMetricRow: View {
    let stage: PrepareStageMetric

    var body: some View {
        HStack(spacing: 3) {
            Text(stage.name)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 2)

            Text(stage.value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(PlayerPerformanceOverlayFormatting.metricColor(stage.milliseconds))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

struct PlayerPerformanceOverlayStartupWaterfallStageRow: View {
    let stage: StartupWaterfallStage
    let maxMilliseconds: Int

    var body: some View {
        HStack(spacing: 5) {
            Text(stage.title)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 48, alignment: .leading)

            PlayerPerformanceOverlayStartupWaterfallTrack(
                milliseconds: stage.milliseconds,
                maxMilliseconds: maxMilliseconds
            )

            Spacer(minLength: 2)

            Text(PlayerPerformanceOverlayFormatting.millisecondsText(stage.milliseconds))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(PlayerPerformanceOverlayFormatting.metricColor(stage.milliseconds))
                .lineLimit(1)
                .frame(width: 43, alignment: .trailing)
        }
    }
}

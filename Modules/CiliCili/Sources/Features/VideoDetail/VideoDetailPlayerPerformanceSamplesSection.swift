import SwiftUI

struct PlayerPerformanceOverlaySamplesSection: View {
    let samples: [PlayerStartupPerformanceSample]

    private var comparableSamples: [PlayerStartupPerformanceSample] {
        PlayerPerformanceOverlayFormatting.comparableStartupSamples(from: samples)
    }

    private var stableSamples: [PlayerStartupPerformanceSample] {
        PlayerPerformanceOverlayFormatting.stableStartupSamples(from: samples)
    }

    private var summaries: [StartupSampleMetricSummary] {
        PlayerPerformanceOverlayFormatting.startupSampleSummaries(from: stableSamples)
    }

    private var filterText: String? {
        PlayerPerformanceOverlayFormatting.startupSampleFilterText(for: samples)
    }

    private var ignoredSampleCount: Int {
        max(samples.count - comparableSamples.count, 0)
    }

    private var coldSampleCount: Int {
        max(comparableSamples.count - stableSamples.count, 0)
    }

    private var sampleNoteText: String? {
        guard let filterText else { return nil }
        var parts = [filterText]
        if coldSampleCount > 0 {
            parts.append("统计已排除 \(coldSampleCount) 条冷启动样本")
        }
        if ignoredSampleCount > 0 {
            parts.append("另忽略 \(ignoredSampleCount) 条不同清晰度/编码样本")
        }
        if coldSampleCount == 0 && ignoredSampleCount == 0 {
            parts.append("样本一致")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Label("稳定 \(stableSamples.count)/\(comparableSamples.count) 次首帧", systemImage: "clock.arrow.circlepath")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if let latest = samples.last?.firstFramePlayerMilliseconds {
                    Text("last \(PlayerPerformanceOverlayFormatting.millisecondsText(latest))")
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(PlayerPerformanceOverlayFormatting.metricColor(latest))
                }
            }

            if summaries.isEmpty {
                Text("反复进入同一个视频后会自动累计样本")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 48), spacing: 6),
                        GridItem(.fixed(44), spacing: 6),
                        GridItem(.fixed(44), spacing: 6),
                        GridItem(.fixed(44), spacing: 6)
                    ],
                    alignment: .leading,
                    spacing: 4
                ) {
                    sampleHeader("项")
                    sampleHeader("min")
                    sampleHeader("avg")
                    sampleHeader("max")

                    ForEach(summaries) { summary in
                        Text(summary.title)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        sampleValue(summary.minimumMilliseconds)
                        sampleValue(summary.averageMilliseconds)
                        sampleValue(summary.maximumMilliseconds)
                    }
                }

                if let sampleNoteText {
                    Text(sampleNoteText)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
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

    private func sampleHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
    }

    private func sampleValue(_ milliseconds: Int) -> some View {
        Text(PlayerPerformanceOverlayFormatting.millisecondsText(milliseconds))
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(PlayerPerformanceOverlayFormatting.metricColor(milliseconds))
            .lineLimit(1)
            .minimumScaleFactor(0.65)
    }
}

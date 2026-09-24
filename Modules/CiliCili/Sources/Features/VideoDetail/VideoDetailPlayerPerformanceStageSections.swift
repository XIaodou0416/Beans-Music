import SwiftUI

struct PlayerPerformanceOverlayStartupWaterfallSection: View {
    let session: PlayerPerformanceSession

    var body: some View {
        let stages = PlayerPerformanceOverlayFormatting.startupWaterfallStages(for: session)
        if !stages.isEmpty {
            let maxMilliseconds = max(stages.map(\.milliseconds).max() ?? 1, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text("First frame")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(stages) { stage in
                    PlayerPerformanceOverlayStartupWaterfallStageRow(
                        stage: stage,
                        maxMilliseconds: maxMilliseconds
                    )
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
}

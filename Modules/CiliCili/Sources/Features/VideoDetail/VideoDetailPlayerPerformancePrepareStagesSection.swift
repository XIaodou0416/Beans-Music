import SwiftUI

struct PlayerPerformanceOverlayPrepareStagesSection: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Prepare stages")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 6),
                    GridItem(.flexible(), spacing: 6)
                ],
                alignment: .leading,
                spacing: 4
            ) {
                ForEach(PlayerPerformanceOverlayFormatting.prepareStageMetrics(from: message), id: \.name) { stage in
                    PlayerPerformanceOverlayPrepareStageMetricRow(stage: stage)
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

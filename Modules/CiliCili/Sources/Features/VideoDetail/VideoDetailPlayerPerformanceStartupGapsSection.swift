import SwiftUI

struct PlayerPerformanceOverlayStartupGapsSection: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Startup gaps")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(message)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(
            PlayerPerformanceOverlayFormatting.sectionBackground,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
    }
}

import SwiftUI

struct PlayerPerformanceOverlayTerminalSection: View {
    let session: PlayerPerformanceSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let qualitySupplementMessage = session.qualitySupplementMessage {
                Text(qualitySupplementMessage)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.orange)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let failure = session.failureMessage {
                Text(failure)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

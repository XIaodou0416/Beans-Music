import SwiftUI

struct PlayerPerformanceOverlayResumeLines: View {
    let session: PlayerPerformanceSession

    var body: some View {
        Group {
            if let resumeDecisionMessage = session.resumeDecisionMessage {
                Label(resumeDecisionMessage, systemImage: "clock.arrow.circlepath")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let resumeRecoveryMessage = session.resumeRecoveryMessage {
                Label(resumeRecoveryMessage, systemImage: "checkmark.circle")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(session.resumeRecoverySlowCount > 0 ? .orange : .secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

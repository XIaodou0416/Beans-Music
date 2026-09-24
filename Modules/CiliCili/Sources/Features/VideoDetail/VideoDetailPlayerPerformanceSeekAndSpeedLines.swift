import SwiftUI

struct PlayerPerformanceOverlaySeekAndSpeedLines: View {
    let session: PlayerPerformanceSession

    var body: some View {
        Group {
            if let seekMessage = session.seekMessage {
                Label(seekMessage, systemImage: "forward.frame")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let seekRecoveryMessage = session.seekRecoveryMessage {
                Label(seekRecoveryMessage, systemImage: "speedometer")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(session.seekRecoverySlowCount > 0 ? .orange : .secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let speedBoostMessage = session.speedBoostMessage {
                Label(speedBoostMessage, systemImage: "forward.fill")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(session.speedBoostInterruptionCount > 0 ? .orange : .secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

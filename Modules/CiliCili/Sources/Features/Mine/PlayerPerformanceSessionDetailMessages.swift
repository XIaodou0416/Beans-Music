import SwiftUI

struct PlayerPerformanceSessionDetailMessages: View {
    let session: PlayerPerformanceSession

    var body: some View {
        if let cdnHostMessage = session.cdnHostMessage {
            Label(cdnHostMessage, systemImage: "network")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }

        optionalMessage(session.networkMessage, color: .secondary, lineLimit: 2)
        optionalMessage(session.hlsStartupMessage, color: .secondary, lineLimit: 2)
        optionalMessage(session.startupSchedulerMessage, color: .secondary, lineLimit: 2)
        optionalMessage(session.accessLogMessage, color: accessLogColor, lineLimit: 3)
        optionalMessage(session.mediaCacheMessage, color: .secondary, lineLimit: 2)
        optionalMessage(session.manifestStageMessage, color: .secondary, lineLimit: 3)
        optionalMessage(session.prepareStageMessage, color: .secondary, lineLimit: 2)
        optionalMessage(session.qualitySupplementMessage, color: .orange, lineLimit: 3)
        optionalMessage(session.resumeRecoveryMessage, color: resumeRecoveryColor, lineLimit: 3)
        optionalMessage(session.seekRecoveryMessage, color: seekRecoveryColor, lineLimit: 3)
        optionalMessage(session.playbackRecoveryMessage, color: playbackRecoveryColor, lineLimit: 3)
    }

    private var accessLogColor: Color {
        (session.accessLogStallCount ?? 0) > 0 ? .orange : .secondary
    }

    private var resumeRecoveryColor: Color {
        session.resumeRecoverySlowCount > 0 ? .orange : .secondary
    }

    private var seekRecoveryColor: Color {
        session.seekRecoverySlowCount > 0 ? .orange : .secondary
    }

    private var playbackRecoveryColor: Color {
        session.playbackRecoveryFailureCount > 0 ? .orange : .secondary
    }

    @ViewBuilder
    private func optionalMessage(_ message: String?, color: Color, lineLimit: Int) -> some View {
        if let message {
            Text(message)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(lineLimit)
        }
    }
}

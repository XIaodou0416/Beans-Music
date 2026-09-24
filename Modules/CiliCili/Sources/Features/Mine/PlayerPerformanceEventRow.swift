import SwiftUI

struct PlayerPerformanceEventRow: View {
    let event: PlayerPerformanceEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Label(event.kind.title, systemImage: systemImage(for: event.kind))
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(event.date, style: .time)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let title = event.title, !title.isEmpty {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Text(event.metricsID)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                if let message = event.message, !message.isEmpty {
                    Text(message)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func systemImage(for kind: PlayerPerformanceEvent.Kind) -> String {
        switch kind {
        case .routeOpen: return "arrow.up.forward.app"
        case .detailLoadStart, .detailLoaded: return "doc.text.magnifyingglass"
        case .playURLStart, .playURLLoaded: return "link"
        case .playerCreated: return "play.rectangle"
        case .prepareRequested, .mediaPrepared, .prepareReturned: return "gearshape"
        case .playRequested: return "play.fill"
        case .firstFrame: return "bolt.fill"
        case .startupBreakdown: return "chart.bar.xaxis"
        case .startupScheduler: return "arrow.triangle.branch"
        case .buffering: return "hourglass"
        case .network: return "network"
        case .accessLog: return "dot.radiowaves.left.and.right"
        case .decodeLog: return "cpu"
        case .mediaCache: return "externaldrive.fill.badge.checkmark"
        case .manifestStage: return "waveform.path.ecg.rectangle"
        case .qualitySupplement: return "arrow.triangle.2.circlepath"
        case .resumeDecision: return "clock.arrow.circlepath"
        case .resumeRecovery: return "checkmark.circle"
        case .seek: return "forward.frame"
        case .seekRecovery: return "speedometer"
        case .speedBoost: return "forward.fill"
        case .playbackRecovery: return "arrow.trianglehead.2.clockwise"
        case .failed: return "exclamationmark.triangle"
        }
    }
}

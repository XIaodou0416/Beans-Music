import SwiftUI

struct PlayerPerformanceOverlayDetailAndEngineLines: View {
    let session: PlayerPerformanceSession
    let playerViewModel: PlayerStateViewModel?

    var body: some View {
        Group {
            if let detailSource = session.detailSourceMessage {
                Label(detailSource, systemImage: "doc.text.magnifyingglass")
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let diagnostics = playerViewModel?.engineDiagnostics {
                Text(diagnostics.compactDescription)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let decodeLogMessage = session.decodeLogMessage {
                Label(decodeLogMessage, systemImage: "cpu")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(decodeLogMessage.localizedCaseInsensitiveContains("success") ? .green : .orange)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

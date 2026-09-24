import SwiftUI

struct PlaybackNetworkHLSBridgeSourceRow: View {
    let snapshot: HLSBridgeSourceDiagnosticsSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("#\(snapshot.order)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                Text(snapshot.host)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                Spacer(minLength: 8)
                if snapshot.isSessionAvoided {
                    Text("避让")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Text(snapshot.averageMilliseconds.map { "\($0) ms" } ?? "-")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(PlaybackNetworkDiagnosticFormat.hlsBridgeSourceSummary(snapshot))
                .font(.caption2)
                .foregroundStyle(snapshot.isSessionAvoided || snapshot.failureCount > 0 ? .orange : .secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 3)
    }
}

import SwiftUI

struct PlaybackNetworkURLPreferenceRow: View {
    let snapshot: PlaybackURLPreferenceSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(snapshot.host)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(snapshot.averageMilliseconds) ms")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(PlaybackNetworkDiagnosticFormat.playbackURLPreferenceSummary(snapshot))
                .font(.caption2)
                .foregroundStyle(snapshot.failureCount > 0 ? .orange : .secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 3)
    }
}

import SwiftUI

struct PlayerPerformanceOverlayNetworkAndCacheLines: View {
    let session: PlayerPerformanceSession

    var body: some View {
        Group {
            if let cdnHost = session.cdnHostMessage {
                Label(cdnHost, systemImage: "network")
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let networkMessage = session.networkMessage {
                Text(networkMessage)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let hlsStartupMessage = session.hlsStartupMessage {
                Text(hlsStartupMessage)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let accessLogMessage = session.accessLogMessage {
                Text(accessLogMessage)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle((session.accessLogStallCount ?? 0) > 0 ? .orange : .secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let mediaCacheMessage = session.mediaCacheMessage {
                Text(mediaCacheMessage)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let manifestStageMessage = session.manifestStageMessage {
                Text(manifestStageMessage)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

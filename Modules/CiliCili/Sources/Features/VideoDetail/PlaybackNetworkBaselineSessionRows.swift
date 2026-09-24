import SwiftUI

struct PlaybackNetworkBaselineSessionRows: View {
    let session: PlayerPerformanceSession?

    @ViewBuilder
    var body: some View {
        if let session {
            PlaybackNetworkBaselineStartupSessionRows(session: session)
            PlaybackNetworkBaselineResumeSessionRows(session: session)
            PlaybackNetworkBaselineRuntimeSessionRows(session: session)
            PlaybackNetworkBaselineSessionMessageRows(session: session)
        } else {
            Text("等待播放性能事件")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct PlaybackNetworkOptionalMultilineRow: View {
    let title: String
    let value: String?

    @ViewBuilder
    var body: some View {
        if let value {
            PlaybackNetworkDiagnosticMultilineRow(title: title, value: value)
        }
    }
}

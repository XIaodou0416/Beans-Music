import SwiftUI

struct PlaybackNetworkBaselineResumeSessionRows: View {
    let session: PlayerPerformanceSession

    @ViewBuilder
    var body: some View {
        if let resumeApplyMilliseconds = session.resumeApplyMilliseconds {
            PlaybackNetworkDiagnosticRow(
                title: "续播 Seek",
                value: PlaybackNetworkDiagnosticFormat.formattedMilliseconds(resumeApplyMilliseconds)
            )
        }
        if session.resumeRecoveryCount > 0 {
            PlaybackNetworkDiagnosticRow(
                title: "续播验证",
                value: "\(session.resumeRecoveryCount) 次，慢 \(session.resumeRecoverySlowCount) 次"
            )
        }
        if let lastResumeRecoveryMilliseconds = session.lastResumeRecoveryMilliseconds {
            PlaybackNetworkDiagnosticRow(
                title: "续播落点",
                value: PlaybackNetworkDiagnosticFormat.formattedMilliseconds(lastResumeRecoveryMilliseconds)
            )
        }
    }
}

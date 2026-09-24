import SwiftUI

struct PlaybackNetworkBaselineRuntimeSessionRows: View {
    let session: PlayerPerformanceSession

    @ViewBuilder
    var body: some View {
        PlaybackNetworkDiagnosticRow(title: "缓冲次数", value: "\(session.bufferCount)")
        PlaybackNetworkDiagnosticRow(title: "Seek 次数", value: "\(session.seekCount)")
        if session.seekRecoveryCount > 0 {
            PlaybackNetworkDiagnosticRow(title: "Seek 恢复", value: "\(session.seekRecoveryCount) 次")
        }
        if session.speedBoostCount > 0 {
            PlaybackNetworkDiagnosticRow(
                title: "长按倍速",
                value: "\(session.speedBoostCount) 次，中断 \(session.speedBoostInterruptionCount) 次"
            )
        }
    }
}

import SwiftUI

struct PlayerPerformanceOverlayCountersRow: View {
    let session: PlayerPerformanceSession

    var body: some View {
        HStack(spacing: 8) {
            Text("缓冲 \(session.bufferCount)")
            if session.resumeRecoveryCount > 0 {
                Text("续验 \(session.resumeRecoveryCount)")
            }
            Text("Seek \(session.seekCount)")
            if session.seekRecoveryCount > 0 {
                Text("恢复 \(session.seekRecoveryCount)")
            }
            if session.playbackRecoveryCount > 0 {
                Text("播恢 \(session.playbackRecoveryCount)")
            }
            if session.speedBoostCount > 0 {
                Text("倍速 \(session.speedBoostCount)")
            }
            if session.speedBoostInterruptionCount > 0 {
                Text("中断 \(session.speedBoostInterruptionCount)")
            }
            if let quality = session.selectedQualityMessage {
                Text(quality)
                    .lineLimit(1)
            }
        }
        .font(.caption2)
        .foregroundStyle(PlayerPerformanceOverlayFormatting.counterColor(for: session))
    }
}

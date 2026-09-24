import SwiftUI

struct PlaybackNetworkBaselineSessionMessageRows: View {
    let session: PlayerPerformanceSession

    @ViewBuilder
    var body: some View {
        PlaybackNetworkOptionalMultilineRow(title: "最近 Seek", value: session.seekMessage)
        PlaybackNetworkOptionalMultilineRow(title: "最近续播验证", value: session.resumeRecoveryMessage)
        PlaybackNetworkOptionalMultilineRow(title: "最近恢复", value: session.seekRecoveryMessage)
        PlaybackNetworkOptionalMultilineRow(title: "最近播放恢复", value: session.playbackRecoveryMessage)
        PlaybackNetworkOptionalMultilineRow(title: "首帧调度", value: session.startupSchedulerMessage)
        PlaybackNetworkOptionalMultilineRow(title: "AccessLog", value: session.accessLogMessage)
        PlaybackNetworkOptionalMultilineRow(title: "最近倍速", value: session.speedBoostMessage)
        PlaybackNetworkOptionalMultilineRow(title: "质量补充", value: session.qualitySupplementMessage)
        if !session.timeline.isEmpty {
            PlaybackNetworkDiagnosticMultilineRow(
                title: "播放时间线",
                value: session.timeline.suffix(8).map(\.compactDescription).joined(separator: "\n")
            )
        }
    }
}

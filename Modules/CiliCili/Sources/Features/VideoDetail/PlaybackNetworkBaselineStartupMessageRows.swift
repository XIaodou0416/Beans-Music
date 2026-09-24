import SwiftUI

struct PlaybackNetworkBaselineStartupMessageRows: View {
    let session: PlayerPerformanceSession

    var body: some View {
        PlaybackNetworkOptionalMultilineRow(title: "播放反馈", value: session.networkMessage)
        PlaybackNetworkOptionalMultilineRow(title: "首帧分段", value: session.startupBreakdownMessage)
        PlaybackNetworkOptionalMultilineRow(title: "HLS 启动请求", value: session.hlsStartupMessage)
        PlaybackNetworkOptionalMultilineRow(title: "启动决策", value: session.startupDecisionMessage)
        PlaybackNetworkOptionalMultilineRow(title: "AccessLog", value: session.accessLogMessage)
        PlaybackNetworkOptionalMultilineRow(title: "播放恢复", value: session.playbackRecoveryMessage)
    }
}

import SwiftUI

struct PlaybackNetworkBaselineProfileRows: View {
    let profile: PlayerPlaybackAdaptationProfile

    var profileRows: some View {
        Group {
            PlaybackNetworkDiagnosticRow(title: "自适应等级", value: profile.diagnosticTitle)
            PlaybackNetworkDiagnosticRow(title: "启动清晰度上限", value: profile.startupQualityCeilingTitle)
            PlaybackNetworkDiagnosticRow(title: "后台预加载额度", value: "\(profile.backgroundPreloadLimit)")
            PlaybackNetworkDiagnosticRow(
                title: "弹幕负载",
                value: String(format: "%.0f%%", profile.danmakuLoadFactor * 100)
            )
            PlaybackNetworkDiagnosticRow(
                title: "保守视频策略",
                value: profile.prefersEnergyEfficientVideo ? "启用" : "未启用"
            )
        }
    }

    var body: some View {
        profileRows
    }
}

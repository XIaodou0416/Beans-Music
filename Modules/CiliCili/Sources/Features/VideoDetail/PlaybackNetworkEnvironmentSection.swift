import SwiftUI

struct PlaybackNetworkEnvironmentSection: View {
    let playbackAutoOptimizationTitle: String
    let environment: PlaybackEnvironment

    var body: some View {
        Section("设备网络") {
            PlaybackNetworkDiagnosticRow(title: "播放自动优化", value: playbackAutoOptimizationTitle)
            PlaybackNetworkDiagnosticRow(title: "网络类型", value: environment.networkClass.diagnosticTitle)
            PlaybackNetworkDiagnosticRow(title: "省电模式", value: environment.isLowPowerModeEnabled ? "开启" : "关闭")
            PlaybackNetworkDiagnosticRow(title: "温控限制", value: environment.isThermallyConstrained ? "已触发" : "未触发")
            PlaybackNetworkDiagnosticRow(title: "保守播放策略", value: environment.shouldPreferConservativePlayback ? "启用" : "未启用")
        }
    }
}

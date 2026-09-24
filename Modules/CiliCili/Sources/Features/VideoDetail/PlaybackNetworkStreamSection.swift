import SwiftUI

struct PlaybackNetworkStreamSection: View {
    let variant: PlayVariant?

    var body: some View {
        Section("当前流") {
            PlaybackNetworkDiagnosticRow(title: "清晰度", value: variant?.title ?? "未选择")
            PlaybackNetworkDiagnosticRow(
                title: "封装模式",
                value: PlaybackNetworkDiagnosticFormat.streamModeTitle(for: variant)
            )
            PlaybackNetworkDiagnosticRow(
                title: "编码",
                value: PlaybackNetworkDiagnosticFormat.nilIfEmpty(variant?.codec) ?? "未知"
            )
            PlaybackNetworkDiagnosticRow(
                title: "分辨率",
                value: PlaybackNetworkDiagnosticFormat.nilIfEmpty(variant?.resolution) ?? "未知"
            )
            PlaybackNetworkDiagnosticRow(
                title: "帧率",
                value: PlaybackNetworkDiagnosticFormat.frameRateTitle(for: variant)
            )
            PlaybackNetworkDiagnosticRow(
                title: "带宽",
                value: PlaybackNetworkDiagnosticFormat.bandwidthTitle(for: variant)
            )

            if let subtitle = PlaybackNetworkDiagnosticFormat.nilIfEmpty(variant?.subtitle) {
                PlaybackNetworkDiagnosticMultilineRow(title: "档位信息", value: subtitle)
            }
        }
    }
}

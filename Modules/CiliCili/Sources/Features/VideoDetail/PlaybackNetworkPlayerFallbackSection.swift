import SwiftUI

struct PlaybackNetworkPlayerFallbackSection: View {
    let fallbackMessage: String?

    var body: some View {
        Section("播放器") {
            PlaybackNetworkDiagnosticRow(title: "状态", value: "等待播放器")
            PlaybackNetworkDiagnosticRow(title: "阶段", value: "等待播放器")
            if let fallbackMessage, !fallbackMessage.isEmpty {
                PlaybackNetworkDiagnosticMultilineRow(title: "降级信息", value: fallbackMessage)
            }
        }
    }
}

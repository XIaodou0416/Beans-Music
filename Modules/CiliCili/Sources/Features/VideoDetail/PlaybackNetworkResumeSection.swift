import SwiftUI

struct PlaybackNetworkResumeSection: View {
    let diagnostics: PlaybackResumeDiagnostics

    var body: some View {
        Section("续播") {
            PlaybackNetworkDiagnosticRow(title: "来源", value: diagnostics.sourceTitle)
            PlaybackNetworkDiagnosticRow(
                title: "目标",
                value: PlaybackNetworkDiagnosticFormat.formattedResumeTime(diagnostics.targetTime)
            )
            PlaybackNetworkDiagnosticRow(title: "CID", value: diagnostics.cid.map(String.init) ?? "未确定")
            PlaybackNetworkDiagnosticRow(title: "状态", value: diagnostics.statusTitle)
            if let currentTime = diagnostics.currentTime {
                PlaybackNetworkDiagnosticRow(
                    title: "当前位置",
                    value: PlaybackNetworkDiagnosticFormat.formattedResumeTime(currentTime)
                )
            }
            PlaybackNetworkDiagnosticMultilineRow(title: "决策原因", value: diagnostics.reason)
        }
    }
}

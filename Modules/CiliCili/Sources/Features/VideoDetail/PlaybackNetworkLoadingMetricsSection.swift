import SwiftUI

struct PlaybackNetworkLoadingMetricsSection: View {
    let detailLoadElapsedMilliseconds: Int?
    let playURLElapsedMilliseconds: Int?
    let relatedElapsedMilliseconds: Int?
    let playURLSource: String?
    let didRelatedLoadTimeOut: Bool

    var body: some View {
        Section("加载耗时") {
            PlaybackNetworkDiagnosticRow(
                title: "视频详情",
                value: PlaybackNetworkDiagnosticFormat.formattedMilliseconds(detailLoadElapsedMilliseconds)
            )
            PlaybackNetworkDiagnosticRow(
                title: "播放地址",
                value: PlaybackNetworkDiagnosticFormat.formattedMilliseconds(playURLElapsedMilliseconds)
            )
            PlaybackNetworkDiagnosticRow(
                title: "相关推荐",
                value: PlaybackNetworkDiagnosticFormat.formattedMilliseconds(relatedElapsedMilliseconds)
            )
            PlaybackNetworkDiagnosticRow(
                title: "取流来源",
                value: PlaybackNetworkDiagnosticFormat.playURLSourceTitle(playURLSource)
            )

            if didRelatedLoadTimeOut {
                Label("相关推荐最近一次加载超时，已停止等待并保留主播放优先。", systemImage: "clock.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
}

import SwiftUI

struct PlaybackNetworkProbeSection: View {
    @ObservedObject var libraryStore: LibraryStore

    var body: some View {
        Section("最近测速") {
            if let snapshot = libraryStore.playbackCDNProbeSnapshotForCurrentContext {
                PlaybackNetworkDiagnosticRow(
                    title: "测速时间",
                    value: snapshot.probedAt.formatted(date: .abbreviated, time: .shortened)
                )
                PlaybackNetworkDiagnosticRow(
                    title: "有效状态",
                    value: isPlaybackCDNProbeSnapshotExpired(snapshot) ? "已过期" : "有效"
                )
                PlaybackNetworkDiagnosticRow(
                    title: "测速参考",
                    value: snapshot.recommendedPreference?.title ?? "暂无参考"
                )
                PlaybackNetworkDiagnosticRow(
                    title: "测速模式",
                    value: snapshot.isWeakReferenceOnly ? "Host 裸探测弱参考" : "真实播放 URL 优先"
                )

                if let recommendation = snapshot.recommendedPreference,
                   let result = snapshot.result(for: recommendation) {
                    PlaybackNetworkDiagnosticRow(
                        title: "参考延迟",
                        value: result.elapsedMilliseconds.map { "\($0) ms" } ?? "失败"
                    )
                }

                if snapshot.isWeakReferenceOnly {
                    Label("本次没有真实播放地址，只能判断 Host 是否有响应；403/959 是 CDN 拒绝裸探测，不代表真实播放失败。", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if !snapshot.results.isEmpty {
                    DisclosureGroup {
                        ForEach(snapshot.results.prefix(8)) { result in
                            PlaybackNetworkProbeResultRow(result: result)
                        }
                    } label: {
                        Label("测速排行", systemImage: "list.number")
                    }
                }

                if isPlaybackCDNProbeSnapshotExpired(snapshot) {
                    Label("测速结果超过 \(playbackCDNProbeRefreshIntervalTitle)，自动 CDN 可能需要重新测速。", systemImage: "clock.badge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } else {
                ContentUnavailableView(
                    "暂无 CDN 测速结果",
                    systemImage: "network.slash",
                    description: Text("进入我的页面执行一次 CDN 测速后，这里会显示推荐节点和延迟。")
                )
            }
        }
    }

}

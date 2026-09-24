import SwiftUI

struct PlaybackNetworkBaselineCacheRows: View {
    let cacheSummary: ResourceCacheSummary?

    @ViewBuilder
    var body: some View {
        if let cacheSummary {
            PlaybackNetworkDiagnosticRow(
                title: "API SWR 缓存",
                value: "\(cacheSummary.apiMemory.count) 条 · \(PlaybackNetworkDiagnosticFormat.formattedBytes(cacheSummary.apiMemory.estimatedBytes))"
            )
            PlaybackNetworkDiagnosticRow(
                title: "API 命中",
                value: "fresh \(cacheSummary.apiMemory.hits) · stale \(cacheSummary.apiMemory.staleHits) · miss \(cacheSummary.apiMemory.misses)"
            )
            PlaybackNetworkDiagnosticRow(
                title: "媒体缓存",
                value: "\(cacheSummary.progressiveMedia.entryCount) 段 · \(PlaybackNetworkDiagnosticFormat.formattedBytes(cacheSummary.progressiveMedia.estimatedBytes))"
            )
            PlaybackNetworkDiagnosticRow(
                title: "图片缓存",
                value: "\(cacheSummary.image.memoryEntryCount) 张 · \(PlaybackNetworkDiagnosticFormat.formattedBytes(cacheSummary.image.diskUsage))"
            )
        } else {
            Text("正在读取缓存基线...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

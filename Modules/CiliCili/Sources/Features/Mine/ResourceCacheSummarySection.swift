import SwiftUI

struct ResourceCacheSummarySection: View {
    let summary: ResourceCacheSummary?
    let cacheLimitSubtitle: String

    var body: some View {
        Section("统计") {
            if let summary {
                ResourceCacheSummaryRows(
                    summary: summary,
                    cacheLimitSubtitle: cacheLimitSubtitle
                )
            } else {
                ProgressView()
            }
        }
    }
}

private struct ResourceCacheSummaryRows: View {
    let summary: ResourceCacheSummary
    let cacheLimitSubtitle: String

    var body: some View {
        ResourceCacheRow(
            title: "总缓存",
            value: ResourceCacheByteFormatter.bytes(summary.managedBytes),
            subtitle: cacheLimitSubtitle
        )

        ResourceCacheRow(
            title: "PlayURL",
            value: "\(summary.playURL.count)/\(summary.playURL.capacity)",
            subtitle: "命中 \(summary.playURL.hits) · 未命中 \(summary.playURL.misses)"
        )

        ResourceCacheRow(
            title: "图片",
            value: "\(summary.image.memoryEntryCount) 张",
            subtitle: "磁盘 \(ResourceCacheByteFormatter.bytes(summary.image.diskUsage)) / \(ResourceCacheByteFormatter.bytes(summary.image.diskCapacity))"
        )

        ResourceCacheRow(
            title: "API",
            value: ResourceCacheByteFormatter.bytes(summary.api.diskUsage),
            subtitle: "内存 \(ResourceCacheByteFormatter.bytes(summary.api.memoryUsage))"
        )

        ResourceCacheRow(
            title: "视频分片",
            value: "\(summary.videoRangeMedia.entryCount) 段",
            subtitle: "\(ResourceCacheByteFormatter.bytes(summary.videoRangeMedia.estimatedBytes)) / \(ResourceCacheByteFormatter.bytes(summary.videoRangeMedia.byteCapacity))"
        )

        ResourceCacheRow(
            title: "播放小片段",
            value: "\(summary.progressiveMedia.entryCount) 段",
            subtitle: "\(ResourceCacheByteFormatter.bytes(summary.progressiveMedia.estimatedBytes)) / \(ResourceCacheByteFormatter.bytes(summary.progressiveMedia.byteCapacity))"
        )

        ResourceCacheRow(
            title: "字幕/弹幕",
            value: "\(summary.subtitlesAndDanmaku.subtitleCount + summary.subtitlesAndDanmaku.danmakuSegmentCount) 项",
            subtitle: "\(ResourceCacheByteFormatter.bytes(summary.subtitlesAndDanmaku.estimatedBytes)) / \(ResourceCacheByteFormatter.bytes(summary.subtitlesAndDanmaku.byteCapacity))"
        )
    }
}

struct ResourceCacheRow: View {
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(value)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}

enum ResourceCacheByteFormatter {
    static func bytes(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    static func megabytes(_ megabytes: Int) -> String {
        bytes(megabytes * 1024 * 1024)
    }
}

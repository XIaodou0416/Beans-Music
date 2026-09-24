import Foundation
import SwiftUI
import UIKit

struct RemoteImageDiagnosticsView: View {
    @ObservedObject var libraryStore: LibraryStore
    @State private var cacheStatistics: RemoteImageCacheStatistics?
    @State private var displayCacheStatistics: RemoteImageDisplayCacheStatistics?
    @State private var scrollStatistics: RemoteImageScrollLoadSuppressionStatistics?
    @State private var cdnStatistics: RemoteImageCDNDiagnosticsSnapshot?
    @State private var isLoading = false
    @State private var didCopy = false

    var body: some View {
        Form {
            if libraryStore.remoteImageDiagnosticsEnabled {
                cacheSection
                scrollSection
                cdnSection
                nodeSection
                degradedNodeSection
                actionsSection
            } else {
                Section {
                    Text("图片加载诊断已关闭。图片会照常加载；回到显示设置打开“记录图片加载诊断”后，新的统计会从零开始。")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .tint(libraryStore.appTintColor)
        .formStyle(.grouped)
        .nativeTopScrollEdgeEffect()
        .navigationTitle("图片加载诊断")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await reload()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading || !libraryStore.remoteImageDiagnosticsEnabled)
                .accessibilityLabel("刷新图片加载诊断")
            }
        }
        .task {
            await reload()
        }
        .onChange(of: libraryStore.remoteImageDiagnosticsEnabled) { _, isEnabled in
            if isEnabled {
                Task {
                    await reload()
                }
            } else {
                clearVisibleStatistics()
            }
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                copyDiagnostics()
            } label: {
                Label(didCopy ? "已复制" : "复制测试数据", systemImage: didCopy ? "checkmark" : "doc.on.doc")
            }
            .disabled(
                isLoading
                    || cacheStatistics == nil
                    || displayCacheStatistics == nil
                    || scrollStatistics == nil
                    || cdnStatistics == nil
            )

            Button(role: .destructive) {
                Task {
                    await resetDiagnostics()
                }
            } label: {
                Label("重置诊断数据", systemImage: "arrow.counterclockwise")
            }
            .disabled(isLoading)
        } footer: {
            Text("只统计数量和 CDN 节点名，不记录图片地址、图片内容或账号信息。重置不会清理图片缓存，也不会改变当前节点降级状态。")
        }
    }

    private var cacheSection: some View {
        Section("缓存") {
            if let cacheStatistics, let displayCacheStatistics {
                LabeledContent("显示缓存命中", value: displayCacheStatistics.hits.formatted())
                LabeledContent("显示缓存未命中", value: displayCacheStatistics.misses.formatted())
                LabeledContent("显示缓存命中率", value: cacheHitRate(hits: displayCacheStatistics.hits, misses: displayCacheStatistics.misses))
                LabeledContent("图片内存命中", value: cacheStatistics.hits.formatted())
                LabeledContent("图片内存未命中", value: cacheStatistics.misses.formatted())
                LabeledContent("图片内存命中率", value: cacheHitRate(hits: cacheStatistics.hits, misses: cacheStatistics.misses))
                LabeledContent("复用进行中加载", value: cacheStatistics.inFlightReuseCount.formatted())
                LabeledContent("新建图片加载任务", value: cacheStatistics.loadTaskCount.formatted())
                LabeledContent("内存条目", value: cacheStatistics.memoryEntryCount.formatted())
                LabeledContent("正在加载", value: cacheStatistics.inFlightCount.formatted())
                LabeledContent(
                    "磁盘占用",
                    value: "\(ResourceCacheByteFormatter.bytes(cacheStatistics.diskUsage)) / \(ResourceCacheByteFormatter.bytes(cacheStatistics.diskCapacity))"
                )
            } else {
                loadingRow
            }
        }
    }

    private var cdnSection: some View {
        Section("B站图片 CDN") {
            LabeledContent("自动切换", value: "已启用")
            if let cdnStatistics {
                LabeledContent("加载任务", value: cdnStatistics.requestCount.formatted())
                LabeledContent("成功响应", value: cdnStatistics.successCount.formatted())
                LabeledContent("瞬时失败", value: cdnStatistics.transientFailureCount.formatted())
                LabeledContent("自动切换", value: cdnStatistics.automaticSwitchCount.formatted())
            } else {
                loadingRow
            }
        }
    }

    private var scrollSection: some View {
        Section("滚动图片调度") {
            LabeledContent("快速滚动负载抑制", value: "已启用")
            if let scrollStatistics {
                LabeledContent("滚动中可见请求放行", value: scrollStatistics.visibleBypassCount.formatted())
                LabeledContent("滚动中后台预取延后", value: scrollStatistics.deferredPrefetchCount.formatted())
                LabeledContent("当前抑制滚动容器", value: scrollStatistics.activeScopeCount.formatted())
            } else {
                loadingRow
            }
        }
    }

    private var nodeSection: some View {
        Section("CDN 节点") {
            if let cdnStatistics {
                ForEach(cdnStatistics.hosts) { node in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(node.host)
                            .font(.body.monospaced())
                        Text("请求 \(node.requestCount) · 成功 \(node.successCount) · 瞬时失败 \(node.transientFailureCount)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                loadingRow
            }
        }
    }

    private var degradedNodeSection: some View {
        Section("当前降级节点") {
            if let cdnStatistics {
                if cdnStatistics.degradedHosts.isEmpty {
                    Text("无")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(cdnStatistics.degradedHosts) { node in
                        LabeledContent(
                            node.host,
                            value: "剩余 \(Int(node.remainingTime.rounded(.up))) 秒"
                        )
                    }
                }
            } else {
                loadingRow
            }
        }
    }

    private var loadingRow: some View {
        HStack {
            Text("读取中")
            Spacer(minLength: 8)
            ProgressView()
                .controlSize(.small)
        }
    }

    private func cacheHitRate(hits: Int, misses: Int) -> String {
        let total = hits + misses
        guard total > 0 else { return "-" }
        return "\(Int((Double(hits) / Double(total) * 100).rounded()))%"
    }

    @MainActor
    private func reload() async {
        guard !isLoading else { return }
        guard libraryStore.remoteImageDiagnosticsEnabled else {
            clearVisibleStatistics()
            return
        }
        isLoading = true
        displayCacheStatistics = RemoteImageDisplayMemoryCache.shared.statistics()
        cacheStatistics = await RemoteImageCache.shared.statistics()
        scrollStatistics = await RemoteImageLoadSuppressionGate.shared.statistics()
        cdnStatistics = RemoteImageCDNHealthMemory.shared.diagnostics()
        isLoading = false
    }

    @MainActor
    private func resetDiagnostics() async {
        RemoteImageDisplayMemoryCache.shared.resetDiagnostics()
        await RemoteImageCache.shared.resetDiagnostics()
        await RemoteImageLoadSuppressionGate.shared.resetDiagnostics()
        clearVisibleStatistics()
        await reload()
    }

    @MainActor
    private func copyDiagnostics() {
        guard let cacheStatistics,
              let displayCacheStatistics,
              let scrollStatistics,
              let cdnStatistics,
              libraryStore.remoteImageDiagnosticsEnabled
        else { return }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        UIPasteboard.general.string = RemoteImageDiagnosticsTextFormatter.makeText(
            cache: cacheStatistics,
            displayCache: displayCacheStatistics,
            scroll: scrollStatistics,
            cdn: cdnStatistics,
            isDiagnosticsEnabled: libraryStore.remoteImageDiagnosticsEnabled,
            version: version,
            build: build,
            generatedAt: Date.now.formatted(date: .numeric, time: .standard)
        )
        didCopy = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            didCopy = false
        }
    }

    private func clearVisibleStatistics() {
        cacheStatistics = nil
        displayCacheStatistics = nil
        scrollStatistics = nil
        cdnStatistics = nil
    }
}

nonisolated enum RemoteImageDiagnosticsTextFormatter {
    static func makeText(
        cache: RemoteImageCacheStatistics,
        displayCache: RemoteImageDisplayCacheStatistics,
        scroll: RemoteImageScrollLoadSuppressionStatistics = .empty,
        cdn: RemoteImageCDNDiagnosticsSnapshot,
        isDiagnosticsEnabled: Bool = true,
        version: String,
        build: String,
        generatedAt: String
    ) -> String {
        var lines = [
            "CiliCili 图片加载诊断",
            "generated: \(generatedAt)",
            "version: \(version) (\(build))",
            "图片加载诊断: \(isDiagnosticsEnabled ? "已开启" : "已关闭")",
            "",
            "显示内存缓存",
            "  命中: \(displayCache.hits)",
            "  未命中: \(displayCache.misses)",
            "  命中率: \(percentage(numerator: displayCache.hits, denominator: displayCache.hits + displayCache.misses))",
            "",
            "图片内存缓存",
            "  命中: \(cache.hits)",
            "  未命中: \(cache.misses)",
            "  命中率: \(percentage(numerator: cache.hits, denominator: cache.hits + cache.misses))",
            "  复用进行中加载: \(cache.inFlightReuseCount)",
            "  新建图片加载任务: \(cache.loadTaskCount)",
            "  内存条目: \(cache.memoryEntryCount)",
            "  正在加载: \(cache.inFlightCount)",
            "  磁盘占用: \(byteCount(cache.diskUsage)) / \(byteCount(cache.diskCapacity))",
            "",
            "滚动图片调度",
            "  快速滚动负载抑制: 已启用",
            "  滚动中可见请求放行: \(scroll.visibleBypassCount)",
            "  滚动中后台预取延后: \(scroll.deferredPrefetchCount)",
            "  当前抑制滚动容器: \(scroll.activeScopeCount)",
            "",
            "B站图片 CDN",
            "  自动切换: 已启用",
            "  加载任务: \(cdn.requestCount)",
            "  成功响应: \(cdn.successCount)",
            "  瞬时失败: \(cdn.transientFailureCount)",
            "  自动切换: \(cdn.automaticSwitchCount)",
            "",
            "CDN 节点"
        ]

        cdn.hosts.forEach { host in
            lines.append(
                "  \(host.host): 请求 \(host.requestCount) · 成功 \(host.successCount) · 瞬时失败 \(host.transientFailureCount) · 失败率 \(percentage(numerator: host.transientFailureCount, denominator: host.requestCount))"
            )
        }

        lines.append("")
        lines.append("当前降级节点")
        if cdn.degradedHosts.isEmpty {
            lines.append("  无")
        } else {
            cdn.degradedHosts.forEach { host in
                lines.append("  \(host.host): 剩余 \(Int(host.remainingTime.rounded(.up))) 秒")
            }
        }
        lines.append("")
        lines.append("隐私: 仅包含统计数字和 CDN 节点名，不包含图片链接、图片内容、账号或 Cookie。")
        return lines.joined(separator: "\n")
    }

    private static func percentage(numerator: Int, denominator: Int) -> String {
        guard denominator > 0 else { return "-" }
        return "\(Int((Double(numerator) / Double(denominator) * 100).rounded()))%"
    }

    private static func byteCount(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

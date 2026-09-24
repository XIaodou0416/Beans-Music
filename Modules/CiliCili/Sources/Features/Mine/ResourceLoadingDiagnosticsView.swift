import SwiftUI
import UIKit

struct ResourceLoadingDiagnosticsView: View {
    @ObservedObject var libraryStore: LibraryStore
    @State private var snapshot = ResourceLoadingDiagnosticsSnapshot.empty
    @State private var didCopy = false

    var body: some View {
        Form {
            experimentSection
            firstScreenSection
            imageSection
            requestSection
            dynamicSnapshotSection
            resumeSection
            recentEventsSection
            actionsSection
        }
        .tint(libraryStore.appTintColor)
        .formStyle(.grouped)
        .nativeTopScrollEdgeEffect()
        .hiddenInlineNavigationTitle()
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("刷新资源加载诊断")

                Button {
                    ResourceLoadingDiagnostics.shared.reset()
                    reload()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(snapshot.events.isEmpty)
                .accessibilityLabel("清空资源加载诊断")
            }
        }
        .task {
            reload()
        }
    }

    private var experimentSection: some View {
        Section {
            LabeledContent(
                "资源加载调度",
                value: "已启用"
            )
            LabeledContent(
                "已开启小功能",
                value: enabledFeatureCount.formatted() + " / 5"
            )
        } header: {
            Text("功能状态")
        } footer: {
            Text("前四项为正式功能；断点续播预热仍可独立调整。")
        }
    }

    private var firstScreenSection: some View {
        Section("首屏资源优先") {
            LabeledContent("首屏优先窗口", value: snapshot.firstScreenWindowCount.formatted())
            LabeledContent("后台预热延后", value: snapshot.backgroundPreloadDeferredCount.formatted())
            LabeledContent("平均延后", value: milliseconds(snapshot.averageBackgroundPreloadDeferredMilliseconds))
        }
    }

    private var imageSection: some View {
        Section {
            LabeledContent("进行中预取提权", value: snapshot.visibleImagePromotionCount.formatted())
        } header: {
            Text("屏幕图片提权")
        } footer: {
            Text("指原本在后台加载的图片，被屏幕中的图片请求接管优先级。")
        }
    }

    private var requestSection: some View {
        Section("重复接口合并") {
            LabeledContent("新请求", value: snapshot.readRequestOwnerCount.formatted())
            LabeledContent("复用结果", value: snapshot.readRequestSharedCount.formatted())
            LabeledContent("失败", value: snapshot.readRequestFailureCount.formatted())
            LabeledContent("平均等待", value: milliseconds(snapshot.averageReadRequestMilliseconds))
        }
    }

    private var dynamicSnapshotSection: some View {
        Section("动态页快速恢复") {
            LabeledContent("快照命中", value: snapshot.dynamicSnapshotHitCount.formatted())
            LabeledContent("快照未命中", value: snapshot.dynamicSnapshotMissCount.formatted())
            LabeledContent("快照过期", value: snapshot.dynamicSnapshotExpiredCount.formatted())
            LabeledContent("已保存", value: snapshot.dynamicSnapshotSavedCount.formatted())
            LabeledContent(
                "已保存数据量",
                value: ByteCountFormatter.string(
                    fromByteCount: Int64(snapshot.dynamicSnapshotSavedBytes),
                    countStyle: .file
                )
            )
            LabeledContent("平均缓存年龄", value: milliseconds(snapshot.averageDynamicSnapshotAgeMilliseconds))
        }
    }

    private var resumeSection: some View {
        Section("断点续播预热") {
            LabeledContent("预热完成", value: snapshot.resumeWarmupHitCount.formatted())
            LabeledContent("预热超时", value: snapshot.resumeWarmupTimeoutCount.formatted())
            LabeledContent("平均等待", value: milliseconds(snapshot.averageResumeWarmupMilliseconds))
        }
    }

    private var recentEventsSection: some View {
        Section("最近事件") {
            if snapshot.events.isEmpty {
                Text("暂无记录")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.events.suffix(20).reversed()) { event in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(event.kind.title)
                        Text(eventSummary(event))
                            .appTypography(.settingsSubtitle, fallback: .caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                UIPasteboard.general.string = ResourceLoadingDiagnosticsTextFormatter.makeText(
                    snapshot: snapshot,
                    featureStates: featureStates
                )
                didCopy = true
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    didCopy = false
                }
            } label: {
                Label(didCopy ? "已复制" : "复制测试数据", systemImage: didCopy ? "checkmark" : "doc.on.doc")
            }
        } footer: {
            Text("仅包含次数、耗时、缓存大小和功能状态，不包含链接、图片内容、账号、Cookie 或视频标题。")
        }
    }

    private var featureStates: [(String, Bool)] {
        [
            ("首屏资源优先", true),
            ("屏幕图片提权", true),
            ("重复接口合并", true),
            ("动态页快速恢复", true),
            ("断点续播预热", libraryStore.resourceLoadingResumePacketWarmupEnabled),
        ]
    }

    private var enabledFeatureCount: Int {
        featureStates.filter(\.1).count
    }

    private func reload() {
        snapshot = ResourceLoadingDiagnostics.shared.snapshot()
    }

    private func milliseconds(_ value: Int) -> String {
        value > 0 ? "\(value)ms" : "-"
    }

    private func eventSummary(_ event: ResourceLoadingDiagnosticEvent) -> String {
        let timestamp = event.timestamp.formatted(date: .omitted, time: .standard)
        let duration = event.durationMilliseconds > 0 ? " · \(event.durationMilliseconds)ms" : ""
        let details = event.detailText.isEmpty ? "" : " · \(event.detailText)"
        return "\(timestamp)\(duration)\(details)"
    }
}

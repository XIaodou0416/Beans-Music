import SwiftUI
import UIKit

struct PlayerPerformanceLogView: View {
    @EnvironmentObject private var libraryStore: LibraryStore
    @StateObject private var store = PlayerPerformanceStore.shared
    @State private var didCopy = false

    var body: some View {
        let reportableSessions = store.sessions.filter(PlayerPerformanceCopyTextFormatter.isReportableSession)
        let detailNavigationSnapshots = navigationSnapshots
        List {
            if store.events.isEmpty && store.sessions.isEmpty && detailNavigationSnapshots.isEmpty {
                ContentUnavailableView(
                    "暂无播放记录",
                    systemImage: "speedometer",
                    description: Text("播放自动优化会在后台使用这些记录调整开播画质、预加载和 CDN 复测。")
                )
            } else {
                Section("自动优化") {
                    PlayerAutoOptimizationSummaryRow(
                        profile: store.playbackAdaptationProfile(
                            isEnabled: libraryStore.isPlaybackAutoOptimizationEnabled
                        )
                    )
                }

                let sampleGroups = store.startupSampleGroups()
                if !sampleGroups.isEmpty {
                    Section("启动样本") {
                        ForEach(Array(sampleGroups.enumerated()), id: \.element.id) { index, group in
                            PlayerPerformanceSampleGroupRow(
                                group: group,
                                isRecommended: index == 0 && group.hasSufficientSamples
                            )
                        }
                    }
                }

                if !reportableSessions.isEmpty {
                    let exceptionSessions = reportableSessions.filter {
                        $0.failureMessage != nil
                            || $0.bufferCount >= 2
                            || $0.seekCount >= 12
                            || $0.resumeRecoverySlowCount > 0
                            || $0.seekRecoverySlowCount > 0
                            || ($0.accessLogStallCount ?? 0) > 0
                    }
                    if !exceptionSessions.isEmpty {
                        Section("最近异常") {
                            ForEach(exceptionSessions.prefix(5)) { session in
                                PlayerPerformanceExceptionRow(session: session)
                            }
                        }
                    }

                    Section("最近视频") {
                        ForEach(reportableSessions) { session in
                            PlayerPerformanceSessionRow(session: session)
                        }
                    }
                }

                if !detailNavigationSnapshots.isEmpty {
                    Section("详情导航时延") {
                        ForEach(Array(detailNavigationSnapshots.enumerated()), id: \.offset) { _, snapshot in
                            VideoDetailNavigationLatencySnapshotRow(snapshot: snapshot)
                        }
                    }
                }

                Section {
                    ForEach(store.events.reversed()) { event in
                        PlayerPerformanceEventRow(event: event)
                    }
                } header: {
                    Text("最近 \(store.events.count) 条")
                }
            }
        }
        .tint(libraryStore.appTintColor)
        .listStyle(.insetGrouped)
        .nativeTopScrollEdgeEffect()
        .hiddenInlineNavigationTitle()
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    UIPasteboard.general.string = [
                        store.performanceLogCopyText(),
                        VideoDetailNavigationLatencyReportFormatter.copyText(
                            detailNavigationSnapshots
                        ),
                    ]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n\n")
                    didCopy = true
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        didCopy = false
                    }
                } label: {
                    Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                }
                .disabled(isEmpty)
                .accessibilityLabel(didCopy ? "已复制性能日志" : "复制性能日志")

                Button {
                    store.clear()
                    PlaybackDetailPerformanceMonitor.shared.clear()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(isEmpty)
                .accessibilityLabel("清空性能日志")
            }
        }
    }

    private var isEmpty: Bool {
        store.events.isEmpty && store.sessions.isEmpty && navigationSnapshots.isEmpty
    }

    private var navigationSnapshots: [PlaybackDetailPerformanceSnapshot] {
        guard libraryStore.videoDetailNavigationLatencyDiagnosticsEnabled else { return [] }
        return PlaybackDetailPerformanceMonitor.shared.recentSnapshots().filter {
            $0.context.kind == .video || $0.context.kind == .pgc
        }
    }
}

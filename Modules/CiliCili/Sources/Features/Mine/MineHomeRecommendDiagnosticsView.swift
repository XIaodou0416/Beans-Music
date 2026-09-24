import SwiftUI

struct MineHomeRecommendDiagnosticsView: View {
    @EnvironmentObject private var diagnosticsStore: HomeRecommendDiagnosticsStore
    @EnvironmentObject private var libraryStore: LibraryStore
    @ObservedObject private var feedbackStore = HomeRecommendFeedbackCenter.shared
    @ObservedObject private var baselineMetricsStore = StageOneBaselineMetricsStore.shared

    private var snapshot: HomeRecommendDiagnosticsSnapshot {
        diagnosticsStore.snapshot
    }

    var body: some View {
        Form {
            Section("最近一次请求") {
                LabeledContent("状态", value: snapshot.status.title)
                LabeledContent("来源", value: snapshot.source.title)
                LabeledContent("接口", value: snapshot.endpoint.isEmpty ? "-" : snapshot.endpoint)
                LabeledContent("Profile", value: snapshot.profile.isEmpty ? "-" : snapshot.profile)
                LabeledContent("请求时间", value: Self.formattedDate(snapshot.requestStartedAt))
                LabeledContent("完成时间", value: Self.formattedDate(snapshot.responseFinishedAt))
                LabeledContent(
                    "请求耗时",
                    value: Self.formattedDuration(
                        from: snapshot.requestStartedAt,
                        to: snapshot.responseFinishedAt
                    )
                )
            }

            if !(snapshot.keyCounts ?? [:]).isEmpty {
                Section("请求计数") {
                    ForEach((snapshot.keyCounts ?? [:]).keys.sorted(), id: \.self) { key in
                        LabeledContent(key, value: String(snapshot.keyCounts?[key] ?? 0))
                    }
                }
            }

            Section("启动基线") {
                LabeledContent(
                    "首页可交互",
                    value: Self.formattedMilliseconds(
                        baselineMetricsStore.snapshot.homeFirstInteractiveMilliseconds
                    )
                )
                LabeledContent(
                    "首页首批数据",
                    value: Self.formattedMilliseconds(baselineMetricsStore.snapshot.homeFirstDataMilliseconds)
                )
                LabeledContent(
                    "动态首批数据",
                    value: Self.formattedMilliseconds(baselineMetricsStore.snapshot.dynamicFirstDataMilliseconds)
                )
                LabeledContent(
                    "启动预热开始",
                    value: Self.formattedMilliseconds(
                        baselineMetricsStore.snapshot.startupWarmupStartedMilliseconds
                    )
                )
                LabeledContent(
                    "启动预热完成",
                    value: Self.formattedMilliseconds(
                        baselineMetricsStore.snapshot.startupWarmupFinishedMilliseconds
                    )
                )
            }

            Section {
                LabeledContent(
                    "本次原始变化",
                    value: baselineMetricsStore.snapshot.networkRawChangeCount.formatted()
                )
                LabeledContent(
                    "本次刷新批次",
                    value: baselineMetricsStore.snapshot.networkRefreshBatchCount.formatted()
                )

                networkSummaryRows(
                    summary: baselineMetricsStore.history.networkSummary(
                        excludingLaunchStartedAt: baselineMetricsStore.snapshot.launchStartedAt
                    )
                )
            } header: {
                Text("网络路径稳定")
            } footer: {
                Text("历史汇总不包含本次尚未结束的启动；本次数据会在下次启动后计入。")
            }

            if snapshot.fallbackFromSource != nil || snapshot.fallbackReason != nil {
                Section("兜底") {
                    LabeledContent("原来源", value: snapshot.fallbackFromSource?.title ?? "-")
                    LabeledContent("原因", value: snapshot.fallbackReason ?? "-")
                    LabeledContent("时间", value: Self.formattedDate(snapshot.fallbackAt))
                    if let errorMessage = snapshot.fallbackErrorMessage, !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            Section("账号状态") {
                LabeledContent("身份", value: snapshot.authMode)
                LabeledContent("登录", value: Self.yesNo(snapshot.isLoggedIn))
                LabeledContent("游客推荐", value: Self.yesNo(snapshot.guestModeEnabled))
                LabeledContent("access_key", value: Self.yesNo(snapshot.hasAccessKey))
                LabeledContent("SESSDATA", value: Self.yesNo(snapshot.hasSESSDATA))
                LabeledContent("DedeUserID", value: Self.yesNo(snapshot.hasDedeUserID))
                LabeledContent("buvid", value: Self.yesNo(snapshot.hasBuvid))
                LabeledContent("buvid_fp", value: Self.yesNo(snapshot.hasBuvidFP))
                LabeledContent("缓存身份", value: snapshot.identityKey.isEmpty ? "-" : snapshot.identityKey)
                if snapshot.source == .app,
                   snapshot.isLoggedIn,
                   !snapshot.guestModeEnabled,
                   !snapshot.hasAccessKey {
                    Label("缺少移动端 access_key，App 推荐会弱于 PiliPlus/PiliPod。请优先用“App 短信验证码登录”。", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            Section("刷新游标") {
                LabeledContent("idx", value: Self.formattedInt(snapshot.requestedIndex))
                LabeledContent("nextIdx", value: Self.formattedInt(snapshot.nextIndex))
                LabeledContent("nextIdx 来源", value: snapshot.nextIndexSource ?? "-")
                LabeledContent("指纹", value: snapshot.fingerprintSource ?? "-")
                LabeledContent("会话", value: snapshot.sessionSource ?? "-")
            }

            if snapshot.appKeyHeader != nil
                || snapshot.signedAppKey != nil
                || snapshot.requestProfile != nil {
                Section("App 请求") {
                    LabeledContent("header app-key", value: snapshot.appKeyHeader ?? "-")
                    LabeledContent("signed appkey", value: snapshot.signedAppKey ?? "-")
                    LabeledContent("版本", value: snapshot.appVersion ?? "-")
                    LabeledContent("build", value: snapshot.build ?? "-")
                    LabeledContent("网络", value: snapshot.network ?? "-")
                    if let requestProfile = snapshot.requestProfile, !requestProfile.isEmpty {
                        Text(requestProfile)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            Section("返回内容") {
                LabeledContent("原始卡片", value: Self.formattedInt(snapshot.rawCount))
                LabeledContent("视频卡片", value: Self.formattedInt(snapshot.videoCardCount))
                LabeledContent("展示视频", value: Self.formattedInt(snapshot.videoCount))
                LabeledContent("直播卡片", value: Self.formattedInt(snapshot.liveCardCount))
                LabeledContent("丢弃卡片", value: Self.formattedInt(snapshot.droppedCardCount))
                LabeledContent("推荐理由", value: Self.formattedInt(snapshot.recommendReasonCount))
            }

            if let errorMessage = snapshot.errorMessage, !errorMessage.isEmpty {
                Section("错误") {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section("行为反馈") {
                LabeledContent("曝光", value: String(feedbackStore.snapshot.exposureCount))
                LabeledContent("点击", value: String(feedbackStore.snapshot.clickCount))
                LabeledContent("有效播放", value: String(feedbackStore.snapshot.playProgressCount))
                LabeledContent("更新时间", value: Self.formattedDate(feedbackStore.snapshot.updatedAt))
            }

            Section("诊断文件") {
                LabeledContent("推荐", value: HomeRecommendDiagnosticsStore.latestSnapshotURL.lastPathComponent)
                LabeledContent("反馈", value: HomeRecommendFeedbackCenter.latestSnapshotURL.lastPathComponent)
                LabeledContent("基线", value: StageOneBaselineMetricsStore.latestSnapshotURL.lastPathComponent)
                LabeledContent("历史", value: StageOneBaselineMetricsStore.historyURL.lastPathComponent)
                ShareLink(item: StageOneBaselineMetricsStore.historyURL) {
                    Label("导出性能历史", systemImage: "square.and.arrow.up")
                }
            }
        }
        .tint(libraryStore.appTintColor)
        .formStyle(.grouped)
        .nativeTopScrollEdgeEffect()
        .hiddenInlineNavigationTitle()
    }

    private static func yesNo(_ value: Bool) -> String {
        value ? "是" : "否"
    }

    private static func formattedInt(_ value: Int?) -> String {
        value.map(String.init) ?? "-"
    }

    private static func formattedDate(_ date: Date?) -> String {
        guard let date else { return "-" }
        return date.formatted(date: .numeric, time: .standard)
    }

    private static func formattedDuration(from start: Date?, to end: Date?) -> String {
        guard let start, let end else { return "-" }
        return "\(max(0, Int((end.timeIntervalSince(start) * 1_000).rounded()))) ms"
    }

    private static func formattedMilliseconds(_ value: Int?) -> String {
        value.map { "\($0) ms" } ?? "-"
    }

    @ViewBuilder
    private func networkSummaryRows(summary: StageOneNetworkSummary) -> some View {
        LabeledContent("历史样本", value: summary.sessionCount.formatted())
        LabeledContent(
            "平均变化",
            value: summary.sessionCount > 0
                ? summary.averageRawChangeCount.formatted(.number.precision(.fractionLength(1)))
                : "-"
        )
        LabeledContent(
            "平均刷新",
            value: summary.sessionCount > 0
                ? summary.averageRefreshBatchCount.formatted(.number.precision(.fractionLength(1)))
                : "-"
        )
        LabeledContent(
            "合并率",
            value: summary.coalescingRatePercent.map { "\($0)%" } ?? "-"
        )
    }
}

struct MineHomeRecommendDiagnosticsSummary {
    let snapshot: HomeRecommendDiagnosticsSnapshot

    var text: String {
        switch snapshot.status {
        case .idle:
            return "暂无刷新记录"
        case .requesting:
            return "\(snapshot.source.title) · \(snapshot.authMode) · 请求中"
        case .succeeded:
            let count = snapshot.videoCount.map { "\($0) 条" } ?? "已返回"
            let fallback = snapshot.fallbackFromSource == nil ? "" : " · 兜底"
            let accessKeyWarning = snapshot.source == .app && !snapshot.hasAccessKey ? " · 缺 access_key" : ""
            return "\(snapshot.source.title) · \(snapshot.authMode) · \(count)\(fallback)\(accessKeyWarning)"
        case .failed:
            return "\(snapshot.source.title) · \(snapshot.authMode) · 失败"
        }
    }
}

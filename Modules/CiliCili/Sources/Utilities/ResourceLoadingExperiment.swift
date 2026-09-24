import Foundation

nonisolated enum ResourceLoadingExperiment {
    enum Feature: CaseIterable {
        case resumePacketWarmup

        var storageKey: String {
            switch self {
            case .resumePacketWarmup:
                "cc.bili.resourceLoading.resumePacketWarmupExperimentEnabled.v1"
            }
        }
    }

    static let firstScreenPriorityWindow: TimeInterval = 0.95
    static let resumePacketWarmupAdditionalWait: TimeInterval = 0.10

    static func isFeatureEnabled(
        _ feature: Feature,
        in userDefaults: UserDefaults = .standard
    ) -> Bool {
        userDefaults.object(forKey: feature.storageKey) as? Bool ?? true
    }

    static func resumeWarmupWait(
        normalBudget: TimeInterval,
        userDefaults: UserDefaults = .standard
    ) -> TimeInterval {
        guard isFeatureEnabled(.resumePacketWarmup, in: userDefaults) else {
            return normalBudget
        }
        return normalBudget + resumePacketWarmupAdditionalWait
    }
}

nonisolated struct ResourceLoadingDiagnosticEvent: Identifiable, Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case firstScreenWindow
        case backgroundPreloadDeferred
        case visibleImagePromoted
        case readRequestOwner
        case readRequestShared
        case readRequestFailure
        case dynamicSnapshotHit
        case dynamicSnapshotMiss
        case dynamicSnapshotExpired
        case dynamicSnapshotSaved
        case resumeWarmupHit
        case resumeWarmupTimeout

        var title: String {
            switch self {
            case .firstScreenWindow:
                "首屏优先窗口"
            case .backgroundPreloadDeferred:
                "后台预热延后"
            case .visibleImagePromoted:
                "屏幕图片提权"
            case .readRequestOwner:
                "接口新请求"
            case .readRequestShared:
                "接口复用结果"
            case .readRequestFailure:
                "合并接口失败"
            case .dynamicSnapshotHit:
                "动态快照命中"
            case .dynamicSnapshotMiss:
                "动态快照未命中"
            case .dynamicSnapshotExpired:
                "动态快照过期"
            case .dynamicSnapshotSaved:
                "动态快照已保存"
            case .resumeWarmupHit:
                "续播预热完成"
            case .resumeWarmupTimeout:
                "续播预热超时"
            }
        }
    }

    let id: UUID
    let timestamp: Date
    let kind: Kind
    let durationMilliseconds: Int
    let details: [String: String]

    var detailText: String {
        details
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
    }
}

nonisolated struct ResourceLoadingDiagnosticsSnapshot: Equatable, Sendable {
    var firstScreenWindowCount = 0
    var backgroundPreloadDeferredCount = 0
    var totalBackgroundPreloadDeferredMilliseconds = 0
    var visibleImagePromotionCount = 0
    var readRequestOwnerCount = 0
    var readRequestSharedCount = 0
    var readRequestFailureCount = 0
    var totalReadRequestMilliseconds = 0
    var dynamicSnapshotHitCount = 0
    var dynamicSnapshotMissCount = 0
    var dynamicSnapshotExpiredCount = 0
    var dynamicSnapshotSavedCount = 0
    var dynamicSnapshotSavedBytes = 0
    var totalDynamicSnapshotAgeMilliseconds = 0
    var resumeWarmupHitCount = 0
    var resumeWarmupTimeoutCount = 0
    var totalResumeWarmupMilliseconds = 0
    var events: [ResourceLoadingDiagnosticEvent] = []

    static let empty = Self()

    var averageBackgroundPreloadDeferredMilliseconds: Int {
        average(
            totalBackgroundPreloadDeferredMilliseconds,
            count: backgroundPreloadDeferredCount
        )
    }

    var averageReadRequestMilliseconds: Int {
        average(totalReadRequestMilliseconds, count: readRequestOwnerCount + readRequestSharedCount)
    }

    var averageDynamicSnapshotAgeMilliseconds: Int {
        average(totalDynamicSnapshotAgeMilliseconds, count: dynamicSnapshotHitCount)
    }

    var averageResumeWarmupMilliseconds: Int {
        average(totalResumeWarmupMilliseconds, count: resumeWarmupHitCount + resumeWarmupTimeoutCount)
    }

    private func average(_ total: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return total / count
    }
}

nonisolated final class ResourceLoadingDiagnostics: @unchecked Sendable {
    static let shared = ResourceLoadingDiagnostics()

    private let lock = NSLock()
    private let maximumEventCount: Int
    private let shouldRecord: @Sendable () -> Bool
    private var storedSnapshot = ResourceLoadingDiagnosticsSnapshot.empty

    init(
        maximumEventCount: Int = 60,
        shouldRecord: @escaping @Sendable () -> Bool = { true }
    ) {
        self.maximumEventCount = max(maximumEventCount, 1)
        self.shouldRecord = shouldRecord
    }

    func record(
        _ kind: ResourceLoadingDiagnosticEvent.Kind,
        durationMilliseconds: Int = 0,
        value: Int = 0,
        details: [String: String] = [:]
    ) {
        guard shouldRecord() else { return }
        let durationMilliseconds = max(durationMilliseconds, 0)
        let event = ResourceLoadingDiagnosticEvent(
            id: UUID(),
            timestamp: Date(),
            kind: kind,
            durationMilliseconds: durationMilliseconds,
            details: details
        )

        lock.withLock {
            switch kind {
            case .firstScreenWindow:
                storedSnapshot.firstScreenWindowCount += 1
            case .backgroundPreloadDeferred:
                storedSnapshot.backgroundPreloadDeferredCount += 1
                storedSnapshot.totalBackgroundPreloadDeferredMilliseconds += durationMilliseconds
            case .visibleImagePromoted:
                storedSnapshot.visibleImagePromotionCount += 1
            case .readRequestOwner:
                storedSnapshot.readRequestOwnerCount += 1
                storedSnapshot.totalReadRequestMilliseconds += durationMilliseconds
            case .readRequestShared:
                storedSnapshot.readRequestSharedCount += 1
                storedSnapshot.totalReadRequestMilliseconds += durationMilliseconds
            case .readRequestFailure:
                storedSnapshot.readRequestFailureCount += 1
            case .dynamicSnapshotHit:
                storedSnapshot.dynamicSnapshotHitCount += 1
                storedSnapshot.totalDynamicSnapshotAgeMilliseconds += durationMilliseconds
            case .dynamicSnapshotMiss:
                storedSnapshot.dynamicSnapshotMissCount += 1
            case .dynamicSnapshotExpired:
                storedSnapshot.dynamicSnapshotExpiredCount += 1
            case .dynamicSnapshotSaved:
                storedSnapshot.dynamicSnapshotSavedCount += 1
                storedSnapshot.dynamicSnapshotSavedBytes += max(value, 0)
            case .resumeWarmupHit:
                storedSnapshot.resumeWarmupHitCount += 1
                storedSnapshot.totalResumeWarmupMilliseconds += durationMilliseconds
            case .resumeWarmupTimeout:
                storedSnapshot.resumeWarmupTimeoutCount += 1
                storedSnapshot.totalResumeWarmupMilliseconds += durationMilliseconds
            }
            storedSnapshot.events.append(event)
            if storedSnapshot.events.count > maximumEventCount {
                storedSnapshot.events.removeFirst(storedSnapshot.events.count - maximumEventCount)
            }
        }
    }

    func snapshot() -> ResourceLoadingDiagnosticsSnapshot {
        lock.withLock { storedSnapshot }
    }

    func reset() {
        lock.withLock {
            storedSnapshot = .empty
        }
    }
}

nonisolated enum ResourceLoadingDiagnosticsTextFormatter {
    static func makeText(
        snapshot: ResourceLoadingDiagnosticsSnapshot,
        featureStates: [(String, Bool)]
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        let featureText =
            featureStates
            .map { "\($0.0)=\($0.1 ? "on" : "off")" }
            .joined(separator: " ")

        var lines = [
            "CiliCili 资源加载诊断",
            "generated: \(formatter.string(from: Date()))",
            "version: \(version) (\(build))",
            "资源加载调度: 已启用",
            "小功能: \(featureText)",
            "",
            "首屏资源优先",
            "  首屏优先窗口: \(snapshot.firstScreenWindowCount)",
            "  后台预热延后: \(snapshot.backgroundPreloadDeferredCount) · 平均 \(snapshot.averageBackgroundPreloadDeferredMilliseconds)ms",
            "",
            "屏幕图片提权",
            "  进行中预取提权: \(snapshot.visibleImagePromotionCount)",
            "",
            "重复接口合并",
            "  新请求: \(snapshot.readRequestOwnerCount)",
            "  复用结果: \(snapshot.readRequestSharedCount)",
            "  失败: \(snapshot.readRequestFailureCount)",
            "  平均等待: \(snapshot.averageReadRequestMilliseconds)ms",
            "",
            "动态页快速恢复",
            "  快照命中: \(snapshot.dynamicSnapshotHitCount) · 平均缓存年龄 \(snapshot.averageDynamicSnapshotAgeMilliseconds)ms",
            "  未命中: \(snapshot.dynamicSnapshotMissCount) · 过期: \(snapshot.dynamicSnapshotExpiredCount)",
            "  已保存: \(snapshot.dynamicSnapshotSavedCount) · 数据量: \(ByteCountFormatter.string(fromByteCount: Int64(snapshot.dynamicSnapshotSavedBytes), countStyle: .file))",
            "",
            "断点续播预热",
            "  完成: \(snapshot.resumeWarmupHitCount) · 超时: \(snapshot.resumeWarmupTimeoutCount) · 平均 \(snapshot.averageResumeWarmupMilliseconds)ms",
            "",
            "最近事件",
        ]

        if snapshot.events.isEmpty {
            lines.append("  暂无记录")
        } else {
            for event in snapshot.events.suffix(40).reversed() {
                let detailSuffix = event.detailText.isEmpty ? "" : " · \(event.detailText)"
                let durationSuffix = event.durationMilliseconds > 0 ? " · \(event.durationMilliseconds)ms" : ""
                lines.append(
                    "  \(formatter.string(from: event.timestamp)) · \(event.kind.title)\(durationSuffix)\(detailSuffix)"
                )
            }
        }

        lines.append("")
        lines.append("隐私: 仅包含次数、耗时、缓存大小和功能状态，不包含链接、图片内容、账号、Cookie 或视频标题。")
        return lines.joined(separator: "\n")
    }
}

nonisolated enum ResourceLoadingForegroundScope: String, Sendable {
    case home
    case dynamic
}

actor ResourceLoadingForegroundPriorityGate {
    static let shared = ResourceLoadingForegroundPriorityGate()

    private var foregroundUntilByScope: [ResourceLoadingForegroundScope: Date] = [:]

    func beginFirstScreenPriorityWindow(
        for scope: ResourceLoadingForegroundScope,
        duration: TimeInterval = ResourceLoadingExperiment.firstScreenPriorityWindow
    ) {
        let deadline = Date().addingTimeInterval(max(duration, 0))
        if let existing = foregroundUntilByScope[scope], existing > deadline {
            return
        }
        foregroundUntilByScope[scope] = deadline
        ResourceLoadingDiagnostics.shared.record(
            .firstScreenWindow,
            durationMilliseconds: Int((max(duration, 0) * 1_000).rounded()),
            details: ["scope": scope.rawValue]
        )
    }

    func backgroundDelayNanoseconds(for scope: ResourceLoadingForegroundScope) -> UInt64 {
        let now = Date()
        guard let deadline = foregroundUntilByScope[scope], deadline > now else {
            foregroundUntilByScope[scope] = nil
            return 0
        }
        let delay = deadline.timeIntervalSince(now)
        ResourceLoadingDiagnostics.shared.record(
            .backgroundPreloadDeferred,
            durationMilliseconds: Int((delay * 1_000).rounded()),
            details: ["scope": scope.rawValue]
        )
        return UInt64((delay * 1_000_000_000).rounded(.up))
    }
}

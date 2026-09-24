import Combine
import Foundation

nonisolated struct StageOneBaselineSnapshot: Codable, Equatable, Sendable {
    let launchStartedAt: Date
    var homeFirstInteractiveMilliseconds: Int?
    var homeFirstDataMilliseconds: Int?
    var dynamicFirstDataMilliseconds: Int?
    var startupWarmupStartedMilliseconds: Int?
    var startupWarmupFinishedMilliseconds: Int?
    var networkRawChangeCount: Int
    var networkRefreshBatchCount: Int

    init(launchStartedAt: Date) {
        self.launchStartedAt = launchStartedAt
        homeFirstInteractiveMilliseconds = nil
        homeFirstDataMilliseconds = nil
        dynamicFirstDataMilliseconds = nil
        startupWarmupStartedMilliseconds = nil
        startupWarmupFinishedMilliseconds = nil
        networkRawChangeCount = 0
        networkRefreshBatchCount = 0
    }

    private enum CodingKeys: String, CodingKey {
        case launchStartedAt
        case homeFirstInteractiveMilliseconds
        case homeFirstDataMilliseconds
        case dynamicFirstDataMilliseconds
        case startupWarmupStartedMilliseconds
        case startupWarmupFinishedMilliseconds
        case deferredWarmupStartedMilliseconds
        case deferredWarmupFinishedMilliseconds
        case networkRawChangeCount
        case networkRefreshBatchCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        launchStartedAt = try container.decode(Date.self, forKey: .launchStartedAt)
        homeFirstInteractiveMilliseconds = try container.decodeIfPresent(
            Int.self,
            forKey: .homeFirstInteractiveMilliseconds
        )
        homeFirstDataMilliseconds = try container.decodeIfPresent(Int.self, forKey: .homeFirstDataMilliseconds)
        dynamicFirstDataMilliseconds = try container.decodeIfPresent(Int.self, forKey: .dynamicFirstDataMilliseconds)
        startupWarmupStartedMilliseconds = try container.decodeIfPresent(
            Int.self,
            forKey: .startupWarmupStartedMilliseconds
        ) ?? container.decodeIfPresent(Int.self, forKey: .deferredWarmupStartedMilliseconds)
        startupWarmupFinishedMilliseconds = try container.decodeIfPresent(
            Int.self,
            forKey: .startupWarmupFinishedMilliseconds
        ) ?? container.decodeIfPresent(Int.self, forKey: .deferredWarmupFinishedMilliseconds)
        networkRawChangeCount = try container.decodeIfPresent(Int.self, forKey: .networkRawChangeCount) ?? 0
        networkRefreshBatchCount = try container.decodeIfPresent(Int.self, forKey: .networkRefreshBatchCount) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(launchStartedAt, forKey: .launchStartedAt)
        try container.encodeIfPresent(homeFirstInteractiveMilliseconds, forKey: .homeFirstInteractiveMilliseconds)
        try container.encodeIfPresent(homeFirstDataMilliseconds, forKey: .homeFirstDataMilliseconds)
        try container.encodeIfPresent(dynamicFirstDataMilliseconds, forKey: .dynamicFirstDataMilliseconds)
        try container.encodeIfPresent(startupWarmupStartedMilliseconds, forKey: .startupWarmupStartedMilliseconds)
        try container.encodeIfPresent(startupWarmupFinishedMilliseconds, forKey: .startupWarmupFinishedMilliseconds)
        try container.encode(networkRawChangeCount, forKey: .networkRawChangeCount)
        try container.encode(networkRefreshBatchCount, forKey: .networkRefreshBatchCount)
    }

    mutating func markHomeFirstInteractive(elapsedMilliseconds: Int) {
        homeFirstInteractiveMilliseconds = homeFirstInteractiveMilliseconds ?? elapsedMilliseconds
    }

    mutating func markHomeFirstData(elapsedMilliseconds: Int) {
        homeFirstDataMilliseconds = homeFirstDataMilliseconds ?? elapsedMilliseconds
    }

    mutating func markDynamicFirstData(elapsedMilliseconds: Int) {
        dynamicFirstDataMilliseconds = dynamicFirstDataMilliseconds ?? elapsedMilliseconds
    }

    mutating func markStartupWarmupStarted(elapsedMilliseconds: Int) {
        startupWarmupStartedMilliseconds = startupWarmupStartedMilliseconds ?? elapsedMilliseconds
    }

    mutating func markStartupWarmupFinished(elapsedMilliseconds: Int) {
        startupWarmupFinishedMilliseconds = startupWarmupFinishedMilliseconds ?? elapsedMilliseconds
    }

    mutating func recordNetworkRawChange() {
        networkRawChangeCount += 1
    }

    mutating func recordNetworkRefreshBatch() {
        networkRefreshBatchCount += 1
    }
}

nonisolated struct StageOneBaselineHistory: Codable, Equatable, Sendable {
    static let capacity = 20

    private(set) var snapshots: [StageOneBaselineSnapshot]

    init(snapshots: [StageOneBaselineSnapshot] = []) {
        self.snapshots = Array(snapshots.suffix(Self.capacity))
    }

    mutating func upsert(_ snapshot: StageOneBaselineSnapshot) {
        if let index = snapshots.firstIndex(where: { $0.launchStartedAt == snapshot.launchStartedAt }) {
            snapshots[index] = snapshot
        } else {
            snapshots.append(snapshot)
        }
        snapshots = Array(snapshots.suffix(Self.capacity))
    }

    func networkSummary(excludingLaunchStartedAt: Date? = nil) -> StageOneNetworkSummary {
        StageOneNetworkSummary(
            snapshots: snapshots.filter {
                $0.launchStartedAt != excludingLaunchStartedAt
            }
        )
    }

    static func decode(historyData: Data?, legacyLatestData: Data?) -> Self {
        let decoder = JSONDecoder()
        if let historyData,
           let history = try? decoder.decode(Self.self, from: historyData) {
            return history
        }
        if let historyData,
           let snapshots = try? decoder.decode([StageOneBaselineSnapshot].self, from: historyData) {
            return Self(snapshots: snapshots)
        }
        if let legacyLatestData,
           let snapshot = try? decoder.decode(StageOneBaselineSnapshot.self, from: legacyLatestData) {
            return Self(snapshots: [snapshot])
        }
        return Self()
    }
}

nonisolated struct StageOneNetworkSummary: Equatable, Sendable {
    let sessionCount: Int
    let rawChangeCount: Int
    let refreshBatchCount: Int

    init(snapshots: [StageOneBaselineSnapshot]) {
        sessionCount = snapshots.count
        rawChangeCount = snapshots.reduce(0) { $0 + $1.networkRawChangeCount }
        refreshBatchCount = snapshots.reduce(0) { $0 + $1.networkRefreshBatchCount }
    }

    var averageRawChangeCount: Double {
        guard sessionCount > 0 else { return 0 }
        return Double(rawChangeCount) / Double(sessionCount)
    }

    var averageRefreshBatchCount: Double {
        guard sessionCount > 0 else { return 0 }
        return Double(refreshBatchCount) / Double(sessionCount)
    }

    var coalescingRatePercent: Int? {
        guard rawChangeCount > 0 else { return nil }
        let savedRefreshCount = max(0, rawChangeCount - refreshBatchCount)
        return Int((Double(savedRefreshCount) / Double(rawChangeCount) * 100).rounded())
    }
}

@MainActor
final class StageOneBaselineMetricsStore: ObservableObject {
    static let shared = StageOneBaselineMetricsStore()
    private static let legacyDirectoryURL = URL.cachesDirectory
        .appending(path: "StageOneBaseline", directoryHint: .isDirectory)
    private static let historyDirectoryURL = URL.applicationSupportDirectory
        .appending(path: "StageOneBaseline", directoryHint: .isDirectory)
    static let latestSnapshotURL = legacyDirectoryURL
        .appending(path: "latest.json")
    static let historyURL = historyDirectoryURL
        .appending(path: "history.json")

    @Published private(set) var snapshot: StageOneBaselineSnapshot
    @Published private(set) var history: StageOneBaselineHistory
    private var launchStartedUptime: TimeInterval

    private init() {
        launchStartedUptime = ProcessInfo.processInfo.systemUptime
        let storedHistory = StageOneBaselineHistory.decode(
            historyData: try? Data(contentsOf: Self.historyURL),
            legacyLatestData: try? Data(contentsOf: Self.latestSnapshotURL)
        )
        history = storedHistory
        snapshot = storedHistory.snapshots.last ?? StageOneBaselineSnapshot(launchStartedAt: Date())
    }

    func beginLaunch() {
        launchStartedUptime = ProcessInfo.processInfo.systemUptime
        snapshot = StageOneBaselineSnapshot(launchStartedAt: Date())
        persist()
    }

    func markHomeFirstInteractive() {
        guard snapshot.homeFirstInteractiveMilliseconds == nil else { return }
        snapshot.markHomeFirstInteractive(elapsedMilliseconds: elapsedMilliseconds())
        persist()
    }

    func markHomeFirstData() {
        guard snapshot.homeFirstDataMilliseconds == nil else { return }
        snapshot.markHomeFirstData(elapsedMilliseconds: elapsedMilliseconds())
        persist()
    }

    func markDynamicFirstData() {
        guard snapshot.dynamicFirstDataMilliseconds == nil else { return }
        snapshot.markDynamicFirstData(elapsedMilliseconds: elapsedMilliseconds())
        persist()
    }

    func markStartupWarmupStarted() {
        guard snapshot.startupWarmupStartedMilliseconds == nil else { return }
        snapshot.markStartupWarmupStarted(elapsedMilliseconds: elapsedMilliseconds())
        persist()
    }

    func markStartupWarmupFinished() {
        guard snapshot.startupWarmupFinishedMilliseconds == nil else { return }
        snapshot.markStartupWarmupFinished(elapsedMilliseconds: elapsedMilliseconds())
        persist()
    }

    func recordNetworkRawChange() {
        snapshot.recordNetworkRawChange()
        persist()
    }

    func recordNetworkRefreshBatch() {
        snapshot.recordNetworkRefreshBatch()
        persist()
    }

    private func elapsedMilliseconds() -> Int {
        max(0, Int(((ProcessInfo.processInfo.systemUptime - launchStartedUptime) * 1_000).rounded()))
    }

    private func persist() {
        do {
            history.upsert(snapshot)
            try FileManager.default.createDirectory(
                at: Self.legacyDirectoryURL,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: Self.historyDirectoryURL,
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(snapshot).write(to: Self.latestSnapshotURL, options: .atomic)
            try encoder.encode(history).write(to: Self.historyURL, options: .atomic)
        } catch {
            return
        }
    }
}

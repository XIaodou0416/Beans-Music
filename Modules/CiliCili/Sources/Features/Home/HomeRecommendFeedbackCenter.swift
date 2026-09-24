import Foundation
import Combine

@MainActor
final class HomeRecommendFeedbackCenter: ObservableObject {
    static let shared = HomeRecommendFeedbackCenter()

    @Published private(set) var snapshot: HomeRecommendFeedbackSnapshot

    private static let directoryURL = URL.cachesDirectory.appending(
        path: "HomeRecommendFeedback",
        directoryHint: .isDirectory
    )
    static let latestSnapshotURL = directoryURL.appending(path: "latest.json")

    private let maxEventCount = 240
    private let exposureDedupeWindow: TimeInterval = 8 * 60
    private let clickPlaybackWindow: TimeInterval = 2 * 60 * 60
    private var recentExposureTimes: [String: Date] = [:]
    private var recentHomeClickTimes: [String: Date] = [:]
    private var recentPlayProgressTimes: [String: Date] = [:]

    private init() {
        if let persistedSnapshot = Self.loadPersistedSnapshot() {
            snapshot = persistedSnapshot
        } else {
            snapshot = .empty
            persist()
        }
        let now = Date()
        recentExposureTimes = snapshot.events.reduce(into: [String: Date]()) { result, event in
            guard event.kind == .exposure else { return }
            result[event.bvid] = max(result[event.bvid] ?? .distantPast, event.occurredAt)
        }
        recentHomeClickTimes = snapshot.events.reduce(into: [String: Date]()) { result, event in
            guard event.kind == .click,
                  now.timeIntervalSince(event.occurredAt) < clickPlaybackWindow else { return }
            result[event.bvid] = max(result[event.bvid] ?? .distantPast, event.occurredAt)
        }
        recentPlayProgressTimes = snapshot.events.reduce(into: [String: Date]()) { result, event in
            guard event.kind == .playProgress,
                  now.timeIntervalSince(event.occurredAt) < clickPlaybackWindow else { return }
            result[event.bvid] = max(result[event.bvid] ?? .distantPast, event.occurredAt)
        }
    }

    func recordExposure(
        video: VideoItem,
        index: Int,
        source: HomeRecommendFeedSourcePreference
    ) {
        let now = Date()
        if let last = recentExposureTimes[video.bvid],
           now.timeIntervalSince(last) < exposureDedupeWindow {
            return
        }
        recentExposureTimes[video.bvid] = now
        append(
            .init(
                kind: .exposure,
                source: source,
                video: video,
                index: index,
                occurredAt: now
            )
        )
    }

    func recordClick(
        video: VideoItem,
        source: HomeRecommendFeedSourcePreference
    ) {
        let now = Date()
        recentHomeClickTimes[video.bvid] = now
        recentPlayProgressTimes[video.bvid] = nil
        append(
            .init(
                kind: .click,
                source: source,
                video: video,
                index: nil,
                occurredAt: now
            )
        )
    }

    func recordPlayProgress(
        video: VideoItem,
        progress: TimeInterval,
        duration: TimeInterval?
    ) {
        guard progress.isFinite, progress >= 5 else { return }
        let now = Date()
        guard let clickedAt = recentHomeClickTimes[video.bvid],
              now.timeIntervalSince(clickedAt) < clickPlaybackWindow else {
            return
        }
        if let lastProgressAt = recentPlayProgressTimes[video.bvid],
           lastProgressAt >= clickedAt {
            return
        }
        recentPlayProgressTimes[video.bvid] = now
        append(
            .init(
                kind: .playProgress,
                source: nil,
                video: video,
                index: nil,
                occurredAt: now,
                progress: progress,
                duration: duration
            )
        )
    }

    func reset() {
        recentExposureTimes.removeAll()
        recentHomeClickTimes.removeAll()
        recentPlayProgressTimes.removeAll()
        snapshot = .empty
        persist()
    }

    private func append(_ event: HomeRecommendFeedbackEvent) {
        var events = snapshot.events
        events.append(event)
        events = Array(events.suffix(maxEventCount))
        snapshot = HomeRecommendFeedbackSnapshot(updatedAt: Date(), events: events)
        persist()
    }

    private func persist() {
        do {
            let fileManager = FileManager.default
            try fileManager.createDirectory(at: Self.directoryURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: Self.latestSnapshotURL, options: [.atomic])
        } catch {
            return
        }
    }

    private static func loadPersistedSnapshot() -> HomeRecommendFeedbackSnapshot? {
        guard let data = try? Data(contentsOf: latestSnapshotURL) else { return nil }
        return try? JSONDecoder().decode(HomeRecommendFeedbackSnapshot.self, from: data)
    }
}

nonisolated enum HomeRecommendFeedbackKind: String, Codable, Sendable {
    case exposure
    case click
    case playProgress
}

nonisolated struct HomeRecommendFeedbackSnapshot: Codable, Equatable, Sendable {
    let updatedAt: Date?
    let events: [HomeRecommendFeedbackEvent]

    static let empty = HomeRecommendFeedbackSnapshot(updatedAt: nil, events: [])

    var exposureCount: Int {
        events.filter { $0.kind == .exposure }.count
    }

    var clickCount: Int {
        events.filter { $0.kind == .click }.count
    }

    var playProgressCount: Int {
        events.filter { $0.kind == .playProgress }.count
    }
}

nonisolated struct HomeRecommendFeedbackEvent: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let kind: HomeRecommendFeedbackKind
    let source: HomeRecommendFeedSourcePreference?
    let bvid: String
    let aid: Int?
    let title: String
    let index: Int?
    let occurredAt: Date
    let progress: TimeInterval?
    let duration: TimeInterval?

    init(
        kind: HomeRecommendFeedbackKind,
        source: HomeRecommendFeedSourcePreference?,
        video: VideoItem,
        index: Int?,
        occurredAt: Date,
        progress: TimeInterval? = nil,
        duration: TimeInterval? = nil
    ) {
        id = UUID()
        self.kind = kind
        self.source = source
        bvid = video.bvid
        aid = video.aid
        title = video.title
        self.index = index
        self.occurredAt = occurredAt
        self.progress = progress
        self.duration = duration
    }
}

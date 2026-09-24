import Foundation
import Combine

@MainActor
final class HomeRecommendDiagnosticsStore: ObservableObject {
    static let shared = HomeRecommendDiagnosticsStore()

    @Published private(set) var snapshot: HomeRecommendDiagnosticsSnapshot

    private static let directoryURL = URL.cachesDirectory.appending(
        path: "HomeRecommendDiagnostics",
        directoryHint: .isDirectory
    )
    static let latestSnapshotURL = directoryURL.appending(path: "latest.json")

    private init() {
        if let persistedSnapshot = Self.loadPersistedSnapshot() {
            snapshot = persistedSnapshot
        } else {
            snapshot = .empty
            persist()
        }
    }

    func recordRequest(_ update: HomeRecommendDiagnosticsSnapshot) {
        var updated = update
        updated.keyCounts = HomeRecommendDiagnosticsCounterPolicy.recordingRequest(
            previous: snapshot.keyCounts
        )
        snapshot = updated
        persist()
    }

    func recordResponse(
        status: HomeRecommendDiagnosticsStatus,
        nextIndex: Int?,
        nextIndexSource: String?,
        rawCount: Int?,
        videoCardCount: Int?,
        videoCount: Int?,
        liveCardCount: Int?,
        droppedCardCount: Int?,
        recommendReasonCount: Int?,
        errorMessage: String? = nil,
        requestID: UUID? = nil
    ) {
        guard HomeRecommendDiagnosticsRequestPolicy.acceptsResponse(
            currentRequestID: snapshot.requestID,
            responseRequestID: requestID
        ) else { return }
        var updated = snapshot.response(
            status: status,
            nextIndex: nextIndex,
            nextIndexSource: nextIndexSource,
            rawCount: rawCount,
            videoCardCount: videoCardCount,
            videoCount: videoCount,
            liveCardCount: liveCardCount,
            droppedCardCount: droppedCardCount,
            recommendReasonCount: recommendReasonCount,
            errorMessage: errorMessage
        )
        updated.keyCounts = HomeRecommendDiagnosticsCounterPolicy.recordingResponse(
            previous: updated.keyCounts,
            status: status
        )
        snapshot = updated
        persist()
    }

    func reset() {
        snapshot = .empty
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

    private static func loadPersistedSnapshot() -> HomeRecommendDiagnosticsSnapshot? {
        guard let data = try? Data(contentsOf: latestSnapshotURL) else { return nil }
        return try? JSONDecoder().decode(HomeRecommendDiagnosticsSnapshot.self, from: data)
    }
}

nonisolated enum HomeRecommendDiagnosticsStatus: String, Codable, Sendable {
    case idle
    case requesting
    case succeeded
    case failed

    var title: String {
        switch self {
        case .idle:
            return "暂无"
        case .requesting:
            return "请求中"
        case .succeeded:
            return "成功"
        case .failed:
            return "失败"
        }
    }
}

nonisolated struct HomeRecommendDiagnosticsSnapshot: Codable, Equatable, Sendable {
    var status: HomeRecommendDiagnosticsStatus
    var source: HomeRecommendFeedSourcePreference
    var fallbackFromSource: HomeRecommendFeedSourcePreference? = nil
    var fallbackReason: String? = nil
    var fallbackErrorMessage: String? = nil
    var fallbackAt: Date? = nil
    var endpoint: String
    var profile: String
    var authMode: String
    var isLoggedIn: Bool
    var guestModeEnabled: Bool
    var hasAccessKey: Bool
    var hasSESSDATA: Bool
    var hasDedeUserID: Bool
    var hasBuvid: Bool
    var hasBuvidFP: Bool
    var identityKey: String
    var requestedIndex: Int?
    var nextIndex: Int?
    var nextIndexSource: String?
    var fingerprintSource: String?
    var sessionSource: String?
    var appKeyHeader: String? = nil
    var signedAppKey: String? = nil
    var appVersion: String? = nil
    var build: String? = nil
    var network: String? = nil
    var requestProfile: String? = nil
    var requestStartedAt: Date?
    var responseFinishedAt: Date?
    var rawCount: Int?
    var videoCardCount: Int?
    var videoCount: Int?
    var liveCardCount: Int?
    var droppedCardCount: Int?
    var recommendReasonCount: Int?
    var errorMessage: String?

    var keyCounts: [String: Int]? = nil
    var requestID: UUID? = nil

    static let empty = HomeRecommendDiagnosticsSnapshot(
        status: .idle,
        source: .app,
        fallbackFromSource: nil,
        fallbackReason: nil,
        fallbackErrorMessage: nil,
        fallbackAt: nil,
        endpoint: "",
        profile: "",
        authMode: "unknown",
        isLoggedIn: false,
        guestModeEnabled: false,
        hasAccessKey: false,
        hasSESSDATA: false,
        hasDedeUserID: false,
        hasBuvid: false,
        hasBuvidFP: false,
        identityKey: "",
        requestedIndex: nil,
        nextIndex: nil,
        nextIndexSource: nil,
        fingerprintSource: nil,
        sessionSource: nil,
        appKeyHeader: nil,
        signedAppKey: nil,
        appVersion: nil,
        build: nil,
        network: nil,
        requestProfile: nil,
        requestStartedAt: nil,
        responseFinishedAt: nil,
        rawCount: nil,
        videoCardCount: nil,
        videoCount: nil,
        liveCardCount: nil,
        droppedCardCount: nil,
        recommendReasonCount: nil,
        errorMessage: nil
    )

    func response(
        status: HomeRecommendDiagnosticsStatus,
        nextIndex: Int?,
        nextIndexSource: String?,
        rawCount: Int?,
        videoCardCount: Int?,
        videoCount: Int?,
        liveCardCount: Int?,
        droppedCardCount: Int?,
        recommendReasonCount: Int?,
        errorMessage: String?,
        finishedAt: Date = Date()
    ) -> Self {
        var copy = self
        copy.status = status
        copy.responseFinishedAt = finishedAt
        copy.nextIndex = nextIndex
        copy.nextIndexSource = nextIndexSource
        copy.rawCount = rawCount
        copy.videoCardCount = videoCardCount
        copy.videoCount = videoCount
        copy.liveCardCount = liveCardCount
        copy.droppedCardCount = droppedCardCount
        copy.recommendReasonCount = recommendReasonCount
        copy.errorMessage = errorMessage
        return copy
    }
}

nonisolated enum HomeRecommendDiagnosticsCounterPolicy {
    static func recordingRequest(previous: [String: Int]?) -> [String: Int] {
        incrementing("request_count", in: previous)
    }

    static func recordingResponse(
        previous: [String: Int]?,
        status: HomeRecommendDiagnosticsStatus
    ) -> [String: Int] {
        var counts = incrementing("response_count", in: previous)
        if status == .failed {
            counts["failure_count", default: 0] += 1
        }
        return counts
    }

    private static func incrementing(
        _ key: String,
        in previous: [String: Int]?
    ) -> [String: Int] {
        var counts = previous ?? [:]
        counts[key, default: 0] += 1
        return counts
    }
}

nonisolated enum HomeRecommendDiagnosticsRequestPolicy {
    static func acceptsResponse(
        currentRequestID: UUID?,
        responseRequestID: UUID?
    ) -> Bool {
        responseRequestID == nil || currentRequestID == responseRequestID
    }
}

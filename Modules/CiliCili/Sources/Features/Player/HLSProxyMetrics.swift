import Foundation
import os

actor HLSProxyStartupMetrics {
    static let shared = HLSProxyStartupMetrics()

    private let maxSessionCount = 36
    private var sessions: [String: Session] = [:]
    private var order: [String] = []

    func reset(metricsID: String?) {
        guard let metricsID, !metricsID.isEmpty else { return }
        sessions[metricsID] = nil
        order.removeAll { $0 == metricsID }
    }

    func summary(metricsID: String?) -> String? {
        guard let metricsID, !metricsID.isEmpty,
              let session = sessions[metricsID],
              session.hasEntries
        else { return nil }
        return session.summary
    }

    func record(
        metricsID: String?,
        path: String,
        bytes: Int,
        elapsedMilliseconds: Double,
        source: String
    ) async {
        guard let metricsID, !metricsID.isEmpty,
              let bucket = StartupBucket(path: path)
        else { return }

        var session = sessions[metricsID] ?? Session()
        let didUpdate = session.record(
            bucket,
            bytes: bytes,
            elapsedMilliseconds: elapsedMilliseconds,
            source: source
        )
        guard didUpdate else { return }

        if sessions[metricsID] == nil {
            order.append(metricsID)
        }
        sessions[metricsID] = session
        trimIfNeeded()

        let message = session.summary
        PlayerMetricsLog.logger.info(
            "hlsProxyStartup id=\(metricsID, privacy: .public) path=\(path, privacy: .public) source=\(source, privacy: .public) elapsedMs=\(elapsedMilliseconds, format: .fixed(precision: 1), privacy: .public) bytes=\(bytes, privacy: .public) summary=\(message, privacy: .public)"
        )
        await PlayerMetricsLog.record(.network, metricsID: metricsID, message: message)
    }

    private func trimIfNeeded() {
        guard order.count > maxSessionCount else { return }
        let overflow = order.count - maxSessionCount
        for key in order.prefix(overflow) {
            sessions[key] = nil
        }
        order.removeFirst(overflow)
    }

    private struct Session: Sendable {
        private var entries: [StartupBucket: Entry] = [:]

        var hasEntries: Bool {
            !entries.isEmpty
        }

        var summary: String {
            [
                "HLS",
                "m:\(value(.masterPlaylist))",
                "v/a:\(value(.videoPlaylist))/\(value(.audioPlaylist))",
                "init:\(value(.videoInit))/\(value(.audioInit))",
                "seg0:\(value(.videoSegment0))/\(value(.audioSegment0))",
                "seg1:\(value(.videoSegment1))/\(value(.audioSegment1))"
            ].joined(separator: " ")
        }

        mutating func record(
            _ bucket: StartupBucket,
            bytes: Int,
            elapsedMilliseconds: Double,
            source: String
        ) -> Bool {
            let rounded = max(0, Int(elapsedMilliseconds.rounded()))
            if let existing = entries[bucket], existing.elapsedMilliseconds <= rounded {
                return false
            }
            entries[bucket] = Entry(
                bytes: bytes,
                elapsedMilliseconds: rounded,
                source: source
            )
            return true
        }

        private func value(_ bucket: StartupBucket) -> String {
            guard let entry = entries[bucket] else { return "-" }
            return "\(entry.elapsedMilliseconds)"
        }
    }

    private struct Entry: Sendable {
        let bytes: Int
        let elapsedMilliseconds: Int
        let source: String
    }

    private enum StartupBucket: Hashable, Sendable {
        case masterPlaylist
        case videoPlaylist
        case audioPlaylist
        case videoInit
        case audioInit
        case videoSegment0
        case audioSegment0
        case videoSegment1
        case audioSegment1

        init?(path: String) {
            let normalizedPath = path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? path
            switch normalizedPath {
            case "/master.m3u8":
                self = .masterPlaylist
            case "/audio.m3u8":
                self = .audioPlaylist
            default:
                let components = normalizedPath.split(separator: "/").map(String.init)
                if components.count == 1,
                   components[0].hasPrefix("video"),
                   components[0].hasSuffix(".m3u8") {
                    self = .videoPlaylist
                    return
                }
                guard components.count == 3,
                      components[0] == "media"
                else { return nil }
                let routePrefix = components[1]
                let component = components[2]
                let isVideo = routePrefix.hasPrefix("video")
                let isAudio = routePrefix == "audio"
                switch (isVideo, isAudio, component) {
                case (true, false, "init.mp4"):
                    self = .videoInit
                case (false, true, "init.mp4"):
                    self = .audioInit
                case (true, false, "segment-0.m4s"):
                    self = .videoSegment0
                case (false, true, "segment-0.m4s"):
                    self = .audioSegment0
                case (true, false, "segment-1.m4s"):
                    self = .videoSegment1
                case (false, true, "segment-1.m4s"):
                    self = .audioSegment1
                default:
                    return nil
                }
            }
        }
    }
}

actor HLSProxyCacheMetrics {
    static let shared = HLSProxyCacheMetrics()

    private let maxSessionCount = 36
    private var sessions: [String: Session] = [:]
    private var order: [String] = []
    private var updateCounts: [String: Int] = [:]

    func record(
        metricsID: String?,
        path: String,
        source: String,
        bytes: Int,
        elapsedMilliseconds: Double
    ) async {
        guard let metricsID, !metricsID.isEmpty else { return }
        var session = sessions[metricsID] ?? Session()
        if sessions[metricsID] == nil {
            order.append(metricsID)
        }
        session.record(source: source, bytes: bytes, elapsedMilliseconds: elapsedMilliseconds)
        sessions[metricsID] = session
        trimIfNeeded()

        let message = session.summary
        PlayerMetricsLog.logger.info(
            "hlsProxyCache id=\(metricsID, privacy: .public) path=\(path, privacy: .public) source=\(source, privacy: .public) elapsedMs=\(elapsedMilliseconds, format: .fixed(precision: 1), privacy: .public) bytes=\(bytes, privacy: .public) summary=\(message, privacy: .public)"
        )
        guard shouldPublish(metricsID: metricsID, source: source) else { return }
        await PlayerMetricsLog.record(.mediaCache, metricsID: metricsID, message: message)
    }

    private func shouldPublish(metricsID: String, source: String) -> Bool {
        var count = updateCounts[metricsID] ?? 0
        count += 1
        updateCounts[metricsID] = count
        return count <= 2 || count.isMultiple(of: 12)
    }

    private func trimIfNeeded() {
        guard order.count > maxSessionCount else { return }
        let overflow = order.count - maxSessionCount
        for key in order.prefix(overflow) {
            sessions[key] = nil
            updateCounts[key] = nil
        }
        order.removeFirst(overflow)
    }

    private struct Session: Sendable {
        private var cacheHits = 0
        private var remoteFetches = 0
        private var streamedRanges = 0
        private var joinedRanges = 0
        private var totalBytes = 0
        private var bestElapsedMilliseconds: Int?

        var summary: String {
            let best = bestElapsedMilliseconds.map { "\($0)ms" } ?? "-"
            return [
                "Cache",
                "hit:\(cacheHits)",
                "fetch:\(remoteFetches)",
                "stream:\(streamedRanges)",
                "join:\(joinedRanges)",
                "bytes:\(totalBytes / 1024)KB",
                "best:\(best)"
            ].joined(separator: " ")
        }

        mutating func record(source: String, bytes: Int, elapsedMilliseconds: Double) {
            if source.contains("Cache") || source == "cache" {
                cacheHits += 1
            } else if source == "streamJoin" {
                joinedRanges += 1
            } else if source == "stream" {
                streamedRanges += 1
            } else {
                remoteFetches += 1
            }
            totalBytes += max(bytes, 0)
            let roundedElapsed = max(0, Int(elapsedMilliseconds.rounded()))
            if roundedElapsed > 0, bestElapsedMilliseconds.map({ roundedElapsed < $0 }) ?? true {
                bestElapsedMilliseconds = roundedElapsed
            }
        }
    }
}

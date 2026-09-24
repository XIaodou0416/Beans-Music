import CoreGraphics
import Foundation

struct HLSBridgeTrack: Sendable {
    enum MediaType: Sendable {
        case video
        case audio

        nonisolated var isVideo: Bool {
            switch self {
            case .video:
                true
            case .audio:
                false
            }
        }

        nonisolated var logLabel: String {
            switch self {
            case .video:
                "video"
            case .audio:
                "audio"
            }
        }
    }

    let url: URL
    let fallbackURLs: [URL]
    let stream: DASHStream?
    let mediaType: MediaType
    let dynamicRange: BiliVideoDynamicRange

    nonisolated init(
        url: URL,
        fallbackURLs: [URL] = [],
        stream: DASHStream?,
        mediaType: MediaType,
        dynamicRange: BiliVideoDynamicRange = .sdr
    ) {
        self.url = url
        self.fallbackURLs = fallbackURLs.filter { $0 != url }
        self.stream = stream
        self.mediaType = mediaType
        self.dynamicRange = switch mediaType {
        case .video:
            dynamicRange
        case .audio:
            .sdr
        }
    }

    nonisolated init(
        stream: DASHStream,
        mediaType: MediaType,
        dynamicRange: BiliVideoDynamicRange = .sdr,
        cdnPreference: PlaybackCDNPreference = .automatic
    ) throws {
        guard let url = stream.playURL(cdnPreference: cdnPreference) else {
            throw PlayerEngineError.missingVideoURL
        }
        self.init(
            url: url,
            fallbackURLs: stream.backupPlayURLs(cdnPreference: cdnPreference),
            stream: stream,
            mediaType: mediaType,
            dynamicRange: dynamicRange
        )
    }

    nonisolated var cacheIdentity: String {
        ([url] + fallbackURLs)
            .map(\.absoluteString)
            .joined(separator: ",")
    }
}

struct HLSBridgeSourceDiagnosticsSnapshot: Identifiable, Equatable, Sendable {
    let host: String
    let order: Int
    let averageMilliseconds: Int?
    let averageKilobytesPerSecond: Int
    let successCount: Int
    let failureCount: Int
    let isSessionAvoided: Bool
    let avoidanceReason: String?
    let avoidanceExpiresAt: Date?

    var id: String { host }

    var attemptCount: Int {
        successCount + failureCount
    }

    var failureRatePercent: Int {
        guard attemptCount > 0 else { return 0 }
        return Int((Double(failureCount) / Double(attemptCount) * 100).rounded())
    }
}

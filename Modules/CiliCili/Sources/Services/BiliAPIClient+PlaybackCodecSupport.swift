import Foundation

nonisolated enum PlayURLCodecPreference: String, CaseIterable {
    case av1
    case hevc
    case automatic
    case avc

    static func primaryPlaybackOrder(requestedQuality: Int?) -> [PlayURLCodecPreference] {
        playbackOrder(for: VideoCodecPreference.stored(), requestedQuality: requestedQuality)
    }

    static func extendedPlaybackOrder(requestedQuality: Int?) -> [PlayURLCodecPreference] {
        playbackOrder(for: VideoCodecPreference.stored(), requestedQuality: requestedQuality)
    }

    private static func playbackOrder(
        for preference: VideoCodecPreference,
        requestedQuality: Int?
    ) -> [PlayURLCodecPreference] {
        if requestedQuality.map({ BiliAPIClient.requiresAutomaticCodecNegotiation(requestedQuality: $0) }) == true {
            return [.automatic]
        }
        let configuredOrder = preference.codecOrder.compactMap { codec -> PlayURLCodecPreference? in
            switch codec {
            case .av1:
                return .av1
            case .hevc:
                return .hevc
            case .h264:
                return .avc
            case .unknown:
                return nil
            }
        }
        guard configuredOrder.count > 1 else {
            return configuredOrder.isEmpty ? [.automatic] : configuredOrder
        }
        if configuredOrder.first == .av1 {
            // The unconstrained response most consistently exposes AV1 alongside
            // the configured fallbacks, so selection can stay local.
            return [.automatic] + configuredOrder
        }
        return configuredOrder + [.automatic]
    }

    func videoCodecid(requestedQuality: Int) -> String? {
        guard !BiliAPIClient.requiresAutomaticCodecNegotiation(requestedQuality: requestedQuality) else {
            return nil
        }
        switch self {
        case .av1:
            return "13"
        case .hevc:
            return "12"
        case .automatic:
            return nil
        case .avc:
            return "7"
        }
    }

    var stageSuffix: String {
        switch self {
        case .av1:
            return "AV1"
        case .hevc:
            return ""
        case .automatic:
            return "AutoCodec"
        case .avc:
            return "AVC"
        }
    }

    func accepts(_ data: PlayURLData) -> Bool {
        switch self {
        case .av1:
            return data.dash?.video?.contains(where: \.isAV1VideoCodec) == true
        case .hevc:
            return data.dash?.video?.contains(where: \.isHEVCVideoCodec) == true
        case .avc:
            return data.dash?.video?.contains(where: \.isAVCVideoCodec) == true
        case .automatic:
            return true
        }
    }

    var selectionCodecFamily: VideoCodecFamily? {
        switch self {
        case .av1:
            return .av1
        case .hevc:
            return .hevc
        case .avc:
            return .h264
        case .automatic:
            return VideoCodecPreference.stored().codecOrder.first
        }
    }

    var allowsUnavailableQualityFallback: Bool {
        self != .automatic
    }
}

extension BiliAPIClient {
    nonisolated func userAgent(for streamSource: PlaybackStreamSourcePreference) -> String {
        switch streamSource {
        case .web:
            return Self.webUserAgent
        case .app:
            return Self.mobileUserAgent
        }
    }

    nonisolated func preferredStartupCandidate(
        _ lhs: PlayURLData?,
        _ rhs: PlayURLData,
        requestedQuality: Int
    ) -> PlayURLData? {
        guard Self.startupCandidateQuality(in: rhs, requestedQuality: requestedQuality) != nil else {
            return lhs
        }
        guard let lhs else { return rhs }
        guard let lhsQuality = Self.startupCandidateQuality(in: lhs, requestedQuality: requestedQuality) else {
            return rhs
        }
        let rhsQuality = Self.startupCandidateQuality(in: rhs, requestedQuality: requestedQuality) ?? 0
        return rhsQuality > lhsQuality ? rhs : lhs
    }

    nonisolated func requireRequestedQualityIfNeeded(
        _ data: PlayURLData,
        requestedQuality: Int
    ) throws -> PlayURLData {
        guard Self.requiresAutomaticCodecNegotiation(requestedQuality: requestedQuality),
            !data.hasMediaPayloadQuality(requestedQuality)
        else { return data }
        throw BiliAPIError.emptyPlayURL
    }

    nonisolated func shouldTryAlternatePlayURLCodec(after error: Error) -> Bool {
        guard let biliError = error as? BiliAPIError else { return false }
        switch biliError {
        case .emptyPlayURL, .unsupportedHardwarePlayback:
            return true
        default:
            return false
        }
    }
}

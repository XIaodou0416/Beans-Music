import AVFoundation
import Foundation

nonisolated enum HLSBridgeRemoteFailureCategory: String, Sendable {
    case authDenied
    case urlExpired
    case rangeUnsupported
    case rateLimited
    case serverUnavailable
    case timeout
    case network
    case invalidResponse
    case codecUnsupported
    case hardwareDecodeRejected
    case decoderFailed
    case terminalStall
    case cancelled
    case unknown
}

nonisolated struct HLSBridgeFailureReason: Sendable, Equatable {
    enum Layer: String, Sendable {
        case remoteRange
        case proxy
        case stream
        case avPlayerItem
        case local
    }

    let layer: Layer
    let category: HLSBridgeRemoteFailureCategory
    let statusCode: Int?
    let urlHost: String?
    let rangeDescription: String?
    let underlyingDescription: String?

    var playbackMessage: String {
        HLSBridgeRemoteFailure.userMessage(for: category)
    }

    var allowsSameSourceRecovery: Bool {
        switch category {
        case .authDenied, .urlExpired, .rangeUnsupported, .rateLimited,
             .codecUnsupported, .hardwareDecodeRejected, .decoderFailed,
             .cancelled:
            return false
        case .serverUnavailable, .timeout, .network, .invalidResponse,
             .terminalStall, .unknown:
            return true
        }
    }

    var shouldFailPlaybackImmediately: Bool {
        category != .cancelled && !allowsSameSourceRecovery
    }

    var isRecoverableByRebuild: Bool {
        switch category {
        case .cancelled, .authDenied, .urlExpired, .rateLimited:
            return false
        case .rangeUnsupported, .serverUnavailable, .timeout, .network, .invalidResponse,
             .codecUnsupported, .hardwareDecodeRejected, .decoderFailed,
             .terminalStall, .unknown:
            return true
        }
    }

    var shouldRecordSourceFailure: Bool {
        switch layer {
        case .remoteRange, .proxy, .stream:
            return category != .cancelled
        case .avPlayerItem, .local:
            return false
        }
    }

    var sourceAvoidanceReason: String {
        let statusSuffix = statusCode.map { "-\($0)" } ?? ""
        return "\(category.rawValue)\(statusSuffix)"
    }

    var sourceAvoidancePenaltyMultiplier: Int {
        switch category {
        case .authDenied, .urlExpired, .rateLimited:
            return 3
        case .rangeUnsupported, .serverUnavailable:
            return 2
        case .timeout, .network, .invalidResponse, .codecUnsupported,
             .hardwareDecodeRejected, .decoderFailed, .terminalStall, .unknown:
            return 1
        case .cancelled:
            return 0
        }
    }

    var proxyHTTPStatus: (statusCode: Int, reason: String) {
        switch category {
        case .authDenied:
            return (403, "Forbidden")
        case .urlExpired:
            return (410, "Gone")
        case .rangeUnsupported:
            return (416, "Range Not Satisfiable")
        case .rateLimited:
            return (429, "Too Many Requests")
        case .timeout:
            return (504, "Gateway Timeout")
        case .cancelled:
            return (499, "Client Closed Request")
        case .serverUnavailable, .network, .invalidResponse, .codecUnsupported,
             .hardwareDecodeRejected, .decoderFailed, .terminalStall, .unknown:
            return (502, "Bad Gateway")
        }
    }
}

typealias HLSRemoteFailureHandler = @MainActor @Sendable (HLSBridgeFailureReason) -> Void

nonisolated struct HLSBridgeRemoteFailure: LocalizedError, Sendable {
    let category: HLSBridgeRemoteFailureCategory
    let statusCode: Int?
    let urlHost: String?
    let rangeDescription: String?
    let underlyingDescription: String?

    var reason: HLSBridgeFailureReason {
        HLSBridgeFailureReason(
            layer: .remoteRange,
            category: category,
            statusCode: statusCode,
            urlHost: urlHost,
            rangeDescription: rangeDescription,
            underlyingDescription: underlyingDescription
        )
    }

    var errorDescription: String? {
        reason.playbackMessage
    }

    static func httpStatus(_ statusCode: Int, url: URL?, range: HTTPByteRange?) -> HLSBridgeRemoteFailure {
        HLSBridgeRemoteFailure(
            category: category(forHTTPStatus: statusCode),
            statusCode: statusCode,
            urlHost: normalizedHost(url),
            rangeDescription: range.map(rangeDescription(for:)),
            underlyingDescription: "HTTP \(statusCode)"
        )
    }

    static func urlSession(_ error: URLError, url: URL?, range: HTTPByteRange?) -> HLSBridgeRemoteFailure {
        HLSBridgeRemoteFailure(
            category: category(forURLErrorCode: error.code),
            statusCode: nil,
            urlHost: normalizedHost(url),
            rangeDescription: range.map(rangeDescription(for:)),
            underlyingDescription: error.localizedDescription
        )
    }

    static func invalidRangeResponse(statusCode: Int, url: URL?, range: HTTPByteRange) -> HLSBridgeRemoteFailure {
        HLSBridgeRemoteFailure(
            category: .rangeUnsupported,
            statusCode: statusCode,
            urlHost: normalizedHost(url),
            rangeDescription: rangeDescription(for: range),
            underlyingDescription: "Range ignored by CDN"
        )
    }

    static func emptyResponse(url: URL?, range: HTTPByteRange) -> HLSBridgeRemoteFailure {
        HLSBridgeRemoteFailure(
            category: .invalidResponse,
            statusCode: nil,
            urlHost: normalizedHost(url),
            rangeDescription: rangeDescription(for: range),
            underlyingDescription: "Empty range response"
        )
    }

    static func playbackMessage(forHTTPStatus statusCode: Int) -> String? {
        reason(forHTTPStatus: statusCode)?.playbackMessage
    }

    static func allowsSameSourceRecovery(forHTTPStatus statusCode: Int) -> Bool {
        reason(forHTTPStatus: statusCode)?.allowsSameSourceRecovery ?? true
    }

    static func allowsSameSourceRecovery(forPlaybackMessage message: String) -> Bool {
        !(message.contains(userMessage(for: .urlExpired))
            || message.contains(userMessage(for: .authDenied))
            || message.contains(userMessage(for: .rangeUnsupported))
            || message.contains(userMessage(for: .rateLimited)))
    }

    static func proxyHTTPStatus(for error: Error) -> (statusCode: Int, reason: String) {
        reason(for: error).proxyHTTPStatus
    }

    static func sourceAvoidanceReason(for error: Error) -> String {
        reason(for: error).sourceAvoidanceReason
    }

    static func sourceAvoidancePenaltyMultiplier(for error: Error) -> Int {
        reason(for: error).sourceAvoidancePenaltyMultiplier
    }

    static func shouldRecordSourceFailure(_ error: Error) -> Bool {
        reason(for: error).shouldRecordSourceFailure
    }

    static func reason(for error: Error) -> HLSBridgeFailureReason {
        if let failure = error as? HLSBridgeRemoteFailure {
            return failure.reason
        }
        if let reason = reasonForAVFoundationError(error) {
            return reason
        }
        if let streamError = error as? HLSRangeStreamError {
            switch streamError {
            case let .responseAlreadyStarted(underlying):
                let underlyingReason = reason(for: underlying)
                return HLSBridgeFailureReason(
                    layer: .stream,
                    category: underlyingReason.category,
                    statusCode: underlyingReason.statusCode,
                    urlHost: underlyingReason.urlHost,
                    rangeDescription: underlyingReason.rangeDescription,
                    underlyingDescription: underlyingReason.underlyingDescription
                )
            case .notCacheable:
                return HLSBridgeFailureReason(
                    layer: .stream,
                    category: .invalidResponse,
                    statusCode: nil,
                    urlHost: nil,
                    rangeDescription: nil,
                    underlyingDescription: streamError.localizedDescription
                )
            }
        }
        if error is CancellationError {
            return HLSBridgeFailureReason(
                layer: .local,
                category: .cancelled,
                statusCode: nil,
                urlHost: nil,
                rangeDescription: nil,
                underlyingDescription: error.localizedDescription
            )
        }
        if let urlError = error as? URLError {
            return HLSBridgeFailureReason(
                layer: .remoteRange,
                category: category(forURLErrorCode: urlError.code),
                statusCode: nil,
                urlHost: nil,
                rangeDescription: nil,
                underlyingDescription: urlError.localizedDescription
            )
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return HLSBridgeFailureReason(
                layer: .remoteRange,
                category: category(forURLErrorCode: URLError.Code(rawValue: nsError.code)),
                statusCode: nil,
                urlHost: nil,
                rangeDescription: nil,
                underlyingDescription: nsError.localizedDescription
            )
        }
        return HLSBridgeFailureReason(
            layer: .local,
            category: .unknown,
            statusCode: nil,
            urlHost: nil,
            rangeDescription: nil,
            underlyingDescription: error.localizedDescription
        )
    }

    static func reason(forHTTPStatus statusCode: Int) -> HLSBridgeFailureReason? {
        switch statusCode {
        case 401, 403, 404, 410, 412, 416, 429, 500...599:
            return HLSBridgeFailureReason(
                layer: .remoteRange,
                category: category(forHTTPStatus: statusCode),
                statusCode: statusCode,
                urlHost: nil,
                rangeDescription: nil,
                underlyingDescription: "HTTP \(statusCode)"
            )
        default:
            return nil
        }
    }

    private static func reasonForAVFoundationError(_ error: Error) -> HLSBridgeFailureReason? {
        let nsError = error as NSError
        guard nsError.domain == AVFoundationErrorDomain else { return nil }
        let category: HLSBridgeRemoteFailureCategory
        switch nsError.code {
        case AVError.Code.decoderNotFound.rawValue,
             AVError.Code.decoderTemporarilyUnavailable.rawValue:
            category = .decoderFailed
        case AVError.Code.fileFormatNotRecognized.rawValue,
             AVError.Code.unsupportedOutputSettings.rawValue:
            category = .codecUnsupported
        case AVError.Code.contentIsNotAuthorized.rawValue:
            category = .authDenied
        case AVError.Code.contentIsUnavailable.rawValue:
            category = .invalidResponse
        default:
            return nil
        }
        return HLSBridgeFailureReason(
            layer: .avPlayerItem,
            category: category,
            statusCode: nil,
            urlHost: nil,
            rangeDescription: nil,
            underlyingDescription: nsError.localizedDescription
        )
    }

    private static func category(forHTTPStatus statusCode: Int) -> HLSBridgeRemoteFailureCategory {
        switch statusCode {
        case 401, 403:
            return .authDenied
        case 404, 410, 412:
            return .urlExpired
        case 416:
            return .rangeUnsupported
        case 429:
            return .rateLimited
        case 500...599:
            return .serverUnavailable
        default:
            return .invalidResponse
        }
    }

    private static func category(forURLErrorCode code: URLError.Code) -> HLSBridgeRemoteFailureCategory {
        switch code {
        case .cancelled:
            return .cancelled
        case .timedOut:
            return .timeout
        case .networkConnectionLost,
             .notConnectedToInternet,
             .cannotConnectToHost,
             .cannotFindHost,
             .secureConnectionFailed:
            return .network
        default:
            return .network
        }
    }

    static func userMessage(for category: HLSBridgeRemoteFailureCategory) -> String {
        switch category {
        case .authDenied:
            return "播放鉴权失败，请刷新登录态或重新获取播放地址"
        case .urlExpired:
            return "播放地址已过期，请重新获取播放地址"
        case .rangeUnsupported:
            return "当前 CDN 不支持分片 Range 请求，正在切换线路"
        case .rateLimited:
            return "当前 CDN 请求过于频繁，正在切换线路"
        case .serverUnavailable:
            return "当前 CDN 临时不可用，正在切换线路"
        case .timeout:
            return "当前 CDN 响应超时，正在切换线路"
        case .network:
            return "网络连接中断，正在切换线路"
        case .invalidResponse:
            return "CDN 返回异常数据，正在切换线路"
        case .codecUnsupported, .hardwareDecodeRejected, .decoderFailed:
            return "当前视频流暂不支持 AVPlayer 解码，正在切换兼容格式"
        case .terminalStall:
            return "播放长时间无进展，正在切换播放器"
        case .cancelled:
            return "播放请求已取消"
        case .unknown:
            return PlayerEngineError.unsupportedMedia.localizedDescription
        }
    }

    private static func normalizedHost(_ url: URL?) -> String? {
        guard let host = url?.host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !host.isEmpty
        else { return nil }
        return host
    }

    private static func rangeDescription(for range: HTTPByteRange) -> String {
        "\(range.start)-\(range.endInclusive)"
    }
}

enum HLSRangeStreamError: LocalizedError {
    case responseAlreadyStarted(Error)
    case notCacheable

    nonisolated var isRetryable: Bool {
        switch self {
        case .responseAlreadyStarted:
            false
        case .notCacheable:
            true
        }
    }

    nonisolated var errorDescription: String? {
        switch self {
        case let .responseAlreadyStarted(error):
            error.localizedDescription
        case .notCacheable:
            "range is too large to cache"
        }
    }
}

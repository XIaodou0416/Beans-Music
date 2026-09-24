import Foundation

enum VideoDetailPlaybackRecoveryFailureSource: String, Sendable {
    case playerCallback
    case errorObserver
    case appResume
}

enum VideoDetailPlaybackRecoveryIgnoreReason: String, Sendable, Equatable {
    case navigationInvalidated
    case navigationInterrupted
    case staleVariant
    case duplicateFailure
    case cancelled
    case playURLReloadInFlight
}

enum VideoDetailPlaybackRecoveryAction: Sendable, Equatable {
    case ignore(VideoDetailPlaybackRecoveryIgnoreReason)
    case reloadPlayURL
    case switchVariant
    case exhausted
}

struct VideoDetailPlaybackRecoveryInput: Sendable, Equatable {
    let source: VideoDetailPlaybackRecoveryFailureSource
    let message: String
    let reason: HLSBridgeFailureReason?
    let failedVariantID: String
    let selectedVariantID: String?
    let hasFallbackVariant: Bool
    let playURLIsLoading: Bool
    let recoveryAttemptCount: Int
    let maxRecoveryReloadAttempts: Int
    let isPlaybackInvalidatedForNavigation: Bool
    let hasPendingNavigationInterruption: Bool
}

struct VideoDetailPlaybackRecoveryDecision: Sendable, Equatable {
    let action: VideoDetailPlaybackRecoveryAction
    let shouldMarkFailedVariant: Bool
    let shouldRefreshCDN: Bool

    var shouldHandleFailure: Bool {
        switch action {
        case .ignore:
            return false
        case .reloadPlayURL, .switchVariant, .exhausted:
            return true
        }
    }
}

struct VideoDetailPlaybackRecoveryCoordinator: Sendable, Equatable {
    private var handledFailureSignatures = Set<FailureSignature>()

    mutating func reset() {
        handledFailureSignatures.removeAll()
    }

    mutating func receiveFailure(
        _ input: VideoDetailPlaybackRecoveryInput
    ) -> VideoDetailPlaybackRecoveryDecision {
        if input.isPlaybackInvalidatedForNavigation {
            return ignored(.navigationInvalidated)
        }
        if input.hasPendingNavigationInterruption {
            return ignored(.navigationInterrupted)
        }
        if input.selectedVariantID != input.failedVariantID {
            return ignored(.staleVariant)
        }
        if input.reason?.category == .cancelled {
            return ignored(.cancelled)
        }

        let signature = FailureSignature(input)
        guard handledFailureSignatures.insert(signature).inserted else {
            return ignored(.duplicateFailure)
        }

        let shouldRefreshCDN = Self.shouldRefreshCDN(for: input.reason)
        let canReloadPlayURL = input.recoveryAttemptCount < input.maxRecoveryReloadAttempts
            && !input.playURLIsLoading
        let shouldReloadPlayURL = Self.prefersPlayURLReload(message: input.message, reason: input.reason)
            || Self.requiresPlayURLReload(input.reason)

        if shouldReloadPlayURL, input.playURLIsLoading {
            return ignored(.playURLReloadInFlight)
        }
        if Self.prefersPlayURLReload(message: input.message, reason: input.reason), canReloadPlayURL {
            return handled(.reloadPlayURL, shouldRefreshCDN: shouldRefreshCDN)
        }
        if Self.requiresPlayURLReload(input.reason), canReloadPlayURL {
            return handled(.reloadPlayURL, shouldRefreshCDN: shouldRefreshCDN)
        }
        if Self.shouldRetrySameVariantOnAlternateCDN(input.reason),
           input.recoveryAttemptCount == 0,
           canReloadPlayURL {
            return handled(.reloadPlayURL, shouldRefreshCDN: shouldRefreshCDN)
        }
        if input.hasFallbackVariant {
            return handled(.switchVariant, shouldRefreshCDN: shouldRefreshCDN)
        }
        if canReloadPlayURL {
            return handled(.reloadPlayURL, shouldRefreshCDN: shouldRefreshCDN)
        }
        return handled(.exhausted, shouldRefreshCDN: shouldRefreshCDN)
    }

    static func shouldRefreshCDN(for reason: HLSBridgeFailureReason?) -> Bool {
        guard let reason else { return true }
        guard reason.layer != .local, reason.layer != .avPlayerItem else { return false }
        switch reason.category {
        case .cancelled, .authDenied, .urlExpired:
            return false
        case .rangeUnsupported, .rateLimited, .serverUnavailable, .timeout, .network, .invalidResponse,
             .codecUnsupported, .hardwareDecodeRejected, .decoderFailed, .terminalStall, .unknown:
            return true
        }
    }

    static func prefersPlayURLReload(message: String, reason: HLSBridgeFailureReason?) -> Bool {
        if let reason {
            switch reason.category {
            case .authDenied, .urlExpired:
                return true
            case .rangeUnsupported, .rateLimited, .serverUnavailable, .timeout, .network,
                 .invalidResponse, .codecUnsupported, .hardwareDecodeRejected, .decoderFailed,
                 .terminalStall, .cancelled, .unknown:
                break
            }
        }
        return message.contains("播放地址已过期")
            || message.contains("重新获取播放地址")
    }

    static func requiresPlayURLReload(_ reason: HLSBridgeFailureReason?) -> Bool {
        guard let reason else { return false }
        switch reason.category {
        case .authDenied, .urlExpired, .rateLimited:
            return true
        case .rangeUnsupported, .serverUnavailable, .timeout, .network, .invalidResponse,
             .codecUnsupported, .hardwareDecodeRejected, .decoderFailed, .terminalStall,
             .cancelled, .unknown:
            return false
        }
    }

    private static func shouldRetrySameVariantOnAlternateCDN(
        _ reason: HLSBridgeFailureReason?
    ) -> Bool {
        guard let reason else { return false }
        switch reason.category {
        case .serverUnavailable, .timeout, .network, .invalidResponse:
            return true
        case .authDenied, .urlExpired, .rangeUnsupported, .rateLimited, .codecUnsupported,
             .hardwareDecodeRejected, .decoderFailed, .terminalStall, .cancelled, .unknown:
            return false
        }
    }

    private func ignored(
        _ reason: VideoDetailPlaybackRecoveryIgnoreReason
    ) -> VideoDetailPlaybackRecoveryDecision {
        VideoDetailPlaybackRecoveryDecision(
            action: .ignore(reason),
            shouldMarkFailedVariant: false,
            shouldRefreshCDN: false
        )
    }

    private func handled(
        _ action: VideoDetailPlaybackRecoveryAction,
        shouldRefreshCDN: Bool
    ) -> VideoDetailPlaybackRecoveryDecision {
        VideoDetailPlaybackRecoveryDecision(
            action: action,
            shouldMarkFailedVariant: true,
            shouldRefreshCDN: shouldRefreshCDN
        )
    }
}

private struct FailureSignature: Hashable, Sendable {
    let selectedVariantID: String?
    let failedVariantID: String
    let recoveryAttemptCount: Int
    let reasonKey: String

    init(_ input: VideoDetailPlaybackRecoveryInput) {
        selectedVariantID = input.selectedVariantID
        failedVariantID = input.failedVariantID
        recoveryAttemptCount = input.recoveryAttemptCount
        if let reason = input.reason {
            reasonKey = [
                reason.category.rawValue,
                reason.layer.rawValue,
                reason.statusCode.map(String.init) ?? "-"
            ].joined(separator: ":")
        } else {
            reasonKey = "message:\(Self.normalizedMessageKey(input.message))"
        }
    }

    private static func normalizedMessageKey(_ message: String) -> String {
        let normalized = message
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(normalized.prefix(96))
    }
}

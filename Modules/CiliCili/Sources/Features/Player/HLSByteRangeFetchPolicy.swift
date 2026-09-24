import Foundation

enum HLSByteRangeFetchStrategy: Sendable {
    case sequential
    case fastFallback

    nonisolated var isFastFallback: Bool {
        switch self {
        case .fastFallback:
            return true
        case .sequential:
            return false
        }
    }

    nonisolated var logLabel: String {
        switch self {
        case .sequential:
            return "sequential"
        case .fastFallback:
            return "fastFallback"
        }
    }
}

struct HLSBootstrapFetchPolicy: Sendable {
    let fetchStrategy: HLSByteRangeFetchStrategy
    let remoteRequestPolicy: HLSRemoteByteRangeRequestPolicy
}

struct HLSRemoteByteRangeRequestPolicy: Sendable {
    let attempts: Int
    let smallRangeTimeout: TimeInterval
    let largeRangeTimeout: TimeInterval
    let retryDelayNanoseconds: UInt64
    let firstFallbackDelayNanoseconds: UInt64
    let additionalFallbackDelayNanoseconds: UInt64

    nonisolated static func `default`(for range: HTTPByteRange) -> HLSRemoteByteRangeRequestPolicy {
        HLSRemoteByteRangeRequestPolicy(
            attempts: 2,
            smallRangeTimeout: 1.6,
            largeRangeTimeout: 2.4,
            retryDelayNanoseconds: 90_000_000,
            firstFallbackDelayNanoseconds: 55_000_000,
            additionalFallbackDelayNanoseconds: 45_000_000
        )
    }

    nonisolated static func startupIndex(urlCount: Int) -> HLSRemoteByteRangeRequestPolicy {
        if urlCount > 1 {
            return HLSRemoteByteRangeRequestPolicy(
                attempts: 1,
                smallRangeTimeout: 0.78,
                largeRangeTimeout: 1.05,
                retryDelayNanoseconds: 0,
                firstFallbackDelayNanoseconds: 18_000_000,
                additionalFallbackDelayNanoseconds: 22_000_000
            )
        } else {
            return HLSRemoteByteRangeRequestPolicy(
                attempts: 2,
                smallRangeTimeout: 0.85,
                largeRangeTimeout: 1.1,
                retryDelayNanoseconds: 45_000_000,
                firstFallbackDelayNanoseconds: 55_000_000,
                additionalFallbackDelayNanoseconds: 45_000_000
            )
        }
    }

    nonisolated func timeoutInterval(for range: HTTPByteRange) -> TimeInterval {
        range.length > 1_500_000 ? largeRangeTimeout : smallRangeTimeout
    }

    nonisolated func fastFallbackDelayNanoseconds(forSourceIndex index: Int) -> UInt64 {
        guard index > 0 else { return 0 }
        return firstFallbackDelayNanoseconds
            + UInt64(max(index - 1, 0)) * additionalFallbackDelayNanoseconds
    }
}

extension VideoRangeExternalFetchReservation {
    nonisolated var isReserved: Bool {
        if case .reserved = self {
            return true
        }
        return false
    }
}

struct HLSRenditionTimelineOffset: Sendable {
    let baseMediaDecodeTimeTicks: UInt64
}

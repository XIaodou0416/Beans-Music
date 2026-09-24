import Foundation

nonisolated enum RelatedPlaybackEarlyPlayURLPrefetchPolicy {
    static func isEligible(environment: PlaybackEnvironment) -> Bool {
        environment.networkClass == .wifi
            && !environment.isLowPowerModeEnabled
            && !environment.isThermallyConstrained
    }

    static func diagnosticStateTitle(for isEnabled: Bool?) -> String {
        switch isEnabled {
        case true:
            return "相关推荐早取：已启用"
        case false:
            return "相关推荐早取：历史未启用"
        case nil:
            return "相关推荐早取：旧样本未知"
        }
    }

    static func diagnosticMessage(
        event: String,
        targetBVID: String,
        disposition: RelatedPlaybackEarlyPlayURLPrefetchDisposition,
        leadMilliseconds: Int? = nil
    ) -> String {
        var parts = [
            "relatedEarlyPlayURLPrefetch",
            "event=\(event)",
            "target=\(targetBVID)",
            "result=\(disposition.rawValue)",
            "mediaWarm=off",
        ]
        if let leadMilliseconds {
            parts.append("lead=\(leadMilliseconds)ms")
        }
        return parts.joined(separator: " ")
    }
}

nonisolated enum RelatedPlaybackEarlyPlayURLPrefetchDisposition: String, Sendable {
    case cacheHit
    case joined
    case started
}

nonisolated struct RelatedPlaybackEarlyPlayURLPrefetchTrace: Sendable {
    let disposition: RelatedPlaybackEarlyPlayURLPrefetchDisposition
    let startedAt: Date

    func leadMilliseconds(at date: Date = Date()) -> Int {
        max(0, Int((date.timeIntervalSince(startedAt) * 1_000).rounded()))
    }
}

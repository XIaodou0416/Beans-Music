import Foundation

nonisolated enum RelatedPlaybackStartupPackageWarmupPolicy {
    static let stablePlaybackDelayNanoseconds: UInt64 = 700_000_000

    static func isEligible(environment: PlaybackEnvironment) -> Bool {
        environment.networkClass == .wifi
            && !environment.isLowPowerModeEnabled
            && !environment.isThermallyConstrained
    }

    static func diagnosticStateTitle(for isEnabled: Bool?) -> String {
        switch isEnabled {
        case true:
            return "相关推荐首包：已启用"
        case false:
            return "相关推荐首包：历史未启用"
        case nil:
            return "相关推荐首包：旧样本未知"
        }
    }

    static func diagnosticMessage(
        event: String,
        targetBVID: String,
        result: String,
        packageState: String? = nil,
        leadMilliseconds: Int? = nil
    ) -> String {
        var parts = [
            "relatedStartupPackageWarmup",
            "event=\(event)",
            "target=\(targetBVID)",
            "result=\(result)",
        ]
        if let packageState {
            parts.append("package=\(packageState)")
        }
        if let leadMilliseconds {
            parts.append("lead=\(leadMilliseconds)ms")
        }
        return parts.joined(separator: " ")
    }
}

nonisolated enum RelatedPlaybackStartupPackageWarmupDisposition: String, Sendable {
    case cacheHit
    case joined
    case started
    case missingPlayURL
    case budgetSkipped
}

nonisolated struct RelatedPlaybackStartupPackageWarmupTrace: Sendable {
    let disposition: RelatedPlaybackStartupPackageWarmupDisposition
    let startedAt: Date

    func leadMilliseconds(at date: Date = Date()) -> Int {
        max(0, Int((date.timeIntervalSince(startedAt) * 1_000).rounded()))
    }
}

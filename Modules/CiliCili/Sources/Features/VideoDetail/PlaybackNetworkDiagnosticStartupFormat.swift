import Foundation

extension PlaybackNetworkDiagnosticFormat {
    static func startupPlayURLTitle(for session: PlayerPerformanceSession) -> String {
        let source = session.startupPlayURLSource ?? session.startupSource
        var parts = [playURLSourceTitle(source)]
        if let count = session.startupPlayURLVariantCount {
            parts.append("\(count) 档")
        }
        return parts.joined(separator: " · ")
    }

    static func startupQualityTitle(_ quality: Int?) -> String {
        guard let quality else { return "未记录" }
        return "\(LibraryStore.videoQualityTitle(quality)) · q\(quality)"
    }

    static func startupRoutePlanTitle(for session: PlayerPerformanceSession) -> String {
        formattedStartupState(
            session.startupRoutePlanState,
            milliseconds: session.startupRoutePlanMilliseconds
        )
    }

    static func startupRoutePrebuildTitle(for session: PlayerPerformanceSession) -> String {
        formattedStartupState(
            session.startupRoutePrebuildState,
            milliseconds: session.startupRoutePrebuildMilliseconds
        )
    }

    static func startupPackageTitle(for session: PlayerPerformanceSession) -> String {
        var parts: [String] = []
        if let routePlan = session.startupPackageRoutePlanState {
            parts.append("Route \(startupStateTitle(routePlan))")
        }
        if let range = session.startupPackageRangeState {
            parts.append("Range \(startupStateTitle(range))")
        }
        return parts.isEmpty ? "未记录" : parts.joined(separator: " · ")
    }

    static func startupRangeWarmTitle(for session: PlayerPerformanceSession) -> String {
        if let state = session.startupRangeWarmState {
            return formattedStartupState(state, milliseconds: session.startupRangeWarmMilliseconds)
        }
        return formattedStartupState(session.startupPackageRangeState, milliseconds: nil)
    }
}

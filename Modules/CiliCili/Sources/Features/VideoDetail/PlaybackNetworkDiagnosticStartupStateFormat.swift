import Foundation

extension PlaybackNetworkDiagnosticFormat {
    static func formattedStartupState(_ state: String?, milliseconds: Int?) -> String {
        guard let state else { return "未记录" }
        var title = startupStateTitle(state)
        if let milliseconds {
            title += " · \(formattedMilliseconds(milliseconds))"
        }
        return title
    }

    static func startupStateTitle(_ state: String) -> String {
        switch state {
        case "hit":
            return "命中"
        case "pending":
            return "等待中"
        case "miss":
            return "未命中"
        case "uncached":
            return "未缓存"
        case "skippedPending":
            return "已有任务"
        case "ready":
            return "已就绪"
        case "skip", "skipped":
            return "跳过"
        default:
            return state
        }
    }
}

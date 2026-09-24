import Foundation

extension PlaybackNetworkDiagnosticFormat {
    static func playURLSourceTitle(_ source: String?) -> String {
        switch source {
        case "playableCache":
            return "可播放缓存"
        case "playableCachePreferredMiss":
            return "可播放缓存，画质待刷新"
        case "playableCacheTargetMiss":
            return "可播放缓存，目标画质待刷新"
        case "playableCacheStaleWhileRefresh":
            return "可播放缓存，后台刷新"
        case "cache":
            return "缓存"
        case "cachePreferredMiss":
            return "缓存，画质待刷新"
        case "cacheTargetMiss":
            return "缓存，目标画质待刷新"
        case "pendingCache":
            return "预加载结果"
        case "pendingCachePreferredMiss":
            return "预加载结果，画质待刷新"
        case "pendingCacheTargetMiss":
            return "预加载结果，目标画质待刷新"
        case "pendingCacheStaleWhileRefresh":
            return "预加载结果，后台刷新"
        case "detailWarmCache":
            return "详情预热缓存"
        case "network":
            return "网络请求"
        case "playableCacheFallbackAfterNetworkFailure":
            return "可播放缓存降级"
        case "cacheFallbackAfterNetworkFailure":
            return "缓存降级"
        case "pendingCacheFallbackAfterNetworkFailure":
            return "预加载缓存降级"
        case "stalePlayableCacheAfterNetworkFailure":
            return "过期可播放缓存降级"
        case "memoryPlayableCacheAfterNetworkFailure":
            return "内存可播放缓存降级"
        case "startupRecovery":
            return "启动取流恢复"
        case "networkRecovery":
            return "完整取流恢复"
        case "networkOrCache":
            return "网络/缓存"
        case let source?:
            return source
        case nil:
            return "未获取"
        }
    }
}

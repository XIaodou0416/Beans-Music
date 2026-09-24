import Foundation

struct VideoDetailDanmakuLoadingState {
    var fullLoadTask: Task<Void, Never>?
    var startupLoadTask: Task<Void, Never>?
    var startupLoadToken: UUID?
    var generation = 0
    var segmentTasks: [Int: Task<Void, Never>] = [:]
    var loadedSegments = Set<Int>()
    var loadingSegments = Set<Int>()
    var segmentItems: [Int: [DanmakuItem]] = [:]
    var didFallbackToFullLoad = false
    var lastScheduleKey: DanmakuScheduleKey?
    var isUnderPlaybackLoad = false
}

extension VideoDetailViewModel {
    var danmakuTask: Task<Void, Never>? {
        get { danmakuLoadingState.fullLoadTask }
        set { danmakuLoadingState.fullLoadTask = newValue }
    }

    var danmakuStartupLoadTask: Task<Void, Never>? {
        get { danmakuLoadingState.startupLoadTask }
        set { danmakuLoadingState.startupLoadTask = newValue }
    }

    var danmakuStartupLoadToken: UUID? {
        get { danmakuLoadingState.startupLoadToken }
        set { danmakuLoadingState.startupLoadToken = newValue }
    }

    var danmakuLoadGeneration: Int {
        get { danmakuLoadingState.generation }
        set { danmakuLoadingState.generation = newValue }
    }

    var danmakuSegmentTasks: [Int: Task<Void, Never>] {
        get { danmakuLoadingState.segmentTasks }
        set { danmakuLoadingState.segmentTasks = newValue }
    }

    var loadedDanmakuSegments: Set<Int> {
        get { danmakuLoadingState.loadedSegments }
        set { danmakuLoadingState.loadedSegments = newValue }
    }

    var loadingDanmakuSegments: Set<Int> {
        get { danmakuLoadingState.loadingSegments }
        set { danmakuLoadingState.loadingSegments = newValue }
    }

    var danmakuSegmentItems: [Int: [DanmakuItem]] {
        get { danmakuLoadingState.segmentItems }
        set { danmakuLoadingState.segmentItems = newValue }
    }

    var didFallbackToFullDanmakuLoad: Bool {
        get { danmakuLoadingState.didFallbackToFullLoad }
        set { danmakuLoadingState.didFallbackToFullLoad = newValue }
    }

    var lastDanmakuScheduleKey: DanmakuScheduleKey? {
        get { danmakuLoadingState.lastScheduleKey }
        set { danmakuLoadingState.lastScheduleKey = newValue }
    }

    var isDanmakuUnderPlaybackLoad: Bool {
        get { danmakuLoadingState.isUnderPlaybackLoad }
        set { danmakuLoadingState.isUnderPlaybackLoad = newValue }
    }
}

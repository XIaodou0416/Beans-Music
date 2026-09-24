import Foundation

extension VideoDetailViewModel {
    func scheduleDanmakuSegments(
        cid: Int,
        around playbackTime: TimeInterval,
        force: Bool,
        generation: Int? = nil
    ) {
        if force {
            resetDanmakuLoad(clearItems: true)
        }
        let loadGeneration = generation ?? danmakuLoadGeneration
        guard danmakuLoadGeneration == loadGeneration else { return }
        guard !didFallbackToFullDanmakuLoad else { return }

        let currentSegment = danmakuSegmentIndex(for: playbackTime)
        let scheduleKey = danmakuScheduleKey(cid: cid, playbackTime: playbackTime, segmentIndex: currentSegment)
        guard force || scheduleKey != lastDanmakuScheduleKey else {
            if danmakuSegmentTasks.isEmpty, danmakuState.isLoading {
                danmakuState = .loaded
            }
            return
        }
        lastDanmakuScheduleKey = scheduleKey

        trimRetainedDanmakuSegments(around: currentSegment)
        let segments = danmakuSegmentsToLoad(around: playbackTime)
            .filter { segment in
                !loadedDanmakuSegments.contains(segment)
                    && !loadingDanmakuSegments.contains(segment)
                    && danmakuSegmentTasks[segment] == nil
            }

        guard !segments.isEmpty else {
            if danmakuSegmentTasks.isEmpty, danmakuState.isLoading {
                danmakuState = .loaded
            }
            return
        }

        if danmakuItems.isEmpty {
            danmakuState = .loading
        }
        for segment in segments {
            loadDanmakuSegment(cid: cid, segmentIndex: segment, generation: loadGeneration)
        }
    }

    func resetDanmakuLoad(clearItems: Bool) {
        danmakuStartupLoadTask?.cancel()
        danmakuStartupLoadTask = nil
        danmakuStartupLoadToken = nil
        danmakuTask?.cancel()
        danmakuTask = nil
        danmakuSegmentTasks.values.forEach { $0.cancel() }
        danmakuSegmentTasks.removeAll()
        advanceDanmakuLoadGeneration()
        loadedDanmakuSegments.removeAll()
        loadingDanmakuSegments.removeAll()
        danmakuSegmentItems.removeAll()
        didFallbackToFullDanmakuLoad = false
        lastDanmakuScheduleKey = nil
        isDanmakuUnderPlaybackLoad = false
        if clearItems {
            updateDanmakuItems([])
        }
        danmakuState = .idle
    }
}

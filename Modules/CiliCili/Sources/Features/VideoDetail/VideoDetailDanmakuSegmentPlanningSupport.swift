import Foundation

extension VideoDetailViewModel {
    func danmakuSegmentsToLoad(around playbackTime: TimeInterval) -> [Int] {
        let current = danmakuSegmentIndex(for: playbackTime)
        var segments = [current]
        guard !isDanmakuUnderPlaybackLoad else {
            return boundedDanmakuSegments(segments)
        }
        if !shouldThrottleDanmakuSegmentPrefetch {
            segments.append(current + 1)
        }
        let offset = playbackTime - TimeInterval(current - 1) * Self.danmakuSegmentDuration
        if current > 1, offset < 18, !shouldThrottleDanmakuSegmentPrefetch {
            segments.insert(current - 1, at: 0)
        }
        return boundedDanmakuSegments(segments)
    }

    var shouldThrottleDanmakuSegmentPrefetch: Bool {
        isDanmakuUnderPlaybackLoad
            || PlaybackEnvironment.current.shouldPreferConservativePlayback
            || playbackAdaptationProfile.shouldThrottleBackgroundPreload
            || effectiveDanmakuSettings.loadFactor < 0.72
    }

    func boundedDanmakuSegments(_ segments: [Int]) -> [Int] {
        var bounded = Array(Set(segments.filter { $0 >= 1 })).sorted()
        if let maxSegment = maxDanmakuSegmentIndex {
            bounded = bounded.filter { $0 <= maxSegment }
        }
        return bounded
    }

    func trimRetainedDanmakuSegments(around segmentIndex: Int) {
        guard !danmakuSegmentItems.isEmpty else { return }
        let retainedRange = isDanmakuUnderPlaybackLoad
            ? max(1, segmentIndex - 1)...(segmentIndex + 1)
            : max(1, segmentIndex - 2)...(segmentIndex + 3)
        let removableSegments = danmakuSegmentItems.keys.filter { !retainedRange.contains($0) }
        guard !removableSegments.isEmpty else { return }
        removableSegments.forEach { danmakuSegmentItems[$0] = nil }
        refreshDanmakuItemsFromSegments()
    }

    func danmakuSegmentIndex(for playbackTime: TimeInterval) -> Int {
        max(1, Int(max(0, playbackTime) / Self.danmakuSegmentDuration) + 1)
    }

    func danmakuScheduleKey(cid: Int, playbackTime: TimeInterval, segmentIndex: Int) -> DanmakuScheduleKey {
        let segmentStart = TimeInterval(segmentIndex - 1) * Self.danmakuSegmentDuration
        let secondsIntoSegment = max(0, playbackTime - segmentStart)
        let isNearPreviousBoundary = segmentIndex > 1 && secondsIntoSegment < 18
        return DanmakuScheduleKey(
            cid: cid,
            segmentIndex: segmentIndex,
            includesPreviousSegment: isNearPreviousBoundary
        )
    }

    var maxDanmakuSegmentIndex: Int? {
        guard let duration = detail.duration, duration > 0 else { return nil }
        return max(1, Int(ceil(Double(duration) / Self.danmakuSegmentDuration)))
    }
}

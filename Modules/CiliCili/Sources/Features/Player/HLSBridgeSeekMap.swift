import Foundation

struct HLSBridgeSeekMap: Sendable {
    let sourceURLs: [URL]
    let initialization: HTTPByteRange
    let segments: [HLSBridgeSeekSegment]
    let includeExtraSegment: Bool

    nonisolated func alignedSeekTime(near playbackTime: TimeInterval) -> TimeInterval? {
        guard let segment = segment(near: playbackTime) else { return nil }
        let offset = playbackTime - segment.startTime
        guard offset.isFinite, offset >= 0 else { return nil }
        let alignmentWindow = min(max(segment.duration * 0.45, 0.65), 2.8)
        guard offset <= alignmentWindow else { return nil }
        return segment.startTime
    }

    nonisolated func warmRanges(around playbackTime: TimeInterval) -> [HTTPByteRange] {
        guard let index = segmentIndex(near: playbackTime) else { return [initialization] }
        let segmentCount = includeExtraSegment ? 3 : 2
        let upperBound = min(segments.count, index + segmentCount)
        return [initialization] + segments[index..<upperBound].map(\.range)
    }

    private nonisolated func segment(near playbackTime: TimeInterval) -> HLSBridgeSeekSegment? {
        guard let index = segmentIndex(near: playbackTime) else { return nil }
        return segments[safe: index]
    }

    private nonisolated func segmentIndex(near playbackTime: TimeInterval) -> Int? {
        guard playbackTime.isFinite, playbackTime >= 0, !segments.isEmpty else { return nil }
        return segments.lastIndex { segment in
            segment.startTime <= playbackTime
        } ?? 0
    }
}

struct HLSBridgeSeekSegment: Sendable {
    let startTime: TimeInterval
    let duration: TimeInterval
    let range: HTTPByteRange
}

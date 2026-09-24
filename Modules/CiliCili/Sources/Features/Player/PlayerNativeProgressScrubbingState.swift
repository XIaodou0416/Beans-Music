import SwiftUI

struct PlayerNativeProgressScrubbingState {
    var editingProgress = 0.0
    var isEditing = false
    var hasReportedScrubStart = false
    private var lastReportedChangeProgress: Double?

    mutating func beginScrub(
        at progress: Double,
        canSeek: Bool,
        onScrubStart: (Double) -> Void
    ) {
        guard canSeek else { return }
        let clampedProgress = min(max(progress, 0), 1)
        if !hasReportedScrubStart {
            hasReportedScrubStart = true
            isEditing = true
            editingProgress = clampedProgress
            lastReportedChangeProgress = nil
            onScrubStart(clampedProgress)
        } else {
            isEditing = true
            editingProgress = clampedProgress
        }
    }

    mutating func finishScrub(
        at progress: Double,
        canSeek: Bool,
        onScrubEnded: (Double) -> Void
    ) {
        guard canSeek else { return }
        let clampedProgress = min(max(progress, 0), 1)
        editingProgress = clampedProgress
        hasReportedScrubStart = false
        isEditing = false
        lastReportedChangeProgress = nil
        onScrubEnded(clampedProgress)
    }

    mutating func shouldReportChange(at progress: Double, minimumDelta: Double) -> Bool {
        let clampedProgress = min(max(progress, 0), 1)
        guard let lastReportedChangeProgress else {
            self.lastReportedChangeProgress = clampedProgress
            return true
        }
        guard abs(clampedProgress - lastReportedChangeProgress) >= minimumDelta else {
            return false
        }
        self.lastReportedChangeProgress = clampedProgress
        return true
    }

    mutating func reset() {
        hasReportedScrubStart = false
        isEditing = false
        lastReportedChangeProgress = nil
    }
}

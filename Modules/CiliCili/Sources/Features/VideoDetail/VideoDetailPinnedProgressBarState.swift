import Foundation

extension VideoDetailPinnedProgressBar {
    var displayedProgress: Double {
        guard isScrubbing else { return playbackProgress }
        return Self.clamped(scrubProgress)
    }

    var playbackProgress: Double {
        Self.clamped(playbackClock.displayProgress)
    }

    var resolvedDuration: TimeInterval? {
        playbackClock.duration ?? playerViewModel.displayDuration
    }

    var canSeek: Bool {
        playerViewModel.canSeek && (resolvedDuration ?? 0) > 0
    }

    var displayedTime: TimeInterval {
        guard isScrubbing, let duration = resolvedDuration, duration > 0 else {
            return max(playbackClock.displayCurrentTime, 0)
        }
        return displayedProgress * duration
    }

    var accessibilityStep: Double {
        guard let duration = resolvedDuration, duration > 0 else { return 0.05 }
        return min(max(10 / duration, 0.01), 0.10)
    }

    var accessibilityValue: String {
        let current = BiliFormatters.duration(Int(displayedTime.rounded()))
        guard let duration = resolvedDuration, duration > 0 else {
            return current
        }
        return "\(current) / \(BiliFormatters.duration(Int(duration.rounded())))"
    }
}

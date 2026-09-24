import SwiftUI

struct VideoDetailPinnedProgressBarActions {
    let playerViewModel: PlayerStateViewModel
    let canSeek: Bool
    let displayedProgress: Double
    let accessibilityStep: Double
    @Binding var isScrubbing: Bool
    @Binding var scrubProgress: Double
    @Binding var lastPreparedProgress: Double
    let onPrepareSeek: (Double) -> Void

    private var canInteractWithPlayer: Bool {
        canSeek && !playerViewModel.isTerminated
    }

    func progressDragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                handleDragChanged(locationX: value.location.x, width: width)
            }
            .onEnded { value in
                handleDragEnded(locationX: value.location.x, width: width)
            }
    }

    func handleAccessibilityAdjustment(_ direction: AccessibilityAdjustmentDirection) {
        guard canInteractWithPlayer else { return }
        switch direction {
        case .increment:
            seek(to: displayedProgress + accessibilityStep)
        case .decrement:
            seek(to: displayedProgress - accessibilityStep)
        default:
            break
        }
    }

    private func handleDragChanged(locationX: CGFloat, width: CGFloat) {
        guard canInteractWithPlayer else {
            resetScrubState()
            return
        }
        let progress = progress(at: locationX, in: width)
        if !isScrubbing {
            prepareSeekWarmupIfNeeded(progress, force: true)
            playerViewModel.beginUserScrubInteraction(source: .pinnedProgress)
        }
        isScrubbing = true
        scrubProgress = progress
        prepareSeekWarmupIfNeeded(progress)
    }

    private func handleDragEnded(locationX: CGFloat, width: CGFloat) {
        guard canInteractWithPlayer else {
            resetScrubState()
            return
        }
        isScrubbing = false
        Haptics.light()
        seek(to: progress(at: locationX, in: width), beginsInteraction: false)
    }

    func progress(at locationX: CGFloat, in width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Self.clamped(Double(locationX / width))
    }

    func seek(to progress: Double, beginsInteraction: Bool = true) {
        guard canInteractWithPlayer else { return }
        let clampedProgress = Self.clamped(progress)
        scrubProgress = clampedProgress
        prepareSeekWarmupIfNeeded(clampedProgress, force: true)
        if beginsInteraction {
            playerViewModel.beginUserScrubInteraction(source: .pinnedProgress)
        }
        playerViewModel.seekAfterSliderCommit(to: clampedProgress)
        lastPreparedProgress = -1
    }

    func prepareSeekWarmupIfNeeded(_ progress: Double, force: Bool = false) {
        guard canInteractWithPlayer else { return }
        let clampedProgress = Self.clamped(progress)
        guard force || abs(clampedProgress - lastPreparedProgress) >= 0.008 else { return }
        lastPreparedProgress = clampedProgress
        onPrepareSeek(clampedProgress)
    }

    private func resetScrubState() {
        isScrubbing = false
        lastPreparedProgress = -1
    }

    static func clamped(_ progress: Double) -> Double {
        min(max(progress, 0), 1)
    }
}

extension VideoDetailPinnedProgressBar {
    static func clamped(_ progress: Double) -> Double {
        VideoDetailPinnedProgressBarActions.clamped(progress)
    }
}

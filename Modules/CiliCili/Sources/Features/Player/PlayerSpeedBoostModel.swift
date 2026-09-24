import Combine
import QuartzCore
import SwiftUI

enum PlayerSpeedBoostPhase: Equatable {
    case idle
    case boosting
    case restoring
}

enum PlayerSpeedBoostEndReason: String {
    case gestureEnded
    case supersededBySeek
    case systemInterrupted
    case background
    case disappear
    case playerChanged
    case terminated

    var isInterruption: Bool {
        self != .gestureEnded
    }

    var shouldStabilizePlayback: Bool {
        self == .gestureEnded
    }

    var shouldShowPlaybackControls: Bool {
        self == .gestureEnded
    }
}

nonisolated enum PlayerSpeedBoostPolicy {
    enum RejectionReason: String, Equatable {
        case terminated
        case live
        case paused
        case alreadyAtMaximumRate
    }

    static func rejectionReason(
        isTerminated: Bool,
        isLiveStream: Bool,
        isPlaying: Bool,
        currentRate: BiliPlaybackRate
    ) -> RejectionReason? {
        if isTerminated { return .terminated }
        if isLiveStream { return .live }
        if !isPlaying { return .paused }
        if currentRate == .x20 { return .alreadyAtMaximumRate }
        return nil
    }
}

@MainActor
final class PlayerSpeedBoostModel: ObservableObject {
    @Published private(set) var phase: PlayerSpeedBoostPhase = .idle
    @Published private(set) var displayedRate: BiliPlaybackRate = .x20

    private var state: PlayerSpeedBoostState?
    private weak var boostedPlayerViewModel: PlayerStateViewModel?
    private var restoreTransitionTask: Task<Void, Never>?
    private var restoreTransitionGeneration = 0
    private let transitionDurationNanoseconds: UInt64 = 140_000_000

    var isIndicatorVisible: Bool {
        phase != .idle
    }

    @discardableResult
    func beginIfNeeded(
        playerViewModel: PlayerStateViewModel,
        isSurfacePlaying: Bool,
        hidePlaybackControls: () -> Void
    ) -> Bool {
        guard state == nil else { return phase == .boosting }
        let isPlaying = isSurfacePlaying || playerViewModel.isPlaying
        if let rejection = PlayerSpeedBoostPolicy.rejectionReason(
            isTerminated: playerViewModel.isTerminated,
            isLiveStream: playerViewModel.isLiveStream,
            isPlaying: isPlaying,
            currentRate: playerViewModel.playbackRate
        ) {
            playerViewModel.recordSpeedBoostMetric("event=ignored reason=\(rejection.rawValue)")
            return false
        }

        restoreTransitionTask?.cancel()
        restoreTransitionTask = nil
        restoreTransitionGeneration &+= 1
        let previousRate = playerViewModel.playbackRate
        let beganAt = CACurrentMediaTime()
        state = PlayerSpeedBoostState(
            restoredRate: previousRate,
            beganAt: beganAt
        )
        boostedPlayerViewModel = playerViewModel
        displayedRate = .x20
        setPhase(.boosting)
        Haptics.medium()
        hidePlaybackControls()
        playerViewModel.setPlaybackRate(.x20)
        let rateElapsed = PlayerMetricsLog.elapsedMilliseconds(since: beganAt)
        playerViewModel.recordSpeedBoostMetric(
            "event=begin phase=boosting restore=\(previousRate.title) beginToRate=\(String(format: "%.0fms", rateElapsed))"
        )
        return true
    }

    func end(
        reason: PlayerSpeedBoostEndReason,
        playerViewModel: PlayerStateViewModel,
        showPlaybackControls: () -> Void
    ) {
        guard let state else { return }
        self.state = nil
        let boostedPlayerViewModel = self.boostedPlayerViewModel ?? playerViewModel
        self.boostedPlayerViewModel = nil
        let releasedAt = CACurrentMediaTime()
        let holdElapsed = PlayerMetricsLog.elapsedMilliseconds(since: state.beganAt)
        displayedRate = state.restoredRate
        setPhase(.restoring)

        guard !boostedPlayerViewModel.isTerminated else {
            boostedPlayerViewModel.recordSpeedBoostMetric(
                "event=end phase=restoring reason=\(reason.rawValue) interrupted=true hold=\(String(format: "%.0fms", holdElapsed)) restoreSkipped=terminated"
            )
            scheduleIdleTransition()
            return
        }
        boostedPlayerViewModel.setPlaybackRate(state.restoredRate)
        let restoreElapsed = PlayerMetricsLog.elapsedMilliseconds(since: releasedAt)
        boostedPlayerViewModel.recordSpeedBoostMetric(
            "event=end phase=restoring reason=\(reason.rawValue) interrupted=\(reason.isInterruption) hold=\(String(format: "%.0fms", holdElapsed)) releaseToRestore=\(String(format: "%.0fms", restoreElapsed)) restore=\(state.restoredRate.title)"
        )
        if reason.shouldStabilizePlayback {
            boostedPlayerViewModel.stabilizePlaybackAfterSpeedBoost(
                restoredRate: state.restoredRate,
                reason: reason.rawValue
            )
        }
        if reason.shouldShowPlaybackControls {
            showPlaybackControls()
        }
        scheduleIdleTransition()
    }

    private func scheduleIdleTransition() {
        restoreTransitionTask?.cancel()
        restoreTransitionGeneration &+= 1
        let generation = restoreTransitionGeneration
        restoreTransitionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: self?.transitionDurationNanoseconds ?? 0)
            guard let self,
                  !Task.isCancelled,
                  self.restoreTransitionGeneration == generation,
                  self.state == nil
            else { return }
            self.restoreTransitionTask = nil
            self.setPhase(.idle)
        }
    }

    private func setPhase(_ phase: PlayerSpeedBoostPhase) {
        withAnimation(.easeInOut(duration: 0.14)) {
            self.phase = phase
        }
    }
}

private struct PlayerSpeedBoostState: Equatable {
    let restoredRate: BiliPlaybackRate
    let beganAt: CFTimeInterval
}

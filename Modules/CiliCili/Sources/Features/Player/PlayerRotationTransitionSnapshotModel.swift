import Combine
import SwiftUI

private enum PlayerRotationTransitionSnapshotTiming {
    static let releaseHoldDelayNanoseconds: UInt64 = 90_000_000
    static let stableSurfaceReleaseHoldDelayNanoseconds: UInt64 = 140_000_000
    static let seekReleaseHoldDelayNanoseconds: UInt64 = 60_000_000
    static let liveSurfaceReleaseHoldDelayNanoseconds: UInt64 = 34_000_000
    static let readinessPollDelayNanoseconds: UInt64 = 16_000_000
    static let maximumReadinessWaitNanoseconds: UInt64 = 720_000_000
    static let requiredStableReadySamples = 2
    static let requiredSeekReadySamples = 3
    static let fadeDuration: TimeInterval = 0.16
    static let stableSurfaceMaximumReadinessWaitNanoseconds: UInt64 = 1_200_000_000
    static let seekMaximumReadinessWaitNanoseconds: UInt64 = 1_500_000_000
    static let stableSurfaceFadeDuration: TimeInterval = 0.12
    static let seekFadeDuration: TimeInterval = 0
    static let liveSurfaceFadeDuration: TimeInterval = 0.12
    static let removalDelayNanoseconds: UInt64 = 110_000_000
    static let stableSurfaceRemovalDelayNanoseconds: UInt64 = 180_000_000
    static let seekRemovalDelayNanoseconds: UInt64 = 90_000_000
    static let liveSurfaceRemovalDelayNanoseconds: UInt64 = 140_000_000
}

@MainActor
final class PlayerRotationTransitionSnapshotModel: ObservableObject {
    @Published var snapshot: PlaybackTransitionSnapshot?
    @Published var opacity = 0.0

    var hasVideoFrameSnapshot: Bool {
        snapshot?.isVideoFrame == true
    }

    private var releaseTask: Task<Void, Never>?
    private var releaseGeneration = 0
    private var requiredSurfaceLayoutGeneration: Int?

    func hold(
        hasPresentedPlayback: Bool,
        surfaceLayoutGeneration: Int,
        makeSnapshot: () -> PlaybackTransitionSnapshot?
    ) {
        cancelReleaseTask()
        requiredSurfaceLayoutGeneration = surfaceLayoutGeneration + 1
        guard hasPresentedPlayback else {
            release(immediate: true)
            return
        }

        guard let nextSnapshot = makeSnapshot() else {
            if snapshot == nil {
                opacity = 0
                requiredSurfaceLayoutGeneration = nil
            }
            return
        }
        snapshot = nextSnapshot
        opacity = 1
    }

    func release(
        immediate: Bool,
        isReadyForReveal: @escaping @MainActor () -> Bool = { true },
        makeRevealSnapshot: (@MainActor () -> PlaybackTransitionSnapshot?)? = nil,
        onReleased: (@MainActor () -> Void)? = nil
    ) {
        release(
            immediate: immediate,
            holdDelayNanoseconds: PlayerRotationTransitionSnapshotTiming.releaseHoldDelayNanoseconds,
            requiredStableReadySamples: PlayerRotationTransitionSnapshotTiming.requiredStableReadySamples,
            readinessPollDelayNanoseconds: PlayerRotationTransitionSnapshotTiming.readinessPollDelayNanoseconds,
            maximumReadinessWaitNanoseconds: PlayerRotationTransitionSnapshotTiming.maximumReadinessWaitNanoseconds,
            fadeDuration: PlayerRotationTransitionSnapshotTiming.fadeDuration,
            removalDelayNanoseconds: PlayerRotationTransitionSnapshotTiming.removalDelayNanoseconds,
            isReadyForReveal: isReadyForReveal,
            makeRevealSnapshot: makeRevealSnapshot,
            onReleased: onReleased
        )
    }

    private func release(
        immediate: Bool,
        holdDelayNanoseconds: UInt64,
        requiredStableReadySamples: Int,
        readinessPollDelayNanoseconds: UInt64,
        maximumReadinessWaitNanoseconds: UInt64,
        fadeDuration: TimeInterval,
        removalDelayNanoseconds: UInt64,
        requiresReadinessBeforeFade: Bool = false,
        isReadyForReveal: @escaping @MainActor () -> Bool,
        makeRevealSnapshot: (@MainActor () -> PlaybackTransitionSnapshot?)?,
        onReleased: (@MainActor () -> Void)? = nil
    ) {
        cancelReleaseTask()
        guard snapshot != nil || opacity > 0 else {
            requiredSurfaceLayoutGeneration = nil
            onReleased?()
            return
        }
        PlayerMetricsLog.diagnostic(
            "rotationSnapshot release immediate=\(immediate) hasSnapshot=\(snapshot != nil) opacity=\(opacity)"
        )

        if immediate {
            snapshot = nil
            opacity = 0
            requiredSurfaceLayoutGeneration = nil
            onReleased?()
            return
        }

        let generation = advanceReleaseGeneration()
        releaseTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self,
                  !Task.isCancelled,
                  self.releaseGeneration == generation
            else { return }

            try? await Task.sleep(
                nanoseconds: holdDelayNanoseconds
            )
            guard !Task.isCancelled,
                  self.releaseGeneration == generation
            else { return }

            let waitStartedAt = DispatchTime.now().uptimeNanoseconds
            var stableReadySamples = 0
            var didLogExtendedWait = false
            var didForceRevealAfterWait = false
            while stableReadySamples < requiredStableReadySamples {
                let elapsed = DispatchTime.now().uptimeNanoseconds - waitStartedAt
                if elapsed >= maximumReadinessWaitNanoseconds {
                    if requiresReadinessBeforeFade {
                        didForceRevealAfterWait = true
                    }
                    break
                }
                if isReadyForReveal() {
                    stableReadySamples += 1
                } else {
                    stableReadySamples = 0
                }
                guard stableReadySamples < requiredStableReadySamples else { break }
                if requiresReadinessBeforeFade,
                   !didLogExtendedWait,
                   elapsed >= maximumReadinessWaitNanoseconds {
                    didLogExtendedWait = true
                    PlayerMetricsLog.diagnostic("rotationSnapshot release waitsForReadiness")
                }
                try? await Task.sleep(
                    nanoseconds: didLogExtendedWait
                        ? max(readinessPollDelayNanoseconds, 80_000_000)
                        : readinessPollDelayNanoseconds
                )
                guard !Task.isCancelled,
                      self.releaseGeneration == generation
                else { return }
            }
            if didForceRevealAfterWait {
                PlayerMetricsLog.diagnostic("rotationSnapshot release forcedAfterReadinessTimeout")
            }

            if let revealSnapshot = makeRevealSnapshot?() {
                self.snapshot = revealSnapshot
                self.opacity = 1
                PlayerMetricsLog.diagnostic(
                    "rotationSnapshot releaseReveal hasSnapshot=true snapshotVideo=\(revealSnapshot.isVideoFrame)"
                )
            } else {
                PlayerMetricsLog.diagnostic("rotationSnapshot releaseReveal hasSnapshot=false")
            }

            withAnimation(.linear(duration: fadeDuration)) {
                self.opacity = 0
            }
            try? await Task.sleep(
                nanoseconds: removalDelayNanoseconds
            )
            guard !Task.isCancelled,
                  self.releaseGeneration == generation
            else { return }
            self.snapshot = nil
            self.requiredSurfaceLayoutGeneration = nil
            self.clearReleaseTaskIfCurrent(generation: generation)
            onReleased?()
        }
    }

    func releaseForLiveSurfaceTransition() {
        release(immediate: false)
    }

    func releaseForStableSurfaceTransition(
        isReadyForReveal: @escaping @MainActor () -> Bool = { true },
        makeRevealSnapshot: (@MainActor () -> PlaybackTransitionSnapshot?)? = nil
    ) {
        release(
            immediate: false,
            holdDelayNanoseconds: PlayerRotationTransitionSnapshotTiming.stableSurfaceReleaseHoldDelayNanoseconds,
            requiredStableReadySamples: PlayerRotationTransitionSnapshotTiming.requiredStableReadySamples,
            readinessPollDelayNanoseconds: PlayerRotationTransitionSnapshotTiming.readinessPollDelayNanoseconds,
            maximumReadinessWaitNanoseconds: PlayerRotationTransitionSnapshotTiming.stableSurfaceMaximumReadinessWaitNanoseconds,
            fadeDuration: PlayerRotationTransitionSnapshotTiming.stableSurfaceFadeDuration,
            removalDelayNanoseconds: PlayerRotationTransitionSnapshotTiming.stableSurfaceRemovalDelayNanoseconds,
            isReadyForReveal: isReadyForReveal,
            makeRevealSnapshot: makeRevealSnapshot
        )
    }

    func releaseForSeekTransition(
        isReadyForReveal: @escaping @MainActor () -> Bool,
        makeRevealSnapshot: (@MainActor () -> PlaybackTransitionSnapshot?)? = nil,
        onReleased: (@MainActor () -> Void)? = nil
    ) {
        release(
            immediate: false,
            holdDelayNanoseconds: PlayerRotationTransitionSnapshotTiming.seekReleaseHoldDelayNanoseconds,
            requiredStableReadySamples: PlayerRotationTransitionSnapshotTiming.requiredSeekReadySamples,
            readinessPollDelayNanoseconds: PlayerRotationTransitionSnapshotTiming.readinessPollDelayNanoseconds,
            maximumReadinessWaitNanoseconds: PlayerRotationTransitionSnapshotTiming.seekMaximumReadinessWaitNanoseconds,
            fadeDuration: PlayerRotationTransitionSnapshotTiming.seekFadeDuration,
            removalDelayNanoseconds: PlayerRotationTransitionSnapshotTiming.seekRemovalDelayNanoseconds,
            requiresReadinessBeforeFade: true,
            isReadyForReveal: isReadyForReveal,
            makeRevealSnapshot: makeRevealSnapshot,
            onReleased: onReleased
        )
    }

    func releaseForAppBackgroundPlaybackRecovery(
        isReadyForReveal: @escaping @MainActor () -> Bool,
        shouldKeepWaiting: @escaping @MainActor () -> Bool,
        onReleased: (@MainActor () -> Void)? = nil
    ) {
        cancelReleaseTask()
        let generation = advanceReleaseGeneration()
        releaseTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await Task.yield()

            while shouldKeepWaiting(), !isReadyForReveal() {
                try? await Task.sleep(
                    nanoseconds: PlayerRotationTransitionSnapshotTiming.readinessPollDelayNanoseconds
                )
                guard !Task.isCancelled,
                      self.releaseGeneration == generation
                else { return }
            }

            guard shouldKeepWaiting(),
                  isReadyForReveal(),
                  !Task.isCancelled,
                  self.releaseGeneration == generation
            else {
                self.snapshot = nil
                self.opacity = 0
                self.requiredSurfaceLayoutGeneration = nil
                self.clearReleaseTaskIfCurrent(generation: generation)
                return
            }

            withAnimation(.linear(duration: PlayerRotationTransitionSnapshotTiming.stableSurfaceFadeDuration)) {
                self.opacity = 0
            }
            try? await Task.sleep(
                nanoseconds: PlayerRotationTransitionSnapshotTiming.stableSurfaceRemovalDelayNanoseconds
            )
            guard !Task.isCancelled,
                  self.releaseGeneration == generation
            else { return }
            self.snapshot = nil
            self.requiredSurfaceLayoutGeneration = nil
            self.clearReleaseTaskIfCurrent(generation: generation)
            onReleased?()
        }
    }

    func hasReachedRequiredSurfaceLayoutGeneration(_ currentGeneration: Int) -> Bool {
        guard let requiredSurfaceLayoutGeneration else { return true }
        return currentGeneration >= requiredSurfaceLayoutGeneration
    }

    @discardableResult
    private func advanceReleaseGeneration() -> Int {
        releaseGeneration += 1
        return releaseGeneration
    }

    private func cancelReleaseTask() {
        releaseTask?.cancel()
        releaseTask = nil
        advanceReleaseGeneration()
    }

    private func clearReleaseTaskIfCurrent(generation: Int) {
        guard releaseGeneration == generation else { return }
        releaseTask = nil
    }

    deinit {
        releaseTask?.cancel()
    }
}

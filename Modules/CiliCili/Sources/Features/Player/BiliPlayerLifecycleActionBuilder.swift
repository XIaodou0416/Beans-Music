import AVFoundation
import SwiftUI

struct BiliPlayerLifecycleActionBuilder {
    let viewModel: PlayerStateViewModel
    let surfaceState: PlayerSurfaceStateModel
    let playbackControlsVisibility: PlayerPlaybackControlsVisibilityModel
    let rotationTransitionSnapshotModel: PlayerRotationTransitionSnapshotModel
    let seekTransitionSnapshotModel: PlayerRotationTransitionSnapshotModel
    let appBackgroundRecoverySnapshotModel: PlayerRotationTransitionSnapshotModel
    let speedBoostModel: PlayerSpeedBoostModel
    let seekPreviewModel: PlayerSeekPreviewModel
    let playbackProgressCoordinator: PlayerPlaybackProgressCoordinator
    let progressReporter: PlayerPlaybackProgressReporter
    let progressContext: PlayerPlaybackProgressContext
    let configuration: BiliPlayerViewConfiguration
    let isPictureInPictureEnabled: Bool
    let defaultPlaybackRate: Double
    let videoGravity: AVLayerVideoGravity
    let resetPreparedScrubProgress: () -> Void

    var actions: BiliPlayerLifecycleActions {
        BiliPlayerLifecycleActions(
            onAppear: handleAppear,
            onPlayerChanged: handlePlayerChange,
            onScenePhaseChanged: handleScenePhaseChange,
            onDisappear: handleDisappear,
            onFullscreenActiveChanged: handleFullscreenActiveChange,
            onPresentationChanged: handlePresentationChange,
            onLayoutTransitionChanged: handleLayoutTransitionChange,
            onSecondaryControlsPresentedChanged: handleSecondaryControlsPresentedChange,
            onPictureInPictureEnabledChanged: handlePictureInPictureEnabledChange
        )
    }

    private var visibilityActions: BiliPlayerPlaybackControlsVisibilityActions {
        BiliPlayerPlaybackControlsVisibilityActions(
            playbackControlsVisibility: playbackControlsVisibility,
            configuration: configuration
        )
    }

    private var speedBoostActions: BiliPlayerSpeedBoostActions {
        BiliPlayerSpeedBoostActions(
            viewModel: viewModel,
            surfaceState: surfaceState,
            speedBoostModel: speedBoostModel,
            visibilityActions: visibilityActions
        )
    }

    private func handleAppear() {
        guard !viewModel.isTerminated else { return }
        guard allowsPlaybackActivation else { return }
        surfaceState.bind(viewModel: viewModel)
        visibilityActions.syncSecondaryControlsPresentation(configuration.isSecondaryControlsPresented)
        viewModel.setPictureInPictureEnabled(isPictureInPictureEnabled)
        applyVideoGravity()
        applyPlaybackDefaults()
        if viewModel.wantsAutoplay {
            viewModel.play()
        }
        progressReporter.start(clock: viewModel.playbackClock) { time in
            playbackProgressCoordinator.saveProgress(time, context: progressContext)
        }
        if configuration.isLayoutTransitioning {
            handleLayoutTransitionChange(true)
        } else {
            visibilityActions.scheduleAutoHide()
        }
    }

    private func handlePlayerChange() {
        speedBoostActions.end(reason: .playerChanged)
        seekPreviewModel.endScrub()
        seekTransitionSnapshotModel.release(immediate: true)
        rotationTransitionSnapshotModel.release(immediate: true)
        appBackgroundRecoverySnapshotModel.release(immediate: true)
        resetPreparedScrubProgress()

        surfaceState.bind(viewModel: viewModel)
        progressReporter.start(clock: viewModel.playbackClock) { time in
            playbackProgressCoordinator.saveProgress(time, context: progressContext)
        }

        guard !viewModel.isTerminated else { return }
        viewModel.setPictureInPictureEnabled(isPictureInPictureEnabled)
        if !isPictureInPictureEnabled {
            viewModel.stopPictureInPictureIfNeeded()
        }
        applyVideoGravity()
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        guard !viewModel.isTerminated else {
            speedBoostActions.end(reason: .terminated)
            return
        }
        if phase == .active {
            guard allowsPlaybackActivation else { return }
            handleActivePlaybackRecovery()
        } else if phase == .inactive {
            speedBoostActions.end(reason: .systemInterrupted)
            holdAppBackgroundRecoverySnapshotIfPossible()
        } else if phase == .background {
            speedBoostActions.end(reason: .background)
            // UIKit may send `.inactive` for Control Center and other temporary
            // overlays. Match the player lifecycle used by PiliPlus: only pause
            // after the app has actually entered the background.
            if viewModel.pauseForAppBackground() {
                // Prefer the frame captured during `.inactive`: on physical devices
                // the player layer can already be blank by `didEnterBackground`.
                holdAppBackgroundRecoverySnapshotIfPossible()
            }
            Task {
                await VideoPreloadCenter.shared.cancelAll()
            }
            playbackProgressCoordinator.saveProgressInBackground(
                currentTime: viewModel.currentTime,
                context: progressContext
            )
        }
    }

    private func handleDisappear() {
        speedBoostActions.end(reason: viewModel.isTerminated ? .terminated : .disappear)
        appBackgroundRecoverySnapshotModel.release(immediate: true)
        progressReporter.stop()
        visibilityActions.cancelAutoHide()
        rotationTransitionSnapshotModel.release(immediate: true)
        playbackProgressCoordinator.endBackgroundTaskIfNeeded()
        guard !viewModel.isTerminated else { return }
        playbackProgressCoordinator.saveProgress(viewModel.currentTime, context: progressContext)
        guard configuration.pausesOnDisappear else { return }
        guard !configuration.isFullscreenActive else { return }
        viewModel.suspendForNavigation()
    }

    private func handleFullscreenActiveChange() {
        guard !viewModel.isTerminated else { return }
        guard allowsPlaybackActivation else { return }
        if !configuration.isLayoutTransitioning {
            releaseRotationSnapshotAfterSurfaceSettle()
        }
        applyVideoGravity()
        visibilityActions.scheduleAutoHide()
    }

    private func handlePresentationChange() {
        guard !viewModel.isTerminated else { return }
        guard allowsPlaybackActivation else { return }
        applyVideoGravity()
        visibilityActions.scheduleAutoHide()
    }

    private func handleLayoutTransitionChange(_ isTransitioning: Bool) {
        guard !viewModel.isTerminated else { return }
        guard allowsPlaybackActivation else { return }
        if isTransitioning {
            if configuration.showsRotationTransitionSnapshot {
                // Even when the live surface is kept during handoff, real devices can
                // briefly expose a blank drawable while the player surface relayouts.
                // Keep a component-level video frame over the player only; do not use a
                // window-level black mask that hides the system rotation animation.
                rotationTransitionSnapshotModel.hold(
                    hasPresentedPlayback: viewModel.hasPresentedPlayback,
                    surfaceLayoutGeneration: viewModel.surfaceLayoutGeneration,
                    makeSnapshot: { [viewModel] in
                        viewModel.makeCurrentVideoFrameTransitionSnapshot()
                            ?? viewModel.makePlaybackTransitionSnapshot()
                    }
                )
            } else {
                rotationTransitionSnapshotModel.release(immediate: true)
            }
            viewModel.stabilizeSurfaceLayoutAfterGeometryChange()
            visibilityActions.cancelAutoHide()
        } else {
            viewModel.stabilizeSurfaceLayoutAfterGeometryChange()
            visibilityActions.scheduleAutoHide()
            // 旋转布局结束：等 surface 真正就绪出帧后再淡出快照（轮询 ready，连续稳定再 reveal）。
            releaseRotationSnapshotAfterSurfaceSettle()
        }
    }

    private func handleSecondaryControlsPresentedChange(_ isPresented: Bool) {
        guard !viewModel.isTerminated else { return }
        guard allowsPlaybackActivation else { return }
        visibilityActions.syncSecondaryControlsPresentation(isPresented)
    }

    private func handlePictureInPictureEnabledChange(_ isEnabled: Bool) {
        guard !viewModel.isTerminated else { return }
        viewModel.setPictureInPictureEnabled(isEnabled)
        guard !isEnabled else { return }
        viewModel.stopPictureInPictureIfNeeded()
    }

    private var allowsPlaybackActivation: Bool {
        configuration.allowsPlaybackActivation?() ?? true
    }

    private func applyVideoGravity() {
        viewModel.setVideoGravity(videoGravity)
    }

    private func applyPlaybackDefaults() {
        viewModel.setPlaybackRate(BiliPlaybackRate(rawValue: defaultPlaybackRate) ?? .x10)
    }

    private func releaseRotationSnapshotAfterSurfaceSettle() {
        rotationTransitionSnapshotModel.releaseForStableSurfaceTransition(
            isReadyForReveal: { [viewModel] in
                viewModel.validateCurrentPlaybackSurfaceReadyForReveal()
            },
            makeRevealSnapshot: { [viewModel] in
                viewModel.makeCurrentVisibleSurfaceTransitionSnapshot()
                    ?? viewModel.makeCurrentVideoFrameTransitionSnapshot()
            }
        )
    }

    private func holdAppBackgroundRecoverySnapshotIfPossible() {
        guard !viewModel.isTerminated,
              ActivePlaybackCoordinator.shared.isActive(viewModel),
              viewModel.hasPresentedPlayback
        else { return }

        appBackgroundRecoverySnapshotModel.hold(
            hasPresentedPlayback: true,
            surfaceLayoutGeneration: viewModel.surfaceLayoutGeneration,
            makeSnapshot: { [viewModel] in
                viewModel.makeCurrentVideoFrameTransitionSnapshot()
                    ?? viewModel.makePlaybackTransitionSnapshot()
            }
        )
    }

    private func handleActivePlaybackRecovery() {
        let shouldHandlePictureInPicture = isPictureInPictureEnabled
        let canActivatePlayback = allowsPlaybackActivation
        let appBackgroundRecoverySnapshotModel = appBackgroundRecoverySnapshotModel
        if viewModel.isAwaitingAppBackgroundSurfaceRecovery {
            // The global application delegate can pause playback even when this
            // SwiftUI host misses the preceding inactive notification. The engine
            // keeps the last valid frame, so establish the visual hold before play.
            holdAppBackgroundRecoverySnapshotIfPossible()
        }
        Task { @MainActor [viewModel, appBackgroundRecoverySnapshotModel] in
            guard !viewModel.isTerminated else { return }
            guard canActivatePlayback else { return }
            if shouldHandlePictureInPicture {
                let didRestorePictureInPicture = await viewModel.restoreInlinePlaybackFromPictureInPictureIfNeeded()
                if didRestorePictureInPicture {
                    appBackgroundRecoverySnapshotModel.releaseForStableSurfaceTransition(
                        isReadyForReveal: {
                            !viewModel.isPictureInPictureActive
                        }
                    )
                    return
                }
                if viewModel.isPictureInPictureActive {
                    return
                }
            }
            if viewModel.prepareStoppedPlaybackAfterAppBackgroundIfNeeded() {
                appBackgroundRecoverySnapshotModel.releaseForAppBackgroundPlaybackRecovery(
                    isReadyForReveal: {
                        viewModel.isStoppedAppBackgroundSurfaceRecoveryReadyForReveal()
                    },
                    shouldKeepWaiting: {
                        !viewModel.isTerminated
                            && viewModel.errorMessage == nil
                            && viewModel.isAwaitingAppBackgroundSurfaceRecovery
                            && ActivePlaybackCoordinator.shared.isActive(viewModel)
                    },
                    onReleased: {
                        viewModel.finishAppBackgroundSurfaceRecoveryReveal()
                    }
                )
                return
            }
            let didResume = viewModel.resumePlaybackAfterAppBackgroundIfNeeded()
            guard didResume else {
                // More than one foreground notification can reach the same
                // player during scene restoration. Keep a held frame while the
                // first recovery task is still waiting for a fresh drawable.
                guard !viewModel.isAwaitingAppBackgroundSurfaceRecovery else { return }
                viewModel.recoverPlaybackAfterAppResume()
                appBackgroundRecoverySnapshotModel.release(immediate: true)
                return
            }
            appBackgroundRecoverySnapshotModel.releaseForAppBackgroundPlaybackRecovery(
                isReadyForReveal: {
                    viewModel.isAppBackgroundSurfaceRecoveryReadyForReveal()
                },
                shouldKeepWaiting: {
                    !viewModel.isTerminated
                        && viewModel.errorMessage == nil
                        && viewModel.wantsAutoplay
                        && ActivePlaybackCoordinator.shared.isActive(viewModel)
                },
                onReleased: {
                    viewModel.finishAppBackgroundSurfaceRecoveryReveal()
                }
            )
        }
    }

    private func restoreInlinePlaybackFromPictureInPictureIfNeeded() {
        guard isPictureInPictureEnabled else { return }
        Task { @MainActor [viewModel] in
            _ = await viewModel.restoreInlinePlaybackFromPictureInPictureIfNeeded()
        }
    }

}

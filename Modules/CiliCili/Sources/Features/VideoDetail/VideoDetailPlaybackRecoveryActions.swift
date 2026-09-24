import Foundation
import OSLog

extension VideoDetailViewModel {
    func handlePlaybackError(_ message: String, for failedVariant: PlayVariant) {
        handlePlaybackError(message, reason: nil, for: failedVariant, source: .errorObserver)
    }

    func handlePlaybackError(
        _ message: String,
        reason: HLSBridgeFailureReason?,
        for failedVariant: PlayVariant,
        source: VideoDetailPlaybackRecoveryFailureSource = .playerCallback
    ) {
        let fallbackVariant = playbackFallbackVariant(excluding: failedVariant)
        let decisionInput = VideoDetailPlaybackRecoveryInput(
            source: source,
            message: message,
            reason: reason,
            failedVariantID: failedVariant.id,
            selectedVariantID: selectedPlayVariant?.id,
            hasFallbackVariant: fallbackVariant != nil,
            playURLIsLoading: playURLState.isLoading,
            recoveryAttemptCount: playbackRecoveryAttemptCount,
            maxRecoveryReloadAttempts: Self.playbackRecoveryReloadAttemptLimit,
            isPlaybackInvalidatedForNavigation: isPlaybackInvalidatedForNavigation,
            hasPendingNavigationInterruption: hasPendingNavigationInterruption
        )
        let decision = playbackRecoveryCoordinator.receiveFailure(decisionInput)
        recordPlaybackRecoveryDecision(
            decision,
            source: source,
            message: message,
            reason: reason,
            failedVariant: failedVariant,
            fallbackVariant: fallbackVariant
        )
        guard decision.shouldHandleFailure else { return }
        if decision.shouldMarkFailedVariant {
            failedPlayVariantIDs.insert(failedVariant.id)
        }
        if decision.shouldRefreshCDN {
            temporarilyAvoidCurrentAutomaticPlaybackCDN(
                reason: playbackCDNAvoidanceReason(reason: reason)
            )
            PlaybackCDNProbeCoordinator.shared.refreshForPlaybackPressure(libraryStore: libraryStore)
        }

        switch decision.action {
        case .ignore:
            return
        case .reloadPlayURL:
            schedulePlaybackRecoveryReload(after: message, failedVariant: failedVariant, reason: reason)
            return
        case .exhausted:
            playbackFallbackMessage = "当前线路多次恢复失败，请稍后重试或手动切换清晰度"
            return
        case .switchVariant:
            guard let fallbackVariant else {
                schedulePlaybackRecoveryReload(after: message, failedVariant: failedVariant, reason: reason)
                return
            }
            switchPlaybackToFallbackVariant(
                fallbackVariant,
                failedVariant: failedVariant,
                message: message,
                reason: reason
            )
        }
    }

    private func switchPlaybackToFallbackVariant(
        _ fallbackVariant: PlayVariant,
        failedVariant: PlayVariant,
        message: String,
        reason: HLSBridgeFailureReason?
    ) {
        let resumeTime = currentPlaybackResumeTime()
        let shouldResumePlayback = currentPlaybackIntent()
        let playbackRate = stablePlayerViewModel?.playbackRate ?? .x10
        let fallbackContext = VideoDetailPlaybackFallbackContext(
            failedVariant: failedVariant,
            fallbackVariant: fallbackVariant
        )
        PlayerMetricsLog.logger.error(
            "playbackFallback \(fallbackContext.logDescription, privacy: .public) error=\(message, privacy: .public)"
        )
        playbackFallbackMessage = fallbackContext.userMessage
        recordPlaybackRecoveryStage(
            "fallbackApplied",
            status: "done",
            attempt: playbackRecoveryAttemptCount,
            failedVariant: failedVariant,
            reason: reason,
            extraParts: fallbackContext.metricParts + [
                "resume=\(String(format: "%.2fs", resumeTime))",
                "autoplay=\(shouldResumePlayback)"
            ]
        )
        selectedPlayVariant = fallbackVariant
        updateStablePlayerViewModelIfNeeded(
            resumeTimeOverride: resumeTime,
            shouldResumePlayback: shouldResumePlayback,
            playbackRateOverride: playbackRate,
            preservesPreviousPlayerUntilFirstFrame: true
        )
    }

    private func shouldRefreshPlaybackCDN(for reason: HLSBridgeFailureReason?) -> Bool {
        VideoDetailPlaybackRecoveryCoordinator.shouldRefreshCDN(for: reason)
    }

    private func shouldReloadPlayURLForPlaybackFailure(_ reason: HLSBridgeFailureReason?) -> Bool {
        VideoDetailPlaybackRecoveryCoordinator.requiresPlayURLReload(reason)
    }

    private func playbackCDNAvoidanceReason(reason: HLSBridgeFailureReason?) -> String {
        guard let reason else { return "playbackError" }
        let statusSuffix = reason.statusCode.map { " status=\($0)" } ?? ""
        return "playbackError reason=\(reason.category.rawValue)\(statusSuffix)"
    }
}

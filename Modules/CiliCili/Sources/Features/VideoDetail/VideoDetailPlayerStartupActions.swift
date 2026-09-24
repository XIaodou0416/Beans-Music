import Foundation

extension VideoDetailViewModel {
    func updateStablePlayerViewModelIfNeeded(
        resumeTimeOverride: TimeInterval? = nil,
        shouldResumePlayback: Bool? = nil,
        playbackRateOverride: BiliPlaybackRate? = nil,
        preservesPreviousPlayerUntilFirstFrame: Bool = false,
        usesSeamlessPlaybackHandoff: Bool = false
    ) {
        guard !isPlaybackInvalidatedForNavigation else { return }
        guard let variant = selectedPlayVariant, variant.isPlayable else {
            resetStablePlayerForMissingVariant()
            return
        }
        normalizeVideoListenMode(for: variant)

        let identity = playerIdentity(for: variant)
        if applyStableIdentityResumeIfNeeded(
            identity: identity,
            resumeTimeOverride: resumeTimeOverride,
            shouldResumePlayback: shouldResumePlayback,
            playbackRateOverride: playbackRateOverride
        ) {
            return
        }

        let startupPreparation = stablePlayerStartupPreparation(
            resumeTimeOverride: resumeTimeOverride,
            shouldResumePlayback: shouldResumePlayback,
            playbackRateOverride: playbackRateOverride,
            usesSeamlessPlaybackHandoff: usesSeamlessPlaybackHandoff
        )
        preparePreviousStablePlayerForReplacement(
            startupPreparation.previousPlayer,
            preservesPreviousPlayerUntilFirstFrame: preservesPreviousPlayerUntilFirstFrame,
            keepsPreviousPlaybackActive: startupPreparation.playbackHandoffSource != nil
        )
        resetStablePlayerObserversForNewIdentity(identity)
        createAndInstallStablePlayer(
            variant: variant,
            startupPreparation: startupPreparation
        )
    }

}

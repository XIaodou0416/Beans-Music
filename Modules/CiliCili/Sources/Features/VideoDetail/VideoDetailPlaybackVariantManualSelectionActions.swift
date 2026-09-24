import Foundation

extension VideoDetailViewModel {
    func beginManualPlayVariantSelection(for variant: PlayVariant) -> UUID {
        let token = UUID()
        didSelectPlayVariantManually = true
        manuallySelectedPlayVariantQuality = variant.quality
        failedPlayVariantIDs.removeAll()
        playbackRecoveryAttemptCount = 0
        playbackRecoveryCoordinator.reset()
        lastBufferingCDNRefreshCount = 0
        cancelPlayVariantSwitchTask()
        return token
    }

    func beginPlayVariantSwitch(for variant: PlayVariant, token: UUID) {
        playVariantSwitchToken = token
        isSwitchingPlayQuality = true
        pendingPlayVariantID = variant.id
    }
}

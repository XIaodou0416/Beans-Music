import Foundation

extension VideoDetailViewModel {
    @discardableResult
    func advancePlaybackRecoveryReloadGeneration() -> Int {
        playbackRecoveryReloadGeneration += 1
        return playbackRecoveryReloadGeneration
    }

    func cancelPlaybackRecoveryReloadTask(advancesGeneration: Bool = true) {
        playbackRecoveryReloadTask?.cancel()
        playbackRecoveryReloadTask = nil
        if advancesGeneration {
            advancePlaybackRecoveryReloadGeneration()
        }
    }

    func isCurrentPlaybackRecoveryReload(
        generation: Int,
        aid: Int?,
        bvid: String,
        cid: Int?,
        failedVariantID: String,
        allowsClearedVariant: Bool = false
    ) -> Bool {
        !isPlaybackInvalidatedForNavigation
            && playbackRecoveryReloadGeneration == generation
            && selectedCID == cid
            && (selectedPlayVariant?.id == failedVariantID || (allowsClearedVariant && selectedPlayVariant == nil))
            && isCurrentVideoContext(aid: aid, bvid: bvid)
    }

    func clearPlaybackRecoveryReloadTaskIfCurrent(generation: Int) {
        guard playbackRecoveryReloadGeneration == generation else { return }
        playbackRecoveryReloadTask = nil
    }
}

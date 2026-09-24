import Foundation

extension VideoDetailViewModel {
    func cancelPlayVariantSwitchTask() {
        playVariantSwitchTask?.cancel()
        playVariantSwitchTask = nil
        playVariantSwitchToken = nil
        pendingPlayVariantID = nil
        isSwitchingPlayQuality = false
    }
}

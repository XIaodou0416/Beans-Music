import Foundation

extension VideoDetailViewModel {
    func cancelSponsorBlockTask(advancesGeneration: Bool = true) {
        sponsorBlockTask?.cancel()
        sponsorBlockTask = nil
        if advancesGeneration {
            advanceSponsorBlockGeneration()
        }
    }

    @discardableResult
    func advanceSponsorBlockGeneration() -> Int {
        sponsorBlockGeneration += 1
        return sponsorBlockGeneration
    }

    func clearSponsorBlockTaskIfCurrent(generation: Int) {
        guard sponsorBlockGeneration == generation else { return }
        sponsorBlockTask = nil
    }
}

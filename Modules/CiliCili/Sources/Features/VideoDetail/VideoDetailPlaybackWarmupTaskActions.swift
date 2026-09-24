import Foundation

extension VideoDetailViewModel {
    func cancelHLSRenditionPrebuildTask(advancesGeneration: Bool = true) {
        hlsRenditionPrebuildTask?.cancel()
        hlsRenditionPrebuildTask = nil
        if advancesGeneration {
            advanceHLSRenditionPrebuildGeneration()
        }
    }

    @discardableResult
    func advanceHLSRenditionPrebuildGeneration() -> Int {
        hlsRenditionPrebuildGeneration += 1
        return hlsRenditionPrebuildGeneration
    }

    func clearHLSRenditionPrebuildTaskIfCurrent(generation: Int) {
        guard hlsRenditionPrebuildGeneration == generation else { return }
        hlsRenditionPrebuildTask = nil
    }
}

import Foundation

extension VideoDetailViewModel {
    func cancelUploaderInteractionTask(advancesGeneration: Bool = true) {
        uploaderInteractionTask?.cancel()
        uploaderInteractionTask = nil
        if advancesGeneration {
            advanceUploaderInteractionLoadGeneration()
        }
    }

    @discardableResult
    func advanceUploaderInteractionLoadGeneration() -> Int {
        uploaderInteractionLoadGeneration += 1
        return uploaderInteractionLoadGeneration
    }

    func clearUploaderInteractionTaskIfCurrent(identity: String, generation: Int) {
        guard uploaderInteractionLoadIdentity == identity,
              uploaderInteractionLoadGeneration == generation
        else { return }
        uploaderInteractionTask = nil
    }
}

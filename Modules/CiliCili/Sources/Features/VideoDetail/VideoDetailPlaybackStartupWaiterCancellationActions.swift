import Foundation

extension VideoDetailViewModel {
    func cancelPlaybackStartupWaiter(_ id: UUID) {
        if let waiter = playbackStartupWaiters.removeValue(forKey: id) {
            waiter.continuation.resume(returning: nil)
        }
    }
}

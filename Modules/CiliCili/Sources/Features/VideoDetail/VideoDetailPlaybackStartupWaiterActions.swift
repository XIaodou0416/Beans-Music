import Foundation

extension VideoDetailViewModel {
    func beginPlaybackStartupAttempt() {
        if stablePlayerViewModel?.hasPresentedPlayback == true {
            finishPlaybackStartupWaiters(with: .firstFrame)
        } else {
            playbackStartupRelease = nil
        }
    }

    func finishPlaybackStartupWaiters(with release: VideoDetailPlaybackStartupRelease?) {
        playbackStartupRelease = release
        guard !playbackStartupWaiters.isEmpty else { return }

        let waiters = playbackStartupWaiters
        playbackStartupWaiters.removeAll()
        for waiter in waiters.values {
            switch release {
            case .firstFrame:
                waiter.continuation.resume(returning: .firstFrame)
            case .failed:
                waiter.continuation.resume(returning: waiter.acceptsFailure ? .failed : nil)
            case .none:
                waiter.continuation.resume(returning: nil)
            }
        }
    }

}

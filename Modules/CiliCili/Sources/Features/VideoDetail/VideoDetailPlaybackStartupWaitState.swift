import Foundation

struct VideoDetailPlaybackStartupWaitState {
    var release: VideoDetailPlaybackStartupRelease?
    var waiters: [UUID: VideoDetailPlaybackStartupWaiter] = [:]
}

extension VideoDetailViewModel {
    var playbackStartupRelease: VideoDetailPlaybackStartupRelease? {
        get { playbackStartupWaitState.release }
        set { playbackStartupWaitState.release = newValue }
    }

    var playbackStartupWaiters: [UUID: VideoDetailPlaybackStartupWaiter] {
        get { playbackStartupWaitState.waiters }
        set { playbackStartupWaitState.waiters = newValue }
    }
}

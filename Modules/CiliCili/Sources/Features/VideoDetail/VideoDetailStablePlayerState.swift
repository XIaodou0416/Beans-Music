import Combine

struct VideoDetailStablePlayerState {
    var identity: String?
    let playbackSession = PlaybackSession()
    var errorCancellable: AnyCancellable?
    var firstFrameCancellable: AnyCancellable?
}

extension VideoDetailViewModel {
    var stablePlayerIdentity: String? {
        get { stablePlayerState.identity }
        set { stablePlayerState.identity = newValue }
    }

    var playbackSession: PlaybackSession {
        stablePlayerState.playbackSession
    }

    var stablePlayerErrorCancellable: AnyCancellable? {
        get { stablePlayerState.errorCancellable }
        set { stablePlayerState.errorCancellable = newValue }
    }

    var stablePlayerFirstFrameCancellable: AnyCancellable? {
        get { stablePlayerState.firstFrameCancellable }
        set { stablePlayerState.firstFrameCancellable = newValue }
    }
}

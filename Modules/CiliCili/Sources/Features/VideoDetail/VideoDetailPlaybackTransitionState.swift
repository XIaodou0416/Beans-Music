import Foundation

struct VideoDetailPlaybackTransitionState {
    var playerViewModel: PlayerStateViewModel?
    var snapshot: PlaybackTransitionSnapshot?
    var fallbackCoverURL: URL?
    var opacity = 0.0
    var releaseTask: Task<Void, Never>?
    var releaseGeneration = 0
}

extension VideoDetailViewModel {
    var playbackTransitionPlayerViewModel: PlayerStateViewModel? {
        get { playbackTransitionState.playerViewModel }
        set {
            playbackTransitionState.playerViewModel = newValue
            scheduleRenderStoreSync(.playerIdentity)
        }
    }

    var playbackTransitionSnapshot: PlaybackTransitionSnapshot? {
        get { playbackTransitionState.snapshot }
        set {
            playbackTransitionState.snapshot = newValue
            scheduleRenderStoreSync(.playerIdentity)
        }
    }

    var playbackTransitionFallbackCoverURL: URL? {
        get { playbackTransitionState.fallbackCoverURL }
        set {
            playbackTransitionState.fallbackCoverURL = newValue
            scheduleRenderStoreSync(.playerIdentity)
        }
    }

    var playbackTransitionOpacity: Double {
        get { playbackTransitionState.opacity }
        set {
            playbackTransitionState.opacity = newValue
            scheduleRenderStoreSync(.playerIdentity)
        }
    }

    var playbackTransitionReleaseTask: Task<Void, Never>? {
        get { playbackTransitionState.releaseTask }
        set { playbackTransitionState.releaseTask = newValue }
    }

    var playbackTransitionReleaseGeneration: Int {
        get { playbackTransitionState.releaseGeneration }
        set { playbackTransitionState.releaseGeneration = newValue }
    }
}

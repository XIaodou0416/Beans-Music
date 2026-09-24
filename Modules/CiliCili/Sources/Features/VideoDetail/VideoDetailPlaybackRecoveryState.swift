import Foundation

struct VideoDetailPlaybackRecoveryState {
    var didSelectPlayVariantManually = false
    var manuallySelectedPlayVariantQuality: Int?
    var failedPlayVariantIDs = Set<String>()
    var playbackRecoveryAttemptCount = 0
    var playbackRecoveryCoordinator = VideoDetailPlaybackRecoveryCoordinator()
    var lastBufferingCDNRefreshCount = 0
    var playbackRecoveryReloadTask: Task<Void, Never>?
    var playbackRecoveryReloadGeneration = 0
    var bufferingCDNRefreshTask: Task<Void, Never>?
    var bufferingCDNRefreshGeneration = 0
}

extension VideoDetailViewModel {
    var didSelectPlayVariantManually: Bool {
        get { playbackRecoveryState.didSelectPlayVariantManually }
        set { playbackRecoveryState.didSelectPlayVariantManually = newValue }
    }

    var manuallySelectedPlayVariantQuality: Int? {
        get { playbackRecoveryState.manuallySelectedPlayVariantQuality }
        set { playbackRecoveryState.manuallySelectedPlayVariantQuality = newValue }
    }

    var failedPlayVariantIDs: Set<String> {
        get { playbackRecoveryState.failedPlayVariantIDs }
        set { playbackRecoveryState.failedPlayVariantIDs = newValue }
    }

    var playbackRecoveryAttemptCount: Int {
        get { playbackRecoveryState.playbackRecoveryAttemptCount }
        set { playbackRecoveryState.playbackRecoveryAttemptCount = newValue }
    }

    var playbackRecoveryCoordinator: VideoDetailPlaybackRecoveryCoordinator {
        get { playbackRecoveryState.playbackRecoveryCoordinator }
        set { playbackRecoveryState.playbackRecoveryCoordinator = newValue }
    }

    var lastBufferingCDNRefreshCount: Int {
        get { playbackRecoveryState.lastBufferingCDNRefreshCount }
        set { playbackRecoveryState.lastBufferingCDNRefreshCount = newValue }
    }

    var playbackRecoveryReloadTask: Task<Void, Never>? {
        get { playbackRecoveryState.playbackRecoveryReloadTask }
        set { playbackRecoveryState.playbackRecoveryReloadTask = newValue }
    }

    var playbackRecoveryReloadGeneration: Int {
        get { playbackRecoveryState.playbackRecoveryReloadGeneration }
        set { playbackRecoveryState.playbackRecoveryReloadGeneration = newValue }
    }

    var bufferingCDNRefreshTask: Task<Void, Never>? {
        get { playbackRecoveryState.bufferingCDNRefreshTask }
        set { playbackRecoveryState.bufferingCDNRefreshTask = newValue }
    }

    var bufferingCDNRefreshGeneration: Int {
        get { playbackRecoveryState.bufferingCDNRefreshGeneration }
        set { playbackRecoveryState.bufferingCDNRefreshGeneration = newValue }
    }
}

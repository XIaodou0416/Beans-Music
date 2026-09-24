import Foundation

struct VideoDetailPlaybackNavigationState {
    var isPlaybackInvalidatedForNavigation = false
    var isPlaybackTerminatedForNavigation = false
    var playbackStopTask: Task<Void, Never>?
    var shouldResumePlaybackAfterCancelledNavigation = false
    var pendingNavigationResumeTime: TimeInterval?
    var hasPendingNavigationInterruption = false
}

extension VideoDetailViewModel {
    var isPlaybackInvalidatedForNavigation: Bool {
        get { navigationState.isPlaybackInvalidatedForNavigation }
        set { navigationState.isPlaybackInvalidatedForNavigation = newValue }
    }

    var isPlaybackTerminatedForNavigation: Bool {
        get { navigationState.isPlaybackTerminatedForNavigation }
        set { navigationState.isPlaybackTerminatedForNavigation = newValue }
    }

    var canActivatePlaybackAfterNavigation: Bool {
        !isPlaybackTerminatedForNavigation && !isPlaybackInvalidatedForNavigation
    }

    var shouldResumePlaybackAfterCancelledNavigation: Bool {
        get { navigationState.shouldResumePlaybackAfterCancelledNavigation }
        set { navigationState.shouldResumePlaybackAfterCancelledNavigation = newValue }
    }

    var pendingNavigationResumeTime: TimeInterval? {
        get { navigationState.pendingNavigationResumeTime }
        set { navigationState.pendingNavigationResumeTime = newValue }
    }

    var hasPendingNavigationInterruption: Bool {
        get { navigationState.hasPendingNavigationInterruption }
        set { navigationState.hasPendingNavigationInterruption = newValue }
    }
}

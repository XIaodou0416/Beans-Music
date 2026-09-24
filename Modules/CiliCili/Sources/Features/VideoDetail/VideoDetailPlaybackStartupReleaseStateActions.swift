import Foundation

extension VideoDetailViewModel {
    func immediatePlaybackStartupRelease(acceptsFailure: Bool) -> VideoDetailPlaybackStartupRelease? {
        if stablePlayerViewModel?.hasPresentedPlayback == true || playbackStartupRelease == .firstFrame {
            return .firstFrame
        }
        if isPlaybackStartupFailed {
            return acceptsFailure ? .failed : nil
        }
        guard let release = playbackStartupRelease else { return nil }
        switch release {
        case .firstFrame:
            return .firstFrame
        case .failed:
            return acceptsFailure ? .failed : nil
        }
    }

    var isPlaybackStartupFailed: Bool {
        stablePlayerViewModel?.errorMessage != nil || isPlayURLFailed
    }

    var isPlayURLFailed: Bool {
        if case .failed = playURLState {
            return true
        }
        return false
    }
}

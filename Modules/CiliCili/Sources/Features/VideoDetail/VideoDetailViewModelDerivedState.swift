import Foundation

extension VideoDetailViewModel {
    var playURLLoadTimeoutNanoseconds: UInt64 {
        PlaybackEnvironment.current.shouldPreferConservativePlayback
            ? 3_800_000_000
            : 4_800_000_000
    }

    var hasMoreComments: Bool {
        !commentsEnd
    }

    var shouldShowRelatedSectionShell: Bool {
        state != .idle || playURLState != .idle || relatedState != .idle || !related.isEmpty
    }

    var shouldUseCompactRelatedArtwork: Bool {
        let environment = PlaybackEnvironment.current
        return environment.shouldPreferConservativePlayback
            || playbackAdaptationProfile.shouldThrottleBackgroundPreload
    }

    var shouldShowEmptyCommentsState: Bool {
        guard didCompleteInitialCommentLoad,
              comments.isEmpty,
              commentState == .loaded
        else { return false }
        if let replyCount = detail.stat?.reply {
            return replyCount == 0 && commentsEnd
        }
        return commentsEnd
    }

    var shouldShowCommentReloadPrompt: Bool {
        didCompleteInitialCommentLoad
            && comments.isEmpty
            && commentState == .loaded
            && !shouldShowEmptyCommentsState
    }

    var shouldAutoLoadInlineComments: Bool {
        if !related.isEmpty {
            return true
        }
        switch relatedState {
        case .loaded, .failed:
            return true
        case .idle, .loading:
            return false
        }
    }
}

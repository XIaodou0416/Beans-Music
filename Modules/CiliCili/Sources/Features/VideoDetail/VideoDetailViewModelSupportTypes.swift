import Foundation

nonisolated enum VideoDetailInteractionMutationKind: Equatable, Sendable {
    case like
    case coin
    case favorite
    case follow
}

nonisolated enum VideoDetailPlaybackHistorySelectionPolicy {
    static func preservesManualPage(manuallySelectedCID: Int?, currentCID: Int) -> Bool {
        manuallySelectedCID == currentCID
    }
}

nonisolated struct VideoDetailInteractionMutationConfirmation: Equatable, Sendable {
    let kind: VideoDetailInteractionMutationKind
    let state: VideoInteractionState

    func reconciling(_ refreshedState: VideoInteractionState) -> VideoInteractionState {
        var reconciledState = refreshedState
        switch kind {
        case .like:
            reconciledState.isLiked = state.isLiked
        case .coin:
            reconciledState.coinCount = max(refreshedState.coinCount, state.coinCount)
        case .favorite:
            reconciledState.isFavorited = state.isFavorited
        case .follow:
            reconciledState.isFollowing = state.isFollowing
        }
        return reconciledState
    }
}

nonisolated enum VideoDetailInteractionReliabilityPolicy {
    static func shouldVerifyAmbiguousMutationResult(after error: Error) -> Bool {
        if error is DecodingError {
            return true
        }
        if let apiError = error as? BiliAPIError {
            switch apiError {
            case .emptyData, .missingPayload:
                return true
            case .api(let code, _):
                return code == -500 || (500...599).contains(code)
            default:
                return false
            }
        }
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .networkConnectionLost,
             .notConnectedToInternet,
             .cannotLoadFromNetwork,
             .badServerResponse,
             .resourceUnavailable:
            return true
        default:
            return false
        }
    }
}

enum VideoDetailPlaybackStartupRelease {
    case firstFrame
    case failed
}

struct VideoDetailPlaybackStartupWaiter {
    let acceptsFailure: Bool
    let continuation: CheckedContinuation<VideoDetailPlaybackStartupRelease?, Never>
}

struct VideoDetailSeekWarmupPlan {
    let variants: [PlayVariant]
    let variantLimit: Int
    let pressureReason: String
}

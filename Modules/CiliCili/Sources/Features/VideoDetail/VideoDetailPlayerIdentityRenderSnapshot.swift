import Foundation

struct VideoDetailPlayerIdentityRenderSnapshot: Equatable {
    var playerViewModel: PlayerStateViewModel?
    var transitionSnapshot: PlaybackTransitionSnapshot?
    var transitionFallbackCoverURL: URL?
    var transitionPlayerOpacity = 0.0

    static func == (
        lhs: VideoDetailPlayerIdentityRenderSnapshot,
        rhs: VideoDetailPlayerIdentityRenderSnapshot
    ) -> Bool {
        isSamePlayer(lhs.playerViewModel, rhs.playerViewModel)
            && isSameSnapshot(lhs.transitionSnapshot, rhs.transitionSnapshot)
            && lhs.transitionFallbackCoverURL == rhs.transitionFallbackCoverURL
            && abs(lhs.transitionPlayerOpacity - rhs.transitionPlayerOpacity) < 0.001
    }

    private static func isSamePlayer(_ lhs: PlayerStateViewModel?, _ rhs: PlayerStateViewModel?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            return true
        case let (.some(left), .some(right)):
            return left === right
        default:
            return false
        }
    }

    private static func isSameSnapshot(_ lhs: PlaybackTransitionSnapshot?, _ rhs: PlaybackTransitionSnapshot?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            return true
        case let (.some(left), .some(right)):
            return left.image === right.image
        default:
            return false
        }
    }
}

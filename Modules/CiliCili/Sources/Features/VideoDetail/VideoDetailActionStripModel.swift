import SwiftUI

struct VideoDetailActionStripModel: Equatable {
    let owner: VideoOwner?
    let canFavorite: Bool
    let shareURL: URL?
    let shareSubject: String
    let shareMessage: String
    let contentWidth: CGFloat
    let isFollowing: Bool
    let isLiked: Bool
    let isCoined: Bool
    let isFavorited: Bool
    let coinCount: Int
    let isMutatingLike: Bool
    let isMutatingCoin: Bool
    let isMutatingFavorite: Bool
    let isMutatingFollow: Bool
}

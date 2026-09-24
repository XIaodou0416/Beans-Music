import SwiftUI

struct HomeFeedContentActions {
    let onVideoSelect: ((VideoItem) -> Void)?
    let onVideoTap: (VideoItem) -> Void
    let onVideoPress: (VideoItem) -> Void
    let onCardAppear: (VideoItem, Int) -> Void
    let onCardDisappear: (VideoItem) -> Void
    let onLoadMore: (VideoItem) async -> Void
    let onRefreshFromLastSeenMarker: () async -> Void
}

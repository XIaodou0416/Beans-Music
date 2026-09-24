import SwiftUI

struct HomeFeedContentSection: View {
    let metrics: HomeFeedLayoutMetrics
    let cells: [HomeVideoCellModel]
    let lastSeenMarkerIndex: Int?
    let isLoadingMore: Bool
    let actions: HomeFeedContentActions

    var body: some View {
        HomeFeedContentSectionResolver(
            metrics: metrics,
            cells: cells,
            lastSeenMarkerIndex: lastSeenMarkerIndex,
            isLoadingMore: isLoadingMore,
            actions: actions
        )
    }
}

import SwiftUI

struct HomeFeedContentSectionResolver: View {
    let metrics: HomeFeedLayoutMetrics
    let cells: [HomeVideoCellModel]
    let lastSeenMarkerIndex: Int?
    let isLoadingMore: Bool
    let actions: HomeFeedContentActions

    var body: some View {
        Group {
            if cells.isEmpty {
                HomeFeedSkeletonSection(metrics: metrics)
            } else if metrics.mode.isDoubleColumn {
                HomeFeedDoubleColumnContent(
                    metrics: metrics,
                    cells: cells,
                    lastSeenMarkerIndex: lastSeenMarkerIndex,
                    isLoadingMore: isLoadingMore,
                    actions: actions
                )
            } else {
                HomeFeedSingleColumnContent(
                    metrics: metrics,
                    cells: cells,
                    lastSeenMarkerIndex: lastSeenMarkerIndex,
                    isLoadingMore: isLoadingMore,
                    actions: actions
                )
            }
        }
    }
}

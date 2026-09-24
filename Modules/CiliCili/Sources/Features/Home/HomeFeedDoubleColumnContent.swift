import SwiftUI

struct HomeFeedDoubleColumnContent: View {
    let metrics: HomeFeedLayoutMetrics
    let cells: [HomeVideoCellModel]
    let lastSeenMarkerIndex: Int?
    let isLoadingMore: Bool
    let actions: HomeFeedContentActions

    private var loadMoreTriggerCellID: String? {
        cells.last?.id
    }

    private var visibleLastSeenMarkerIndex: Int? {
        guard let lastSeenMarkerIndex,
              lastSeenMarkerIndex > 0,
              lastSeenMarkerIndex < cells.count
        else { return nil }
        return lastSeenMarkerIndex
    }

    var body: some View {
        LazyVGrid(columns: metrics.feedColumns, spacing: metrics.feedSpacing) {
            ForEach(cells) { cell in
                if visibleLastSeenMarkerIndex == cell.index {
                    HomeFeedLastSeenMarkerCard(
                        metrics: metrics,
                        action: actions.onRefreshFromLastSeenMarker
                    )
                }

                HomeFeedDoubleColumnCard(
                    metrics: metrics,
                    cell: cell,
                    loadMoreTriggerCellID: loadMoreTriggerCellID,
                    actions: actions
                )
            }

            if isLoadingMore {
                HomeFeedDoubleColumnLoadingMorePlaceholder(columnCount: metrics.feedColumns.count)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, metrics.feedHorizontalPadding)
    }
}

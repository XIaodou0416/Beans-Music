import SwiftUI

struct HomeFeedDoubleColumnCard: View {
    let metrics: HomeFeedLayoutMetrics
    let cell: HomeVideoCellModel
    let loadMoreTriggerCellID: String?
    let actions: HomeFeedContentActions

    var body: some View {
        HomeFeedVideoCardButton(
            metrics: metrics,
            video: cell.video,
            display: cell.display,
            actions: actions
        )
        .homeFeedCardLifecycle(
            cell: cell,
            loadMoreTriggerCellID: loadMoreTriggerCellID,
            actions: actions
        )
    }
}

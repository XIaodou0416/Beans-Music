import SwiftUI

struct HomeFeedSingleColumnCard: View {
    let metrics: HomeFeedLayoutMetrics
    let cell: HomeVideoCellModel
    let isFirstCell: Bool
    let loadMoreTriggerCellID: String?
    let actions: HomeFeedContentActions

    var body: some View {
        HomeFeedVideoCardButton(
            metrics: metrics,
            video: cell.video,
            display: cell.display,
            actions: actions
        )
        .padding(.top, metrics.mode == .borderedSingleColumn ? 6 : (isFirstCell ? 0 : 9))
        .padding(.bottom, metrics.mode == .borderedSingleColumn ? 6 : 14)
        .homeFeedCardLifecycle(
            cell: cell,
            loadMoreTriggerCellID: loadMoreTriggerCellID,
            actions: actions
        )
    }
}

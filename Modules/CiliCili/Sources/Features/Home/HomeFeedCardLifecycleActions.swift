import Foundation

struct HomeFeedCardLifecycleActions {
    let cell: HomeVideoCellModel
    let loadMoreTriggerCellID: String?
    let actions: HomeFeedContentActions

    var shouldAttachLoadMoreTask: Bool {
        cell.id == loadMoreTriggerCellID
    }

    func handleAppear() {
        actions.onCardAppear(cell.video, cell.index)
    }

    func handleDisappear() {
        actions.onCardDisappear(cell.video)
    }

    func loadMoreIfNeeded() async {
        await actions.onLoadMore(cell.video)
    }
}

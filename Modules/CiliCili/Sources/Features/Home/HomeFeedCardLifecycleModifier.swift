import SwiftUI

private struct HomeFeedCardLifecycleModifier: ViewModifier {
    let cell: HomeVideoCellModel
    let lifecycleActions: HomeFeedCardLifecycleActions

    func body(content: Content) -> some View {
        content
            .onAppear(perform: lifecycleActions.handleAppear)
            .onDisappear(perform: lifecycleActions.handleDisappear)
            .homeLoadMoreTask(if: lifecycleActions.shouldAttachLoadMoreTask, id: cell.id) {
                await lifecycleActions.loadMoreIfNeeded()
            }
    }
}

extension View {
    func homeFeedCardLifecycle(
        cell: HomeVideoCellModel,
        loadMoreTriggerCellID: String?,
        actions: HomeFeedContentActions
    ) -> some View {
        modifier(
            HomeFeedCardLifecycleModifier(
                cell: cell,
                lifecycleActions: HomeFeedCardLifecycleActions(
                    cell: cell,
                    loadMoreTriggerCellID: loadMoreTriggerCellID,
                    actions: actions
                )
            )
        )
    }
}

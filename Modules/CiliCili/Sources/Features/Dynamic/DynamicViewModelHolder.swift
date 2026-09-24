import Combine

@MainActor
final class DynamicViewModelHolder: ObservableObject {
    @Published var viewModel: DynamicViewModel?
    private var cancellable: AnyCancellable?
    private var snapshotRefreshTask: Task<Void, Never>?
    private var lastSnapshot: DynamicRenderSnapshot?

    func configure(api: BiliAPIClient, libraryStore: LibraryStore, sessionStore: SessionStore) {
        guard viewModel == nil else { return }
        installViewModel(api: api, libraryStore: libraryStore, sessionStore: sessionStore)
    }

    func reconfigure(api: BiliAPIClient, libraryStore: LibraryStore, sessionStore: SessionStore) {
        snapshotRefreshTask?.cancel()
        snapshotRefreshTask = nil
        cancellable = nil
        viewModel = nil
        lastSnapshot = nil
        installViewModel(api: api, libraryStore: libraryStore, sessionStore: sessionStore)
    }

    private func installViewModel(
        api: BiliAPIClient,
        libraryStore: LibraryStore,
        sessionStore: SessionStore
    ) {
        let viewModel = DynamicViewModel(api: api, libraryStore: libraryStore, sessionStore: sessionStore)
        self.viewModel = viewModel
        lastSnapshot = DynamicRenderSnapshot(viewModel)
        cancellable = viewModel.objectWillChange.sink { [weak self] _ in
            self?.scheduleSnapshotRefresh(for: viewModel)
        }
    }

    private func scheduleSnapshotRefresh(for viewModel: DynamicViewModel) {
        guard snapshotRefreshTask == nil else { return }
        snapshotRefreshTask = Task { @MainActor [weak self, weak viewModel] in
            try? await Task.sleep(nanoseconds: 16_000_000)
            guard let self, let viewModel, !Task.isCancelled else { return }
            self.snapshotRefreshTask = nil
            let snapshot = DynamicRenderSnapshot(viewModel)
            guard snapshot != self.lastSnapshot else { return }
            self.lastSnapshot = snapshot
            self.objectWillChange.send()
        }
    }

    deinit {
        snapshotRefreshTask?.cancel()
    }
}

private struct DynamicRenderSnapshot: Equatable {
    let state: LoadingState
    let hasMoreItems: Bool
    let topUploaderStripRevision: Int
    let isTopUploaderStripLoading: Bool
    let itemCount: Int
    let firstItemID: String?
    let lastItemID: String?
    let itemsRevision: Int

    init(_ viewModel: DynamicViewModel) {
        state = viewModel.state
        hasMoreItems = viewModel.hasMoreItems
        topUploaderStripRevision = viewModel.topUploaderStripRevision
        isTopUploaderStripLoading = viewModel.isTopUploaderStripLoading
        itemCount = viewModel.items.count
        firstItemID = viewModel.items.first?.id
        lastItemID = viewModel.items.last?.id
        itemsRevision = viewModel.itemsRevision
    }
}

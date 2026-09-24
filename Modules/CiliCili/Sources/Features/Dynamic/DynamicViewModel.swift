import Combine
import Foundation

@MainActor
final class DynamicViewModel: ObservableObject {
    @Published var items: [DynamicFeedItem] = [] {
        didSet {
            itemsRevision &+= 1
        }
    }
    @Published private(set) var topUploaderStripItems: [DynamicTopUploaderStripItem] = [] {
        didSet {
            topUploaderStripRevision &+= 1
        }
    }
    @Published private(set) var isTopUploaderStripLoading = false
    @Published private(set) var isRefreshing = false
    @Published var state: LoadingState = .idle
    @Published private(set) var itemsRevision = 0
    @Published private(set) var topUploaderStripRevision = 0

    private let lifecycleCoordinator: DynamicFeedLifecycleCoordinator
    private var filterCancellable: AnyCancellable?

    var hasMoreItems: Bool {
        lifecycleCoordinator.hasMoreItems
    }

    init(api: BiliAPIClient, libraryStore: LibraryStore, sessionStore: SessionStore) {
        let contentFilter = DynamicFeedContentFilter(libraryStore: libraryStore)
        let resourcePrefetchCoordinator = DynamicFeedResourcePrefetchCoordinator(
            api: api,
            libraryStore: libraryStore
        )
        lifecycleCoordinator = DynamicFeedLifecycleCoordinator(
            api: api,
            sessionStore: sessionStore,
            libraryStore: libraryStore,
            contentFilter: contentFilter,
            resourcePrefetchCoordinator: resourcePrefetchCoordinator
        )
        filterCancellable = libraryStore.$blocksAdDynamics
            .combineLatest(libraryStore.$blocksGoodsDynamics)
            .combineLatest(libraryStore.$blockedDynamicKeywords)
            .removeDuplicates { lhs, rhs in
                lhs.0.0 == rhs.0.0
                    && lhs.0.1 == rhs.0.1
                    && lhs.1 == rhs.1
            }
            .dropFirst()
            .sink { [weak self] _ in
                self?.applyCurrentFilter()
            }
    }

    func loadInitial() async {
        guard items.isEmpty else { return }
        guard lifecycleCoordinator.isLoggedIn else {
            prepareLoggedOutState()
            return
        }
        state = .loading
        refreshTopUploaderStrip()
        do {
            items = try await lifecycleCoordinator.loadInitialPage()
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func refresh() async {
        guard lifecycleCoordinator.isLoggedIn, !isRefreshing else {
            if !lifecycleCoordinator.isLoggedIn {
                prepareLoggedOutState()
            }
            return
        }
        isRefreshing = true
        defer {
            isRefreshing = false
        }
        state = .loading
        refreshTopUploaderStrip()
        do {
            items = try await lifecycleCoordinator.refreshPage()
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func loadMoreIfNeeded(current item: DynamicFeedItem?) async {
        guard let item, items.last?.id == item.id else { return }
        await loadMore()
    }

    func loadMore() async {
        guard lifecycleCoordinator.isLoggedIn else {
            prepareLoggedOutState()
            return
        }
        guard lifecycleCoordinator.hasMoreItems, !state.isLoading else { return }
        state = .loading
        do {
            items = try await lifecycleCoordinator.loadMorePage()
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func prepareLoggedOutState() {
        lifecycleCoordinator.prepareLoggedOutState()
        items = []
        topUploaderStripItems = []
        isTopUploaderStripLoading = false
        state = .idle
    }

    private func applyCurrentFilter() {
        items = lifecycleCoordinator.filteredCurrentItems()
    }

    private func refreshTopUploaderStrip() {
        isTopUploaderStripLoading = true
        lifecycleCoordinator.refreshTopUploaderStripItems { [weak self] items in
            self?.topUploaderStripItems = items
            self?.isTopUploaderStripLoading = false
        }
    }
}

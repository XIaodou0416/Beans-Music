import Foundation

@MainActor
final class DynamicFeedLifecycleCoordinator {
    private let api: BiliAPIClient
    private let sessionStore: SessionStore
    private let libraryStore: LibraryStore
    private let contentFilter: DynamicFeedContentFilter
    private let resourcePrefetchCoordinator: DynamicFeedResourcePrefetchCoordinator
    private var rawItems: [DynamicFeedItem] = []
    private var offset = ""
    private var hasMore = true
    private var topUploaderStripTask: Task<Void, Never>?

    var isLoggedIn: Bool {
        sessionStore.isLoggedIn
    }

    var hasMoreItems: Bool {
        hasMore
    }

    init(
        api: BiliAPIClient,
        sessionStore: SessionStore,
        libraryStore: LibraryStore,
        contentFilter: DynamicFeedContentFilter,
        resourcePrefetchCoordinator: DynamicFeedResourcePrefetchCoordinator
    ) {
        self.api = api
        self.sessionStore = sessionStore
        self.libraryStore = libraryStore
        self.contentFilter = contentFilter
        self.resourcePrefetchCoordinator = resourcePrefetchCoordinator
    }

    deinit {
        topUploaderStripTask?.cancel()
    }

    func prepareLoggedOutState() {
        topUploaderStripTask?.cancel()
        topUploaderStripTask = nil
        rawItems = []
        offset = ""
        hasMore = false
    }

    func loadInitialPage() async throws -> [DynamicFeedItem] {
        resetPagination()
        let page = try await DynamicFeedWarmCache.shared.page(
            api: api,
            identityKey: cacheIdentityKey
        )
        return apply(page: page, prefetchDelay: 0.08)
    }

    func refreshPage() async throws -> [DynamicFeedItem] {
        resetPagination()
        let identityKey = cacheIdentityKey
        let page = try await api.fetchDynamicFeed()
        await DynamicFeedWarmCache.shared.store(page, identityKey: identityKey)
        return apply(page: page, prefetchDelay: 0.08)
    }

    func loadMorePage() async throws -> [DynamicFeedItem] {
        let page = try await api.fetchDynamicFeed(offset: offset)
        let moreItems = contentFilter.displayable(page.items)
        rawItems = contentFilter.uniqueAppendItems(moreItems, to: rawItems)
        let filteredItems = filteredCurrentItems()
        resourcePrefetchCoordinator.scheduleResourcePrefetch(for: moreItems, initialDelay: 0.75)
        offset = page.offset ?? offset
        hasMore = page.hasMore ?? false
        return filteredItems
    }

    func filteredCurrentItems() -> [DynamicFeedItem] {
        contentFilter.filtered(rawItems)
    }

    func refreshTopUploaderStripItems(setItems: @escaping ([DynamicTopUploaderStripItem]) -> Void) {
        topUploaderStripTask?.cancel()
        topUploaderStripTask = Task { [api] in
            let portal = try? await api.fetchDynamicPortal()
            guard !Task.isCancelled else { return }

            let items = Self.makeTopUploaderStripItems(
                portal: portal,
                limit: 10
            )
            await MainActor.run {
                setItems(items)
            }
        }
    }

    private func resetPagination() {
        offset = ""
        hasMore = true
    }

    private var cacheIdentityKey: String {
        sessionStore.accountCacheIdentityKey(
            for: .dynamicFeed,
            multiAccountEnabled: libraryStore.multiAccountExperimentEnabled
        )
    }

    private func apply(page: DynamicFeedData, prefetchDelay: TimeInterval) -> [DynamicFeedItem] {
        rawItems = contentFilter.displayable(page.items)
        let filteredItems = filteredCurrentItems()
        if !filteredItems.isEmpty {
            StageOneBaselineMetricsStore.shared.markDynamicFirstData()
        }
        resourcePrefetchCoordinator.scheduleResourcePrefetch(for: filteredItems, initialDelay: prefetchDelay)
        offset = page.offset ?? ""
        hasMore = page.hasMore ?? false
        return filteredItems
    }

    private nonisolated static func makeTopUploaderStripItems(
        portal: DynamicPortalData?,
        limit: Int
    ) -> [DynamicTopUploaderStripItem] {
        var items: [DynamicTopUploaderStripItem] = []
        var usedMIDs = Set<Int>()

        for liveUser in portal?.liveUsers?.items ?? [] {
            let owner = liveUser.owner
            guard owner.mid <= 0 || usedMIDs.insert(owner.mid).inserted else { continue }
            items.append(DynamicTopUploaderStripItem(owner: owner, liveRoom: liveUser.liveRoom))
            guard items.count < limit else { return items }
        }

        for upItem in portal?.upList?.items ?? [] {
            let owner = upItem.owner
            guard owner.mid > 0, usedMIDs.insert(owner.mid).inserted else { continue }
            items.append(DynamicTopUploaderStripItem(owner: owner, liveRoom: nil))
            guard items.count < limit else { break }
        }

        return items
    }
}

import Combine
import Foundation

@MainActor
final class LiveViewModelHolder: ObservableObject {
    @Published var viewModel: LiveViewModel?
    private var cancellable: AnyCancellable?
    private var lastSnapshot: LiveRenderSnapshot?

    func configure(api: BiliAPIClient) {
        guard viewModel == nil else { return }
        let viewModel = LiveViewModel(api: api)
        self.viewModel = viewModel
        lastSnapshot = LiveRenderSnapshot(viewModel)
        cancellable = viewModel.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self, weak viewModel] in
                guard let self, let viewModel else { return }
                let snapshot = LiveRenderSnapshot(viewModel)
                guard snapshot != self.lastSnapshot else { return }
                self.lastSnapshot = snapshot
                self.objectWillChange.send()
            }
        }
    }
}

@MainActor
final class LiveViewModel: ObservableObject {
    @Published private(set) var rooms: [LiveRoom] = [] {
        didSet { roomsRevision &+= 1 }
    }
    @Published var state: LoadingState = .idle
    @Published private(set) var isLoadingMore = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var loadMoreMessage: String?
    @Published private(set) var roomsRevision = 0

    private let api: BiliAPIClient
    private var page = 1
    private var hasMore = true
    private var generation = 0
    private var refreshIndex = 0
    private let pageSize = 20
    private var imagePrefetchTask: Task<Void, Never>?

    init(api: BiliAPIClient) {
        self.api = api
    }

    deinit {
        imagePrefetchTask?.cancel()
    }

    var emptyTitle: String {
        "暂无直播"
    }

    var emptyMessage: String {
        if case .failed(let message) = state {
            return message
        }
        return "下拉刷新或稍后再来看看。"
    }

    func loadInitial() async {
        guard rooms.isEmpty, !state.isLoading else { return }
        await loadFirstPage(isUserInitiated: false)
    }

    func refresh() async {
        guard !isRefreshing else { return }
        await loadFirstPage(isUserInitiated: true)
    }

    func loadMoreIfNeeded(current room: LiveRoom) async {
        guard rooms.last?.id == room.id else { return }
        await loadMore()
    }

    private func loadFirstPage(isUserInitiated: Bool) async {
        generation &+= 1
        refreshIndex &+= 1
        let currentGeneration = generation
        let currentRefreshIndex = refreshIndex
        let previousRooms = rooms
        let previousPage = page
        let previousHasMore = hasMore
        isRefreshing = isUserInitiated
        isLoadingMore = false
        loadMoreMessage = nil
        state = .loading
        await loadPage(
            1,
            reset: true,
            generation: currentGeneration,
            refreshIndex: currentRefreshIndex,
            previousRooms: previousRooms,
            previousPage: previousPage,
            previousHasMore: previousHasMore
        )
    }

    private func loadMore() async {
        guard hasMore, !state.isLoading, !isLoadingMore else { return }
        let currentGeneration = generation
        let nextPage = page
        loadMoreMessage = nil
        isLoadingMore = true
        await loadPage(
            nextPage,
            reset: false,
            generation: currentGeneration,
            refreshIndex: refreshIndex,
            previousRooms: rooms,
            previousPage: page,
            previousHasMore: hasMore
        )
    }

    private func loadPage(
        _ targetPage: Int,
        reset: Bool,
        generation targetGeneration: Int,
        refreshIndex targetRefreshIndex: Int,
        previousRooms: [LiveRoom],
        previousPage: Int,
        previousHasMore: Bool
    ) async {
        defer {
            if targetGeneration == generation {
                isLoadingMore = false
                isRefreshing = false
            }
        }

        do {
            let fetchedRooms = try await api.fetchLiveRooms(
                page: targetPage,
                refreshIndex: targetRefreshIndex
            )
            guard targetGeneration == generation else { return }

            if reset {
                rooms = Self.uniqued(fetchedRooms)
            } else {
                rooms = Self.appendingUnique(fetchedRooms, to: rooms)
            }

            scheduleImagePrefetch(for: reset ? rooms : fetchedRooms)
            page = targetPage + 1
            hasMore = fetchedRooms.count >= pageSize
            state = .loaded
        } catch {
            guard targetGeneration == generation else { return }
            let message = error.localizedDescription
            if reset, !previousRooms.isEmpty {
                rooms = previousRooms
                page = previousPage
                hasMore = previousHasMore
                loadMoreMessage = "刷新失败，已保留当前推荐"
                state = .loaded
            } else if reset || rooms.isEmpty {
                state = .failed(message)
            } else {
                loadMoreMessage = "加载更多失败，稍后再试"
                state = .loaded
            }
        }
    }

    private static func uniqued(_ rooms: [LiveRoom]) -> [LiveRoom] {
        appendingUnique(rooms, to: [])
    }

    private static func appendingUnique(_ newRooms: [LiveRoom], to existingRooms: [LiveRoom]) -> [LiveRoom] {
        var seen = Set(existingRooms.map(\.roomID))
        var result = existingRooms
        for room in newRooms where seen.insert(room.roomID).inserted {
            result.append(room)
        }
        return result
    }

    private func scheduleImagePrefetch(for rooms: [LiveRoom]) {
        imagePrefetchTask?.cancel()
        let environment = PlaybackEnvironment.current
        let plan = imagePrefetchPlan(for: rooms, limit: environment.shouldPreferConservativePlayback ? 6 : 10)
        guard !plan.coverSources.isEmpty || !plan.avatarSources.isEmpty else { return }
        imagePrefetchTask = Task(priority: .utility) {
            async let coverPrefetch: Void = RemoteImageCache.shared.prefetch(
                plan.coverSources,
                targetPixelSize: 420,
                maximumConcurrentLoads: environment.shouldPreferConservativePlayback ? 1 : 2
            )
            async let avatarPrefetch: Void = RemoteImageCache.shared.prefetch(
                plan.avatarSources,
                targetPixelSize: 56,
                maximumConcurrentLoads: 1
            )
            _ = await (coverPrefetch, avatarPrefetch)
        }
    }

    private func imagePrefetchPlan(
        for rooms: [LiveRoom],
        limit: Int
    ) -> (coverSources: [RemoteImageSource], avatarSources: [RemoteImageSource]) {
        var seenCovers = Set<String>()
        var seenAvatars = Set<String>()
        var coverSources = [RemoteImageSource]()
        var avatarSources = [RemoteImageSource]()

        for room in rooms.prefix(limit) {
            if let coverSource = coverSource(for: room),
               seenCovers.insert(coverSource.identity).inserted {
                coverSources.append(coverSource.source)
            }

            if let face = room.face?.normalizedBiliURL(),
               let url = URL(string: face.biliAvatarThumbnailURL(size: 56)),
               seenAvatars.insert(face).inserted {
                avatarSources.append(RemoteImageSource(url: url, fallbackURL: URL(string: face)))
            }
        }

        return (coverSources, avatarSources)
    }

    private func coverSource(for room: LiveRoom) -> (identity: String, source: RemoteImageSource)? {
        let coverCandidates = room.coverCandidates
        if let cover = coverCandidates.first,
           let url = URL(string: cover.biliCoverThumbnailURL(width: 420, height: 236)) {
            let fallbackURL: URL?
            if coverCandidates.count > 1 {
                fallbackURL = URL(string: coverCandidates[1].biliCoverThumbnailURL(width: 420, height: 236))
            } else if let face = room.face?.normalizedBiliURL() {
                fallbackURL = URL(string: face.biliAvatarThumbnailURL(size: 240))
            } else {
                fallbackURL = nil
            }
            return (coverCandidates.joined(separator: "|"), RemoteImageSource(url: url, fallbackURL: fallbackURL))
        }

        guard let face = room.face?.normalizedBiliURL(),
              let url = URL(string: face.biliImageThumbnailURL(maxSide: 420))
        else { return nil }
        return ("avatar|\(face)", RemoteImageSource(url: url, fallbackURL: URL(string: face)))
    }
}

private struct LiveRenderSnapshot: Equatable {
    let state: LoadingState
    let isLoadingMore: Bool
    let isRefreshing: Bool
    let loadMoreMessage: String?
    let roomCount: Int
    let firstRoomID: Int?
    let lastRoomID: Int?
    let roomsRevision: Int

    init(_ viewModel: LiveViewModel) {
        state = viewModel.state
        isLoadingMore = viewModel.isLoadingMore
        isRefreshing = viewModel.isRefreshing
        loadMoreMessage = viewModel.loadMoreMessage
        roomCount = viewModel.rooms.count
        firstRoomID = viewModel.rooms.first?.roomID
        lastRoomID = viewModel.rooms.last?.roomID
        roomsRevision = viewModel.roomsRevision
    }
}

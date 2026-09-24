import Foundation
import Combine

enum UploaderVideoOrder: String, CaseIterable, Identifiable, Sendable {
    case pubdate
    case click

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pubdate:
            return "最新发布"
        case .click:
            return "最多播放"
        }
    }
}

@MainActor
final class UploaderViewModel: ObservableObject {
    @Published var profile: UploaderProfile? {
        didSet { profileRevision &+= 1 }
    }
    @Published var videos: [VideoItem] = [] {
        didSet { videosRevision &+= 1 }
    }
    @Published var state: LoadingState = .idle
    @Published private(set) var profileState: LoadingState = .idle
    @Published private(set) var isFollowing = false
    @Published private(set) var followerCount: Int?
    @Published private(set) var followingCount: Int?
    @Published private(set) var likeCount: Int?
    @Published private(set) var archiveCount: Int?
    @Published private(set) var isMutatingFollow = false
    @Published var followMessage: String?
    @Published private(set) var profileRevision = 0
    @Published private(set) var videosRevision = 0
    @Published private(set) var videoOrder: UploaderVideoOrder = .pubdate
    @Published private(set) var hasMoreVideos = true
    @Published var dynamicItems: [DynamicFeedItem] = [] {
        didSet { dynamicItemsRevision &+= 1 }
    }
    @Published var dynamicState: LoadingState = .idle
    @Published private(set) var dynamicItemsRevision = 0
    @Published var seasonSeriesItems: [UploaderSeasonSeriesItem] = [] {
        didSet { seasonSeriesRevision &+= 1 }
    }
    @Published var seasonSeriesState: LoadingState = .idle
    @Published private(set) var seasonSeriesRevision = 0

    let seedOwner: VideoOwner

    private let api: BiliAPIClient
    private let uploaderVideosTimeoutNanoseconds: UInt64 = 8_000_000_000
    private var page = 1
    private var videoCursor: UploaderVideoPageCursor?
    private var dynamicOffset: String?
    private var dynamicHasMore = true
    private var seasonSeriesPage = 1
    private var seasonSeriesHasMore = true

    init(seedOwner: VideoOwner, api: BiliAPIClient) {
        self.seedOwner = seedOwner
        self.api = api
    }

    func loadInitial() async {
        if profile == nil, !profileState.isLoading {
            Task { await loadProfile() }
        }
        guard videos.isEmpty, !state.isLoading else { return }
        await refresh()
    }

    func refresh() async {
        state = .loading
        page = 1
        videoCursor = nil
        hasMoreVideos = true
        Task { await loadProfile(force: true) }
        do {
            applyVideoPage(try await fetchUploaderVideosWithTimeout(page: page), appending: false)
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func loadProfile(force: Bool = false) async {
        guard force || !profileState.isLoading else { return }
        profileState = .loading
        var didLoadStats = false
        do {
            let statsProfile = try await api.fetchUploaderStatsProfile(mid: seedOwner.mid)
            applyProfile(statsProfile)
            didLoadStats = statsProfile.hasVisibleStats
        } catch {
            didLoadStats = false
        }
        do {
            applyProfile(try await api.fetchUploaderProfile(mid: seedOwner.mid))
            profileState = .loaded
        } catch {
            profileState = didLoadStats ? .loaded : .failed(error.localizedDescription)
        }
    }

    func loadMoreIfNeeded(current video: VideoItem?) async {
        guard let video,
              videos.last?.id == video.id,
              hasMoreVideos,
              !state.isLoading
        else { return }
        state = .loading
        page += 1
        do {
            applyVideoPage(try await fetchUploaderVideosWithTimeout(page: page), appending: true)
            state = .loaded
        } catch {
            page = max(1, page - 1)
            state = .failed(error.localizedDescription)
        }
    }

    func changeVideoOrder(_ order: UploaderVideoOrder) async {
        guard order != videoOrder, !state.isLoading else { return }
        videoOrder = order
        videos = []
        await refresh()
    }

    var hasMoreDynamicItems: Bool {
        dynamicHasMore
    }

    func loadDynamicsIfNeeded() async {
        guard dynamicItems.isEmpty, !dynamicState.isLoading else { return }
        await refreshDynamics()
    }

    func refreshDynamics() async {
        dynamicState = .loading
        dynamicOffset = nil
        dynamicHasMore = true
        do {
            let page = try await api.fetchUploaderDynamicFeed(mid: seedOwner.mid)
            applyDynamicPage(page, appending: false)
            dynamicState = .loaded
        } catch {
            dynamicState = .failed(error.localizedDescription)
        }
    }

    func loadMoreDynamicsIfNeeded(current item: DynamicFeedItem?) async {
        guard let item, dynamicItems.last?.id == item.id else { return }
        await loadMoreDynamics()
    }

    func loadMoreDynamics() async {
        guard dynamicHasMore, !dynamicState.isLoading else { return }
        dynamicState = .loading
        do {
            let page = try await api.fetchUploaderDynamicFeed(mid: seedOwner.mid, offset: dynamicOffset)
            applyDynamicPage(page, appending: true)
            dynamicState = .loaded
        } catch {
            dynamicState = .failed(error.localizedDescription)
        }
    }

    var hasMoreSeasonSeriesItems: Bool {
        seasonSeriesHasMore
    }

    func loadSeasonSeriesIfNeeded() async {
        guard seasonSeriesItems.isEmpty, !seasonSeriesState.isLoading else { return }
        await refreshSeasonSeries()
    }

    func refreshSeasonSeries() async {
        seasonSeriesState = .loading
        seasonSeriesPage = 1
        seasonSeriesHasMore = true
        do {
            let page = try await api.fetchUploaderSeasonSeries(mid: seedOwner.mid, page: seasonSeriesPage)
            applySeasonSeriesPage(page, appending: false)
            seasonSeriesState = .loaded
        } catch {
            seasonSeriesState = .failed(error.localizedDescription)
        }
    }

    func loadMoreSeasonSeriesIfNeeded(current item: UploaderSeasonSeriesItem?) async {
        guard let item, seasonSeriesItems.last?.id == item.id else { return }
        await loadMoreSeasonSeries()
    }

    func loadMoreSeasonSeries() async {
        guard seasonSeriesHasMore, !seasonSeriesState.isLoading else { return }
        seasonSeriesState = .loading
        seasonSeriesPage += 1
        do {
            let page = try await api.fetchUploaderSeasonSeries(mid: seedOwner.mid, page: seasonSeriesPage)
            applySeasonSeriesPage(page, appending: true)
            seasonSeriesState = .loaded
        } catch {
            seasonSeriesPage = max(1, seasonSeriesPage - 1)
            seasonSeriesState = .failed(error.localizedDescription)
        }
    }

    private func fetchUploaderVideosWithTimeout(page: Int) async throws -> UploaderVideoPageResult {
        try await withThrowingTaskGroup(of: UploaderVideoPageResult.self) { group in
            let mid = seedOwner.mid
            let timeout = uploaderVideosTimeoutNanoseconds
            let cursor = videoCursor
            let order = videoOrder

            group.addTask(priority: .userInitiated) {
                try await self.api.fetchUploaderVideoPage(mid: mid, page: page, cursor: cursor, order: order)
            }
            group.addTask(priority: .utility) {
                try await Task.sleep(nanoseconds: timeout)
                throw BiliAPIError.api(code: -1, message: "投稿加载超时，请稍后重试")
            }

            guard let pageResult = try await group.next() else {
                group.cancelAll()
                throw BiliAPIError.emptyData
            }
            group.cancelAll()
            return pageResult
        }
    }

    @discardableResult
    func toggleFollow() async -> Bool {
        guard !isMutatingFollow else { return false }
        guard seedOwner.mid > 0 else {
            followMessage = "没有找到 UP 主 UID，无法关注"
            return false
        }

        let targetState = !isFollowing
        let previousState = isFollowing
        let previousFollowerCount = followerCount
        isMutatingFollow = true
        isFollowing = targetState
        if let followerCount {
            self.followerCount = max(0, followerCount + (targetState ? 1 : -1))
        }
        followMessage = targetState ? "正在关注" : "正在取消关注"

        do {
            try await api.setUploaderFollowing(mid: seedOwner.mid, following: targetState)
            followMessage = targetState ? "已关注" : "已取消关注"
            isMutatingFollow = false
            Task { await loadProfile(force: true) }
            return true
        } catch {
            isFollowing = previousState
            followerCount = previousFollowerCount
            followMessage = followFailureMessage(error)
            isMutatingFollow = false
            return false
        }
    }

    @discardableResult
    private func appendUnique(_ more: [VideoItem]) -> Int {
        let existing = Set(videos.map(\.id))
        let unique = more.filter { !existing.contains($0.id) }
        videos.append(contentsOf: unique)
        return unique.count
    }

    private func applyVideoPage(_ page: UploaderVideoPageResult, appending: Bool) {
        videoCursor = page.nextCursor
        if let totalCount = page.totalCount {
            archiveCount = totalCount
        }
        if appending {
            let appendedCount = appendUnique(page.videos)
            hasMoreVideos = page.hasMore && appendedCount > 0
        } else {
            videos = page.videos
            hasMoreVideos = page.hasMore && !page.videos.isEmpty
        }
    }

    private func applyDynamicPage(_ page: DynamicFeedData, appending: Bool) {
        dynamicOffset = page.offset
        dynamicHasMore = page.hasMore ?? false
        let incoming = page.items ?? []
        if appending {
            let existing = Set(dynamicItems.map(\.id))
            dynamicItems.append(contentsOf: incoming.filter { !existing.contains($0.id) })
        } else {
            dynamicItems = incoming
        }
    }

    private func applySeasonSeriesPage(_ page: UploaderSeasonSeriesData, appending: Bool) {
        let incoming = page.items
        seasonSeriesHasMore = page.page?.hasMore(afterPage: seasonSeriesPage, receivedCount: incoming.count) ?? !incoming.isEmpty
        if appending {
            let existing = Set(seasonSeriesItems.map(\.id))
            let unique = incoming.filter { !existing.contains($0.id) }
            seasonSeriesItems.append(contentsOf: unique)
            seasonSeriesHasMore = seasonSeriesHasMore && !unique.isEmpty
        } else {
            seasonSeriesItems = incoming
            seasonSeriesHasMore = seasonSeriesHasMore && !incoming.isEmpty
        }
    }

    private func applyProfile(_ profile: UploaderProfile) {
        let mergedProfile = self.profile?.merged(with: profile) ?? profile
        self.profile = mergedProfile
        if let isFollowing = profile.following {
            self.isFollowing = isFollowing
        }
        followerCount = mergedProfile.visibleFollowerCount ?? followerCount
        followingCount = mergedProfile.visibleFollowingCount ?? followingCount
        likeCount = mergedProfile.visibleLikeCount ?? likeCount
        archiveCount = mergedProfile.visibleArchiveCount ?? archiveCount
        followMessage = nil
    }

    private func followFailureMessage(_ error: Error) -> String {
        if case BiliAPIError.missingSESSDATA = error {
            return "登录后才能关注 UP 主"
        }
        return "关注状态更新失败：\(error.localizedDescription)"
    }
}

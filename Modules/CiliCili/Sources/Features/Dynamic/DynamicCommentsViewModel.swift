import Combine
import Foundation

nonisolated enum DynamicCommentRefreshOutcome: Equatable, Sendable {
    case refreshed
    case superseded
    case failed
}

@MainActor
final class DynamicCommentsViewModel: ObservableObject {
    private(set) var comments: [Comment] = [] {
        didSet {
            syncCommentItems()
        }
    }
    @Published private(set) var commentItems: [DynamicCommentRowItem] = []
    @Published var state: LoadingState = .idle
    @Published var loadMoreState: LoadingState = .idle
    @Published var selectedSort: CommentSort = .hot
    @Published private(set) var displayedReplyCount: Int?
    let replyStore: DynamicCommentReplyStore

    private let item: DynamicFeedItem
    private let api: BiliAPIClient
    private var blocksGoodsComments = true
    private var cursor = ""
    private var commentsEnd = false
    private var commentItemsSignature = DynamicCommentListSignature([])
    private var loadGeneration = 0

    var canLoadComments: Bool {
        commentOID != nil && commentType != nil
    }

    var hasMoreComments: Bool {
        !commentsEnd
    }

    init(item: DynamicFeedItem, api: BiliAPIClient) {
        self.item = item
        self.api = api
        self.displayedReplyCount = item.replyCount
        self.replyStore = DynamicCommentReplyStore(item: item, api: api, blocksGoodsComments: blocksGoodsComments)
    }

    func setBlocksGoodsComments(_ isEnabled: Bool) {
        guard blocksGoodsComments != isEnabled else { return }
        blocksGoodsComments = isEnabled
        replyStore.setBlocksGoodsComments(isEnabled)
        refilterLoadedComments()
    }

    func loadInitial() async {
        guard comments.isEmpty, state != .loading else { return }
        await reload()
    }

    func reload() async {
        _ = await reload(cookieHeader: nil)
    }

    private func reload(cookieHeader: String?) async -> DynamicCommentRefreshOutcome {
        loadGeneration &+= 1
        let generation = loadGeneration
        let previousCursor = cursor
        let previousCommentsEnd = commentsEnd
        cursor = ""
        commentsEnd = false
        loadMoreState = .idle
        let outcome = await loadPage(
            emptyPageSkipLimit: 2,
            generation: generation,
            cookieHeader: cookieHeader,
            replacesExistingComments: true
        )
        if outcome == .failed, generation == loadGeneration, !comments.isEmpty {
            cursor = previousCursor
            commentsEnd = previousCommentsEnd
            state = .loaded
        }
        return outcome
    }

    func selectSort(_ sort: CommentSort) async {
        guard selectedSort != sort else { return }
        selectedSort = sort
        await reload()
    }

    func loadMore() async {
        guard !state.isLoading, !loadMoreState.isLoading, !commentsEnd else { return }
        _ = await loadPage(
            emptyPageSkipLimit: 2,
            generation: loadGeneration,
            replacesExistingComments: false
        )
    }

    func registerSubmittedComment() {
        displayedReplyCount = max(0, (displayedReplyCount ?? comments.count) + 1)
    }

    private var commentOID: String? {
        item.commentOID
    }

    private var commentType: Int? {
        item.commentType
    }

    private func loadPage(
        emptyPageSkipLimit: Int = 0,
        generation: Int,
        cookieHeader: String? = nil,
        replacesExistingComments: Bool
    ) async -> DynamicCommentRefreshOutcome {
        guard generation == loadGeneration else { return .superseded }
        guard let oid = commentOID, let type = commentType else {
            state = .failed("这条动态没有返回评论入口")
            commentsEnd = true
            return .failed
        }

        let isInitialPage = replacesExistingComments && cursor.isEmpty
        var remainingEmptyPageSkips = emptyPageSkipLimit
        if isInitialPage {
            state = .loading
            loadMoreState = .idle
        } else {
            loadMoreState = .loading
        }
        while true {
            let previousCount = comments.count
            let previousCursor = cursor
            do {
                let page = try await fetchCommentsWithTimeout(
                    oid: oid,
                    type: type,
                    cursor: cursor,
                    sort: selectedSort,
                    cookieHeader: cookieHeader
                )
                guard generation == loadGeneration else { return .superseded }
                let pageComments = isInitialPage
                    ? (page.topReplies ?? []) + (page.replies ?? [])
                    : (page.replies ?? [])
                let filteredPageComments = filteredComments(pageComments)
                if replacesExistingComments {
                    if !filteredPageComments.isEmpty || comments.isEmpty {
                        comments = uniqueComments(filteredPageComments)
                    }
                } else {
                    appendUniqueComments(filteredPageComments)
                }
                cursor = page.cursor?.effectiveNext ?? ""
                commentsEnd = page.cursor?.isEnd ?? (comments.count == previousCount && cursor.isEmpty)
                state = .loaded
                loadMoreState = .idle

                let didAppendComments = replacesExistingComments
                    ? !filteredPageComments.isEmpty
                    : comments.count > previousCount
                let canSkipEmptyPage = !didAppendComments
                    && !commentsEnd
                    && remainingEmptyPageSkips > 0
                    && !cursor.isEmpty
                    && cursor != previousCursor
                guard canSkipEmptyPage else {
                    if !isInitialPage, !didAppendComments {
                        commentsEnd = true
                    }
                    return .refreshed
                }
                remainingEmptyPageSkips -= 1
                if isInitialPage {
                    state = .loading
                } else {
                    loadMoreState = .loading
                }
            } catch is CancellationError {
                guard generation == loadGeneration else { return .superseded }
                if isInitialPage, comments.isEmpty {
                    state = .idle
                } else {
                    state = .loaded
                    commentsEnd = true
                }
                loadMoreState = .idle
                return .failed
            } catch {
                guard generation == loadGeneration else { return .superseded }
                if comments.isEmpty {
                    state = .failed(error.localizedDescription)
                    loadMoreState = .idle
                } else {
                    state = .loaded
                    commentsEnd = true
                    loadMoreState = .idle
                }
                return .failed
            }
        }
    }

    private func appendUniqueComments(_ more: [Comment]) {
        let existing = Set(comments.map(\.id))
        comments.append(contentsOf: more.filter { !existing.contains($0.id) })
    }

    private func uniqueComments(_ comments: [Comment]) -> [Comment] {
        var seen = Set<Int>()
        return comments.filter { seen.insert($0.id).inserted }
    }

    private func fetchCommentsWithTimeout(
        oid: String,
        type: Int,
        cursor: String,
        sort: CommentSort,
        cookieHeader: String? = nil
    ) async throws -> CommentPage {
        try await withThrowingTaskGroup(of: CommentPage.self) { group in
            group.addTask(priority: .userInitiated) {
                try await self.api.fetchComments(
                    oid: oid,
                    type: type,
                    cursor: cursor,
                    sort: sort,
                    cookieHeader: cookieHeader
                )
            }
            group.addTask(priority: .utility) {
                try await Task.sleep(nanoseconds: 8_000_000_000)
                throw BiliAPIError.api(code: -1, message: "评论加载超时，请稍后重试")
            }
            guard let page = try await group.next() else {
                group.cancelAll()
                throw BiliAPIError.emptyData
            }
            group.cancelAll()
            return page
        }
    }

    private func syncCommentItems() {
        let nextSignature = DynamicCommentListSignature(comments)
        guard nextSignature != commentItemsSignature else { return }
        commentItemsSignature = nextSignature
        commentItems = comments.map(DynamicCommentRowItem.init)
    }

    private func filteredComments(_ values: [Comment]) -> [Comment] {
        guard blocksGoodsComments else { return values }
        return values.filter { !$0.containsGoodsPromotion }
    }

    func refilterLoadedComments() {
        guard !comments.isEmpty else { return }
        if blocksGoodsComments {
            comments = filteredComments(comments)
        } else {
            Task { await reload() }
        }
    }
}

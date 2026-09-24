import Combine
import Foundation

@MainActor
final class DynamicCommentReplyStore: ObservableObject {
    @Published private var snapshot = DynamicCommentReplyStoreSnapshot()
    private var replyItemCache: [Int: DynamicCommentReplyItemCacheEntry] = [:]
    private var dialogItemCache: [String: DynamicCommentDialogItemCacheEntry] = [:]
    private var replyLoadGenerations: [Int: Int] = [:]
    private var dialogLoadGenerations: [String: Int] = [:]

    private let item: DynamicFeedItem
    private let api: BiliAPIClient
    private var blocksGoodsComments: Bool

    init(item: DynamicFeedItem, api: BiliAPIClient, blocksGoodsComments: Bool) {
        self.item = item
        self.api = api
        self.blocksGoodsComments = blocksGoodsComments
    }

    private func updateSnapshot(_ transform: (inout DynamicCommentReplyStoreSnapshot) -> Void) {
        var next = snapshot
        transform(&next)
        setSnapshot(next)
    }

    private func setSnapshot(_ next: DynamicCommentReplyStoreSnapshot) {
        guard next.changeSignature != snapshot.changeSignature else { return }
        snapshot = next
    }

    func setBlocksGoodsComments(_ isEnabled: Bool) {
        guard blocksGoodsComments != isEnabled else { return }
        blocksGoodsComments = isEnabled
        updateSnapshot { snapshot in
            if isEnabled {
                snapshot.replyThreads = snapshot.replyThreads.mapValues(filteredComments)
                snapshot.dialogThreads = snapshot.dialogThreads.mapValues(filteredComments)
            } else {
                snapshot.replyThreads = [:]
                snapshot.dialogThreads = [:]
                snapshot.replyPages = [:]
                snapshot.replyHasMore = [:]
            }
        }
        replyItemCache.removeAll()
        dialogItemCache.removeAll()
    }

    func replies(for comment: Comment) -> [Comment] {
        snapshot.replyThreads[comment.id] ?? comment.replies ?? []
    }

    func repliesSnapshot(for comment: Comment) -> DynamicCommentRepliesSnapshot {
        let replies = replies(for: comment)
        return DynamicCommentRepliesSnapshot(
            state: snapshot.replyStates[comment.id] ?? .idle,
            replies: replies,
            replyItems: replyItems(for: comment, replies: replies),
            hasMoreReplies: hasMoreReplies(for: comment, loadedCount: replies.count)
        )
    }

    func replyItems(for comment: Comment) -> [DynamicCommentReplyItem] {
        replyItems(for: comment, replies: replies(for: comment))
    }

    private func replyItems(for comment: Comment, replies: [Comment]) -> [DynamicCommentReplyItem] {
        let signature = DynamicCommentReplyItemSignature(rootComment: comment, replies: replies)
        if let cached = replyItemCache[comment.id], cached.signature == signature {
            return cached.items
        }

        let items = replies.map { DynamicCommentReplyItem(reply: $0, rootComment: comment) }
        replyItemCache[comment.id] = DynamicCommentReplyItemCacheEntry(signature: signature, items: items)
        return items
    }

    func hasMoreReplies(for comment: Comment) -> Bool {
        if let hasMore = snapshot.replyHasMore[comment.id] {
            return hasMore
        }
        let loadedCount = replies(for: comment).count
        return hasMoreReplies(for: comment, loadedCount: loadedCount)
    }

    private func hasMoreReplies(for comment: Comment, loadedCount: Int) -> Bool {
        if let hasMore = snapshot.replyHasMore[comment.id] {
            return hasMore
        }
        let totalCount = comment.replyCount ?? comment.replies?.count ?? loadedCount
        return loadedCount < totalCount
    }

    func replyState(for comment: Comment) -> LoadingState {
        snapshot.replyStates[comment.id] ?? .idle
    }

    func loadReplies(for comment: Comment) async {
        guard snapshot.replyThreads[comment.id] == nil else { return }
        let generation = nextReplyLoadGeneration(for: comment.id)
        updateSnapshot {
            $0.replyPages[comment.id] = 0
            $0.replyHasMore[comment.id] = true
        }
        _ = await loadReplyPage(for: comment, reset: true, generation: generation)
    }

    func reloadReplies(for comment: Comment) async {
        let generation = nextReplyLoadGeneration(for: comment.id)
        updateSnapshot {
            $0.replyThreads[comment.id] = nil
            $0.replyPages[comment.id] = 0
            $0.replyHasMore[comment.id] = true
        }
        replyItemCache[comment.id] = nil
        _ = await loadReplyPage(for: comment, reset: true, generation: generation)
    }

    func loadMoreReplies(for comment: Comment) async {
        guard snapshot.replyHasMore[comment.id] != false,
              !(snapshot.replyStates[comment.id]?.isLoading ?? false)
        else { return }
        let generation = replyLoadGenerations[comment.id] ?? nextReplyLoadGeneration(for: comment.id)
        _ = await loadReplyPage(for: comment, reset: false, generation: generation)
    }

    func dialogItems(for root: Comment, reply: Comment) -> [DynamicCommentDialogItem] {
        let key = dialogKey(root: root, reply: reply)
        let replies = dialogReplies(for: root, reply: reply)
        return dialogItems(for: root, key: key, replies: replies)
    }

    private func dialogItems(for root: Comment, key: String, replies: [Comment]) -> [DynamicCommentDialogItem] {
        let signature = DynamicCommentReplyItemSignature(rootComment: root, replies: replies)
        if let cached = dialogItemCache[key], cached.signature == signature {
            return cached.items
        }

        let items = replies.map(DynamicCommentDialogItem.init)
        dialogItemCache[key] = DynamicCommentDialogItemCacheEntry(signature: signature, items: items)
        return items
    }

    func dialogState(for root: Comment, reply: Comment) -> LoadingState {
        snapshot.dialogStates[dialogKey(root: root, reply: reply)] ?? .idle
    }

    func dialogSnapshot(for root: Comment, reply: Comment) -> DynamicCommentDialogSnapshot {
        let key = dialogKey(root: root, reply: reply)
        let replies = dialogReplies(for: root, reply: reply)
        return DynamicCommentDialogSnapshot(
            state: snapshot.dialogStates[key] ?? .idle,
            items: dialogItems(for: root, key: key, replies: replies)
        )
    }

    func loadDialog(for root: Comment, reply: Comment) async {
        let key = dialogKey(root: root, reply: reply)
        guard snapshot.dialogThreads[key] == nil else { return }
        let generation = nextDialogLoadGeneration(for: key)
        await loadDialogPage(for: root, reply: reply, generation: generation)
    }

    func reloadDialog(for root: Comment, reply: Comment) async {
        let key = dialogKey(root: root, reply: reply)
        let generation = nextDialogLoadGeneration(for: key)
        updateSnapshot { $0.dialogThreads[key] = nil }
        dialogItemCache[key] = nil
        await loadDialogPage(for: root, reply: reply, generation: generation)
    }

    private var commentOID: String? {
        item.commentOID
    }

    private var commentType: Int? {
        item.commentType
    }

    private func nextReplyLoadGeneration(for commentID: Int) -> Int {
        let generation = (replyLoadGenerations[commentID] ?? 0) &+ 1
        replyLoadGenerations[commentID] = generation
        return generation
    }

    private func nextDialogLoadGeneration(for key: String) -> Int {
        let generation = (dialogLoadGenerations[key] ?? 0) &+ 1
        dialogLoadGenerations[key] = generation
        return generation
    }

    private func loadReplyPage(
        for comment: Comment,
        reset: Bool,
        sort: CommentSort? = nil,
        generation: Int,
        cookieHeader: String? = nil
    ) async -> DynamicCommentRefreshOutcome {
        guard generation == replyLoadGenerations[comment.id] else { return .superseded }
        guard let oid = commentOID, let type = commentType else {
            updateSnapshot { $0.replyStates[comment.id] = .failed("这条动态没有返回评论入口") }
            return .failed
        }

        updateSnapshot { $0.replyStates[comment.id] = .loading }
        do {
            let nextPage = reset ? 1 : (snapshot.replyPages[comment.id] ?? 1) + 1
            let resolvedCookieHeader: String
            if let cookieHeader {
                resolvedCookieHeader = cookieHeader
            } else {
                resolvedCookieHeader = await api.interactionRequestContext().cookieHeader
            }
            guard generation == replyLoadGenerations[comment.id] else { return .superseded }
            let page = try await api.fetchCommentReplies(
                oid: oid,
                type: type,
                root: comment.rpid,
                page: nextPage,
                sort: sort,
                cookieHeader: resolvedCookieHeader
            )
            guard generation == replyLoadGenerations[comment.id] else { return .superseded }
            let fetchedReplies = filteredComments(page.replies ?? [])
            let existingReplies = reset
                ? filteredComments(comment.replies ?? [])
                : filteredComments(snapshot.replyThreads[comment.id] ?? comment.replies ?? [])
            let replies = uniqueComments(fetchedReplies + existingReplies)
            let totalCount = comment.replyCount ?? Int.max
            updateSnapshot {
                $0.replyThreads[comment.id] = replies
                $0.replyPages[comment.id] = nextPage
                $0.replyHasMore[comment.id] = !fetchedReplies.isEmpty && replies.count < totalCount
                $0.replyStates[comment.id] = .loaded
            }
            return .refreshed
        } catch {
            guard generation == replyLoadGenerations[comment.id] else { return .superseded }
            updateSnapshot {
                if reset {
                    let fallbackReplies = filteredComments(comment.replies ?? [])
                    $0.replyThreads[comment.id] = fallbackReplies
                    if fallbackReplies.isEmpty {
                        $0.replyStates[comment.id] = .failed(error.localizedDescription)
                    } else {
                        $0.replyHasMore[comment.id] = false
                        $0.replyStates[comment.id] = .loaded
                    }
                } else {
                    $0.replyHasMore[comment.id] = false
                    $0.replyStates[comment.id] = .loaded
                }
            }
            return .failed
        }
    }

    private func loadDialogPage(for root: Comment, reply: Comment, generation: Int) async {
        let key = dialogKey(root: root, reply: reply)
        guard generation == dialogLoadGenerations[key] else { return }
        guard let oid = commentOID, let type = commentType else {
            updateSnapshot { $0.dialogStates[key] = .failed("这条动态没有返回评论入口") }
            return
        }

        let fallbackReplies = filteredComments(localDialogReplies(root: root, reply: reply))

        guard let dialogID = reply.dialogID, dialogID > 0 else {
            updateSnapshot {
                $0.dialogThreads[key] = fallbackReplies
                $0.dialogStates[key] = .loaded
            }
            return
        }

        updateSnapshot { $0.dialogStates[key] = .loading }
        do {
            let context = await api.interactionRequestContext()
            guard generation == dialogLoadGenerations[key] else { return }
            let page = try await api.fetchCommentDialog(
                oid: oid,
                type: type,
                root: root.rpid,
                dialog: dialogID,
                cookieHeader: context.cookieHeader
            )
            guard generation == dialogLoadGenerations[key] else { return }
            let replies = uniqueComments(filteredComments(page.replies ?? []) + fallbackReplies)
            updateSnapshot {
                $0.dialogThreads[key] = replies.isEmpty ? fallbackReplies : replies
                $0.dialogStates[key] = .loaded
            }
        } catch {
            guard generation == dialogLoadGenerations[key] else { return }
            updateSnapshot {
                $0.dialogThreads[key] = fallbackReplies
                $0.dialogStates[key] = .failed(error.localizedDescription)
            }
        }
    }

    private func dialogReplies(for root: Comment, reply: Comment) -> [Comment] {
        let key = dialogKey(root: root, reply: reply)
        return snapshot.dialogThreads[key] ?? localDialogReplies(root: root, reply: reply)
    }

    private func dialogKey(root: Comment, reply: Comment) -> String {
        let dialogID = reply.dialogID ?? 0
        if dialogID > 0 {
            return "\(root.id)-\(dialogID)"
        }
        let parentID = reply.parentID ?? 0
        if parentID > 0 {
            return "\(root.id)-p-\(parentID)-\(reply.id)"
        }
        return "\(root.id)-r-\(reply.id)"
    }

    private func localDialogReplies(root: Comment, reply: Comment) -> [Comment] {
        let siblings = replies(for: root)
        let dialogID = reply.dialogID ?? 0
        if dialogID > 0 {
            let matches = siblings.filter {
                $0.dialogID == dialogID || $0.id == dialogID || $0.parentID == dialogID
            }
            let merged = uniqueComments([reply] + matches)
            if merged.count > 1 {
                return merged
            }
        }

        let parentID = reply.parentID ?? 0
        if parentID > 0 {
            let matches = siblings.filter {
                $0.parentID == parentID || $0.id == parentID || $0.id == reply.id
            }
            let merged = uniqueComments([reply] + matches)
            if merged.count > 1 {
                return merged
            }
        }

        return [reply]
    }

    private func filteredComments(_ values: [Comment]) -> [Comment] {
        guard blocksGoodsComments else { return values }
        return values.filter { !$0.containsGoodsPromotion }
    }

    private func uniqueComments(_ comments: [Comment]) -> [Comment] {
        var seen = Set<Int>()
        return comments.filter { seen.insert($0.id).inserted }
    }
}

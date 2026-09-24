import Foundation

@MainActor
extension VideoDetailCommentThreadRenderStore {
    func replyDisplays(
        for comment: Comment,
        replies: [Comment]
    ) -> [VideoDetailCommentReplyDisplayItem] {
        let signature = VideoDetailCommentReplyDisplaySignature(rootComment: comment, replies: replies)
        if let cached = replyDisplayCache[comment.id], cached.signature == signature {
            return cached.items
        }

        let items = VideoDetailCommentReplyDisplayItems.make(replies: replies, rootComment: comment)
        replyDisplayCache[comment.id] = VideoDetailCommentReplyDisplayCacheEntry(
            signature: signature,
            items: items
        )
        return items
    }

    func hasMoreReplies(for comment: Comment, loadedCount: Int) -> Bool {
        if let hasMore = snapshot.replyThreadHasMore[comment.id] {
            return hasMore
        }
        let totalCount = comment.replyCount ?? comment.replies?.count ?? loadedCount
        return loadedCount < totalCount
    }

    func dialogReplies(for root: Comment, reply: Comment, key: String) -> [Comment] {
        snapshot.dialogThreads[key]
            ?? VideoDetailCommentThreadResolver.localDialogReplies(
                reply,
                siblings: replies(for: root)
            )
    }

    func dialogDisplays(
        for root: Comment,
        key: String,
        replies: [Comment]
    ) -> [VideoDetailCommentDialogDisplayItem] {
        let signature = VideoDetailCommentReplyDisplaySignature(rootComment: root, replies: replies)
        if let cached = dialogDisplayCache[key], cached.signature == signature {
            return cached.items
        }

        let items = replies.map(VideoDetailCommentDialogDisplayItem.init(reply:))
        dialogDisplayCache[key] = VideoDetailCommentDialogDisplayCacheEntry(
            signature: signature,
            items: items
        )
        return items
    }
}

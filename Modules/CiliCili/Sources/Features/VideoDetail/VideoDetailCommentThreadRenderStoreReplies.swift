import Combine
import Foundation

@MainActor
extension VideoDetailCommentThreadRenderStore {
    func replies(for comment: Comment) -> [Comment] {
        snapshot.replyThreads[comment.id] ?? comment.replies ?? []
    }

    func repliesSnapshot(for comment: Comment) -> VideoDetailCommentThreadRepliesSnapshot {
        let replies = replies(for: comment)
        return VideoDetailCommentThreadRepliesSnapshot(
            state: snapshot.replyThreadStates[comment.id] ?? .idle,
            replies: replies,
            replyDisplays: replyDisplays(for: comment, replies: replies),
            hasMoreReplies: hasMoreReplies(for: comment, loadedCount: replies.count)
        )
    }

    func replyDisplays(for comment: Comment) -> [VideoDetailCommentReplyDisplayItem] {
        replyDisplays(for: comment, replies: replies(for: comment))
    }

    func hasMoreReplies(for comment: Comment) -> Bool {
        if let hasMore = snapshot.replyThreadHasMore[comment.id] {
            return hasMore
        }
        let loadedCount = replies(for: comment).count
        return hasMoreReplies(for: comment, loadedCount: loadedCount)
    }

    func replyState(for comment: Comment) -> LoadingState {
        snapshot.replyThreadStates[comment.id] ?? .idle
    }
}

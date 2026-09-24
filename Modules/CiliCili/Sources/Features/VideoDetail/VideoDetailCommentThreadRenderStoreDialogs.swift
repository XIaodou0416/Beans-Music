import Combine
import Foundation

@MainActor
extension VideoDetailCommentThreadRenderStore {
    func dialogReplies(for root: Comment, reply: Comment) -> [Comment] {
        let key = VideoDetailCommentThreadResolver.dialogKey(root: root, reply: reply)
        return dialogReplies(for: root, reply: reply, key: key)
    }

    func dialogState(for root: Comment, reply: Comment) -> LoadingState {
        let key = VideoDetailCommentThreadResolver.dialogKey(root: root, reply: reply)
        return snapshot.dialogThreadStates[key] ?? .idle
    }

    func dialogSnapshot(
        for root: Comment,
        reply: Comment
    ) -> VideoDetailCommentThreadDialogSnapshot {
        let key = VideoDetailCommentThreadResolver.dialogKey(root: root, reply: reply)
        let replies = dialogReplies(for: root, reply: reply, key: key)
        return VideoDetailCommentThreadDialogSnapshot(
            state: snapshot.dialogThreadStates[key] ?? .idle,
            items: dialogDisplays(for: root, key: key, replies: replies)
        )
    }
}

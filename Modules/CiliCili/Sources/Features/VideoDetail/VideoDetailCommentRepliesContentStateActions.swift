import Foundation

@MainActor
struct CommentRepliesContentStateActions {
    let rootComment: Comment
    let reloadReplies: (Comment) async -> Void

    func reloadRepliesAction() {
        Task { await reloadReplies(rootComment) }
    }
}

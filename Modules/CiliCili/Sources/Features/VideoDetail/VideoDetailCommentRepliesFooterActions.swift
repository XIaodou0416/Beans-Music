import Foundation

@MainActor
struct CommentRepliesFooterActions {
    let rootComment: Comment
    let loadMoreReplies: (Comment) async -> Void

    func performLoadMoreReplies() {
        Task { await loadMoreReplies(rootComment) }
    }
}

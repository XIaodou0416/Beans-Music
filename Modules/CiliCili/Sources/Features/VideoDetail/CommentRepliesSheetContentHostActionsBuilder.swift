import Foundation

@MainActor
struct CommentRepliesSheetContentHostActionsBuilder {
    let rootComment: Comment
    let loadReplies: (Comment) async -> Void

    var actions: CommentRepliesSheetContentHostActions {
        CommentRepliesSheetContentHostActions(
            rootComment: rootComment,
            loadReplies: loadReplies
        )
    }
}

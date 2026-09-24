import Foundation

@MainActor
struct CommentDialogSheetActionsBuilder {
    let rootComment: Comment
    let focusReply: Comment
    let loadDialog: (Comment, Comment) async -> Void

    var actions: CommentDialogSheetActions {
        CommentDialogSheetActions(
            rootComment: rootComment,
            focusReply: focusReply,
            loadDialog: loadDialog
        )
    }
}

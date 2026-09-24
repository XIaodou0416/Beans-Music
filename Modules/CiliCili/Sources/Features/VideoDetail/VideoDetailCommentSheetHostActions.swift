import Foundation

@MainActor
struct CommentRepliesSheetContentHostActions {
    let rootComment: Comment
    let loadReplies: (Comment) async -> Void

    func load() async {
        await loadReplies(rootComment)
    }
}

@MainActor
struct CommentDialogSheetActions {
    let rootComment: Comment
    let focusReply: Comment
    let loadDialog: (Comment, Comment) async -> Void

    func load() async {
        await loadDialog(rootComment, focusReply)
    }
}

import Foundation

nonisolated struct VideoDetailCommentReplyDisplayItem: Identifiable, Equatable {
    let id: Int
    let reply: Comment
    let display: VideoDetailCommentDisplayModel
    let canShowDialog: Bool
}

nonisolated enum VideoDetailCommentReplyDisplayItems {
    static func make(replies: [Comment], rootComment: Comment) -> [VideoDetailCommentReplyDisplayItem] {
        replies.map { reply in
            VideoDetailCommentReplyDisplayItem(
                id: reply.id,
                reply: reply,
                display: VideoDetailCommentDisplayModel(comment: reply),
                canShowDialog: VideoDetailCommentReplyDialogEligibility.canShowDialog(
                    for: reply,
                    rootComment: rootComment
                )
            )
        }
    }
}

import Foundation

nonisolated struct VideoDetailCommentReplyDisplaySignature: Equatable {
    let rootID: Int
    let replies: [Reply]

    init(rootComment: Comment, replies: [Comment]) {
        rootID = rootComment.id
        self.replies = replies.map(Reply.init)
    }

    struct Reply: Equatable {
        let id: Int
        let parentID: Int?
        let dialogID: Int?
        let message: String?

        init(_ reply: Comment) {
            id = reply.id
            parentID = reply.parentID
            dialogID = reply.dialogID
            message = reply.content?.message
        }
    }
}

nonisolated struct VideoDetailCommentReplyDisplayCacheEntry {
    let signature: VideoDetailCommentReplyDisplaySignature
    let items: [VideoDetailCommentReplyDisplayItem]
}

nonisolated struct VideoDetailCommentDialogDisplayCacheEntry {
    let signature: VideoDetailCommentReplyDisplaySignature
    let items: [VideoDetailCommentDialogDisplayItem]
}

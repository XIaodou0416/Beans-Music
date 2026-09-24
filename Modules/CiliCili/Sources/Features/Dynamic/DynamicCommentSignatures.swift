nonisolated struct DynamicCommentListSignature: Equatable {
    let items: [DynamicCommentSignature]

    init(_ comments: [Comment]) {
        items = comments.map(DynamicCommentSignature.init)
    }
}

nonisolated struct DynamicCommentSignature: Equatable {
    let id: Int
    let parentID: Int?
    let dialogID: Int?
    let authorName: String?
    let avatar: String?
    let message: String?
    let like: Int?
    let ctime: Int?
    let replyCount: Int?
    let likeState: Int?
    let pictureURLs: [String]
    let replyPreviews: [DynamicCommentReplyPreviewSignature]

    init(_ comment: Comment) {
        id = comment.id
        parentID = comment.parentID
        dialogID = comment.dialogID
        authorName = comment.member?.uname
        avatar = comment.member?.avatar
        message = comment.content?.message
        like = comment.like
        ctime = comment.ctime
        replyCount = comment.replyCount
        likeState = comment.likeState
        pictureURLs = (comment.content?.pictures ?? []).map(\.url)
        replyPreviews = (comment.replies ?? [])
            .prefix(2)
            .map(DynamicCommentReplyPreviewSignature.init)
    }
}

nonisolated struct DynamicCommentReplyPreviewSignature: Equatable {
    let id: Int
    let authorName: String?
    let message: String?

    init(_ comment: Comment) {
        id = comment.id
        authorName = comment.member?.uname
        message = comment.content?.message
    }
}

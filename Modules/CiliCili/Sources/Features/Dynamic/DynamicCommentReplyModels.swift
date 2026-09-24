struct DynamicCommentRepliesSnapshot: Equatable {
    let state: LoadingState
    let replies: [Comment]
    let replyItems: [DynamicCommentReplyItem]
    let hasMoreReplies: Bool

    var hasLoadedReplies: Bool {
        !replies.isEmpty
    }
}

struct DynamicCommentDialogSnapshot: Equatable {
    let state: LoadingState
    let items: [DynamicCommentDialogItem]
}

struct DynamicCommentReplyStoreSnapshot {
    var replyThreads: [Int: [Comment]] = [:]
    var replyStates: [Int: LoadingState] = [:]
    var replyPages: [Int: Int] = [:]
    var replyHasMore: [Int: Bool] = [:]
    var dialogThreads: [String: [Comment]] = [:]
    var dialogStates: [String: LoadingState] = [:]

    var changeSignature: DynamicCommentReplyStoreChangeSignature {
        DynamicCommentReplyStoreChangeSignature(
            replyThreadSignatures: replyThreads.mapValues(DynamicCommentListSignature.init),
            replyStates: replyStates,
            replyPages: replyPages,
            replyHasMore: replyHasMore,
            dialogThreadSignatures: dialogThreads.mapValues(DynamicCommentListSignature.init),
            dialogStates: dialogStates
        )
    }
}

nonisolated struct DynamicCommentReplyStoreChangeSignature: Equatable {
    let replyThreadSignatures: [Int: DynamicCommentListSignature]
    let replyStates: [Int: LoadingState]
    let replyPages: [Int: Int]
    let replyHasMore: [Int: Bool]
    let dialogThreadSignatures: [String: DynamicCommentListSignature]
    let dialogStates: [String: LoadingState]
}

struct DynamicCommentReplyItem: Identifiable, Equatable {
    let id: Int
    let reply: Comment
    let display: DynamicCommentRowDisplayModel
    let canShowDialog: Bool

    init(reply: Comment, rootComment: Comment) {
        id = reply.id
        self.reply = reply
        display = DynamicCommentRowDisplayModel(comment: reply)
        canShowDialog = Self.canShowDialog(for: reply, rootComment: rootComment)
    }

    private static func canShowDialog(for reply: Comment, rootComment: Comment) -> Bool {
        guard reply.id != rootComment.id else { return false }
        if let dialogID = reply.dialogID, dialogID > 0 {
            return true
        }
        if let parentID = reply.parentID, parentID > 0, parentID != rootComment.rpid {
            return true
        }
        return DynamicCommentTextBuilder.hasReplyTarget(in: reply.content?.message)
    }
}

struct DynamicCommentDialogItem: Identifiable, Equatable {
    let id: Int
    let reply: Comment
    let display: DynamicCommentRowDisplayModel

    init(reply: Comment) {
        id = reply.id
        self.reply = reply
        display = DynamicCommentRowDisplayModel(comment: reply)
    }
}

nonisolated struct DynamicCommentReplyItemSignature: Equatable {
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

struct DynamicCommentReplyItemCacheEntry {
    let signature: DynamicCommentReplyItemSignature
    let items: [DynamicCommentReplyItem]
}

struct DynamicCommentDialogItemCacheEntry {
    let signature: DynamicCommentReplyItemSignature
    let items: [DynamicCommentDialogItem]
}

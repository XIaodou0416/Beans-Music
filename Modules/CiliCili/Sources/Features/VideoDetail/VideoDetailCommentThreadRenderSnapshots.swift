import Foundation

struct VideoDetailCommentThreadRepliesSnapshot: Equatable {
    let state: LoadingState
    let replies: [Comment]
    let replyDisplays: [VideoDetailCommentReplyDisplayItem]
    let hasMoreReplies: Bool

    var hasLoadedReplies: Bool {
        !replies.isEmpty
    }
}

struct VideoDetailCommentThreadDialogSnapshot: Equatable {
    let state: LoadingState
    let items: [VideoDetailCommentDialogDisplayItem]
}

struct VideoDetailCommentThreadRenderSnapshot: Equatable {
    var replyThreads: [Int: [Comment]]
    var replyThreadStates: [Int: LoadingState]
    var replyThreadHasMore: [Int: Bool]
    var dialogThreads: [String: [Comment]]
    var dialogThreadStates: [String: LoadingState]

    init(
        replyThreads: [Int: [Comment]] = [:],
        replyThreadStates: [Int: LoadingState] = [:],
        replyThreadHasMore: [Int: Bool] = [:],
        dialogThreads: [String: [Comment]] = [:],
        dialogThreadStates: [String: LoadingState] = [:]
    ) {
        self.replyThreads = replyThreads
        self.replyThreadStates = replyThreadStates
        self.replyThreadHasMore = replyThreadHasMore
        self.dialogThreads = dialogThreads
        self.dialogThreadStates = dialogThreadStates
    }

    var changeSignature: VideoDetailCommentThreadRenderChangeSignature {
        VideoDetailCommentThreadRenderChangeSignature(
            replyThreads: replyThreads.mapValues(VideoDetailCommentListSignature.init),
            replyThreadStates: replyThreadStates,
            replyThreadHasMore: replyThreadHasMore,
            dialogThreads: dialogThreads.mapValues(VideoDetailCommentListSignature.init),
            dialogThreadStates: dialogThreadStates
        )
    }
}

nonisolated struct VideoDetailCommentThreadRenderChangeSignature: Equatable {
    let replyThreads: [Int: VideoDetailCommentListSignature]
    let replyThreadStates: [Int: LoadingState]
    let replyThreadHasMore: [Int: Bool]
    let dialogThreads: [String: VideoDetailCommentListSignature]
    let dialogThreadStates: [String: LoadingState]
}

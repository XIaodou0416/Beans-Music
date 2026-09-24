import Foundation

struct VideoDetailCommentThreadAnchor: Equatable {
    let contextKey: String
    let rootID: Int
}

struct VideoDetailCommentThreadState {
    var replyThreads: [Int: [Comment]] = [:]
    var replyThreadStates: [Int: LoadingState] = [:]
    var replyThreadPages: [Int: Int] = [:]
    var replyThreadHasMore: [Int: Bool] = [:]
    var replyThreadLoadTokens: [Int: UUID] = [:]
    var dialogThreads: [String: [Comment]] = [:]
    var dialogThreadStates: [String: LoadingState] = [:]
    var dialogThreadLoadTokens: [String: UUID] = [:]
    var deepLinkAnchor: VideoDetailCommentThreadAnchor?
}

extension VideoDetailViewModel {
    var replyThreads: [Int: [Comment]] {
        get { commentThreadState.replyThreads }
        set {
            commentThreadState.replyThreads = newValue
            syncCommentThreadRenderStore()
        }
    }

    var replyThreadStates: [Int: LoadingState] {
        get { commentThreadState.replyThreadStates }
        set {
            commentThreadState.replyThreadStates = newValue
            syncCommentThreadRenderStore()
        }
    }

    var replyThreadPages: [Int: Int] {
        get { commentThreadState.replyThreadPages }
        set { commentThreadState.replyThreadPages = newValue }
    }

    var replyThreadHasMore: [Int: Bool] {
        get { commentThreadState.replyThreadHasMore }
        set {
            commentThreadState.replyThreadHasMore = newValue
            syncCommentThreadRenderStore()
        }
    }

    var replyThreadLoadTokens: [Int: UUID] {
        get { commentThreadState.replyThreadLoadTokens }
        set { commentThreadState.replyThreadLoadTokens = newValue }
    }

    var dialogThreads: [String: [Comment]] {
        get { commentThreadState.dialogThreads }
        set {
            commentThreadState.dialogThreads = newValue
            syncCommentThreadRenderStore()
        }
    }

    var dialogThreadStates: [String: LoadingState] {
        get { commentThreadState.dialogThreadStates }
        set {
            commentThreadState.dialogThreadStates = newValue
            syncCommentThreadRenderStore()
        }
    }

    var dialogThreadLoadTokens: [String: UUID] {
        get { commentThreadState.dialogThreadLoadTokens }
        set { commentThreadState.dialogThreadLoadTokens = newValue }
    }
}

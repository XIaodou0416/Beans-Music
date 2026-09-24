import Foundation

struct VideoDetailCommentsRenderSnapshot: Equatable {
    var detail: VideoItem?
    var comments: [Comment]
    var commentItems: [VideoDetailCommentDisplayItem]
    var state: LoadingState
    var loadMoreState: LoadingState
    var selectedSort: CommentSort
    var didCompleteInitialLoad: Bool
    var hasMoreComments: Bool
    var replyCountText: String?
    private(set) var commentsSignature: VideoDetailCommentListSignature

    init(
        detail: VideoItem? = nil,
        comments: [Comment] = [],
        state: LoadingState = .idle,
        loadMoreState: LoadingState = .idle,
        selectedSort: CommentSort = .hot,
        didCompleteInitialLoad: Bool = false,
        hasMoreComments: Bool = false,
        replyCountText: String? = nil
    ) {
        self.detail = detail
        self.comments = comments
        self.commentItems = VideoDetailCommentRenderSnapshotFactory.makeCommentItems(comments)
        self.commentsSignature = VideoDetailCommentListSignature(comments)
        self.state = state
        self.loadMoreState = loadMoreState
        self.selectedSort = selectedSort
        self.didCompleteInitialLoad = didCompleteInitialLoad
        self.hasMoreComments = hasMoreComments
        self.replyCountText = replyCountText ?? VideoDetailCommentRenderSnapshotFactory.makeReplyCountText(detail: detail)
    }

    var changeSignature: VideoDetailCommentsRenderChangeSignature {
        VideoDetailCommentsRenderChangeSignature(
            detailBVID: detail?.bvid,
            detailReplyCount: detail?.stat?.reply,
            commentsSignature: commentsSignature,
            state: state,
            loadMoreState: loadMoreState,
            selectedSort: selectedSort,
            didCompleteInitialLoad: didCompleteInitialLoad,
            hasMoreComments: hasMoreComments,
            replyCountText: replyCountText
        )
    }

    mutating func setComments(_ comments: [Comment]) {
        self.comments = comments
        commentItems = VideoDetailCommentRenderSnapshotFactory.makeCommentItems(comments)
        commentsSignature = VideoDetailCommentListSignature(comments)
    }

    static func makeCommentItems(_ comments: [Comment]) -> [VideoDetailCommentDisplayItem] {
        VideoDetailCommentRenderSnapshotFactory.makeCommentItems(comments)
    }

    static func makeReplyCountText(detail: VideoItem?) -> String? {
        VideoDetailCommentRenderSnapshotFactory.makeReplyCountText(detail: detail)
    }
}

import Foundation

nonisolated struct VideoDetailCommentsRenderChangeSignature: Equatable {
    let detailBVID: String?
    let detailReplyCount: Int?
    let commentsSignature: VideoDetailCommentListSignature
    let state: LoadingState
    let loadMoreState: LoadingState
    let selectedSort: CommentSort
    let didCompleteInitialLoad: Bool
    let hasMoreComments: Bool
    let replyCountText: String?
}

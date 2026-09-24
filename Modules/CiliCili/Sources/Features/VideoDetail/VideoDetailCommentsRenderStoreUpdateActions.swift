import Combine
import Foundation

@MainActor
extension VideoDetailCommentsRenderStore {
    func update(
        detail: VideoItem,
        comments: [Comment],
        state: LoadingState,
        loadMoreState: LoadingState,
        selectedSort: CommentSort,
        didCompleteInitialLoad: Bool,
        hasMoreComments: Bool
    ) {
        setSnapshot(
            VideoDetailCommentsRenderSnapshot(
                detail: detail,
                comments: comments,
                state: state,
                loadMoreState: loadMoreState,
                selectedSort: selectedSort,
                didCompleteInitialLoad: didCompleteInitialLoad,
                hasMoreComments: hasMoreComments
            )
        )
    }

    func updateDetail(_ detail: VideoItem) {
        updateSnapshot {
            $0.detail = detail
            $0.replyCountText = VideoDetailCommentsRenderSnapshot.makeReplyCountText(detail: detail)
        }
    }

    func updateComments(_ comments: [Comment]) {
        updateSnapshot { $0.setComments(comments) }
    }
}

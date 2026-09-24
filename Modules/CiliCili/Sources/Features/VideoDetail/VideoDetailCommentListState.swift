import Foundation

struct VideoDetailCommentListState {
    var comments: [Comment] = []
    var state: LoadingState = .idle
    var loadMoreState: LoadingState = .idle
    var didCompleteInitialLoad = false
    var selectedSort: CommentSort = .hot
    var cursor = ""
    var end = false
    var pageLoadGeneration = 0
}

extension VideoDetailViewModel {
    var comments: [Comment] {
        get { commentListState.comments }
        set {
            commentListState.comments = newValue
            commentsRenderStore.updateComments(newValue)
        }
    }

    var commentState: LoadingState {
        get { commentListState.state }
        set {
            commentListState.state = newValue
            commentsRenderStore.updateState(newValue)
        }
    }

    var commentLoadMoreState: LoadingState {
        get { commentListState.loadMoreState }
        set {
            commentListState.loadMoreState = newValue
            commentsRenderStore.updateLoadMoreState(newValue)
        }
    }

    var didCompleteInitialCommentLoad: Bool {
        get { commentListState.didCompleteInitialLoad }
        set {
            commentListState.didCompleteInitialLoad = newValue
            commentsRenderStore.updateDidCompleteInitialLoad(newValue)
        }
    }

    var selectedCommentSort: CommentSort {
        get { commentListState.selectedSort }
        set {
            commentListState.selectedSort = newValue
            commentsRenderStore.updateSelectedSort(newValue)
        }
    }

    var commentCursor: String {
        get { commentListState.cursor }
        set { commentListState.cursor = newValue }
    }

    var commentsEnd: Bool {
        get { commentListState.end }
        set {
            commentListState.end = newValue
            commentsRenderStore.updateHasMoreComments(!newValue)
        }
    }

    var commentPageLoadGeneration: Int {
        get { commentListState.pageLoadGeneration }
        set { commentListState.pageLoadGeneration = newValue }
    }
}

import Foundation

extension VideoDetailViewModel {
    func loadMoreComments() async {
        guard !commentState.isLoading,
              !commentLoadMoreState.isLoading,
              !commentsEnd
        else { return }
        await loadCommentsPage(presentsErrors: false, emptyPageSkipLimit: 2)
    }

    func retryComments() async {
        cancelCommentsLoadingTask()
        await loadInitialComments()
    }

    func selectCommentSort(_ sort: CommentSort) async {
        guard selectedCommentSort != sort else { return }
        selectedCommentSort = sort
        cancelCommentsLoadingTask()
        await loadInitialComments()
    }

}

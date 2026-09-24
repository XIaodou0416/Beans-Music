import Foundation

@MainActor
struct VideoDetailCommentsSectionFooterActions {
    let loadMoreComments: () async -> Void

    func loadMore() async {
        await loadMoreComments()
    }

    func retryLoadMoreComments() {
        Task { await loadMoreComments() }
    }
}

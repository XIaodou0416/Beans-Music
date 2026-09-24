import Foundation

extension VideoDetailViewModel {
    func failCommentPageLoad(_ error: Error, presentsErrors: Bool) {
        if presentsErrors || comments.isEmpty {
            commentState = .failed(error.localizedDescription)
            commentLoadMoreState = .idle
        } else {
            commentState = .loaded
            commentsEnd = true
            commentLoadMoreState = .idle
        }
    }
}

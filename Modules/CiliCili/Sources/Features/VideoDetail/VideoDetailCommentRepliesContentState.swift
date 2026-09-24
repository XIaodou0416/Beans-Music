import Foundation

enum CommentRepliesContentState {
    case loading
    case failed(String)
    case empty
    case loaded

    init(snapshot: VideoDetailCommentThreadRepliesSnapshot) {
        if snapshot.replies.isEmpty && snapshot.state.isLoading {
            self = .loading
        } else if snapshot.replies.isEmpty, case .failed(let message) = snapshot.state {
            self = .failed(message)
        } else if snapshot.replies.isEmpty {
            self = .empty
        } else {
            self = .loaded
        }
    }
}

import SwiftUI

enum CommentsSectionContentState {
    case loading
    case failed(String)
    case empty
    case reloadPrompt
    case spacer
    case loaded

    init(
        store: VideoDetailCommentsRenderStore,
        shouldShowLoadingPlaceholder: Bool
    ) {
        if store.comments.isEmpty && shouldShowLoadingPlaceholder {
            self = .loading
        } else if store.comments.isEmpty, case .failed(let message) = store.state {
            self = .failed(message)
        } else if store.shouldShowEmptyCommentsState {
            self = .empty
        } else if store.shouldShowCommentReloadPrompt {
            self = .reloadPrompt
        } else if store.comments.isEmpty {
            self = .spacer
        } else {
            self = .loaded
        }
    }
}

import SwiftUI

struct CommentDialogStateContent: View {
    let snapshot: VideoDetailCommentThreadDialogSnapshot
    let focusReplyID: Int
    let actions: CommentDialogStateContentActions

    init(
        snapshot: VideoDetailCommentThreadDialogSnapshot,
        focusReplyID: Int,
        reloadDialog: @escaping () async -> Void
    ) {
        self.snapshot = snapshot
        self.focusReplyID = focusReplyID
        actions = CommentDialogStateContentActions(reloadDialog: reloadDialog)
    }

    var body: some View {
        switch contentState {
        case .loading:
            CommentDialogLoadingContent()
        case .failed(let message):
            CommentDialogErrorContent(message: message, retry: actions.reloadDialogAction)
        case .empty:
            CommentDialogEmptyContent()
        case .loaded:
            CommentDialogLoadedContent(
                items: snapshot.items,
                focusReplyID: focusReplyID,
                footerFailureMessage: footerFailureMessage,
                retryDialog: actions.reloadDialogAction
            )
        }
    }

    private var contentState: CommentDialogContentState {
        if snapshot.items.isEmpty && snapshot.state.isLoading {
            return .loading
        }
        if snapshot.items.isEmpty, case .failed(let message) = snapshot.state {
            return .failed(message)
        }
        if snapshot.items.isEmpty {
            return .empty
        }
        return .loaded
    }

    private var footerFailureMessage: String? {
        if case .failed(let message) = snapshot.state {
            return message
        }
        return nil
    }
}

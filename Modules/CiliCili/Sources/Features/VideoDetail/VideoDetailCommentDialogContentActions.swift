import Foundation

@MainActor
struct CommentDialogStateContentActions {
    let reloadDialog: () async -> Void

    func reloadDialogAction() {
        Task { await reloadDialog() }
    }
}

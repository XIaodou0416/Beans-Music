import Foundation

enum CommentDialogContentState {
    case loading
    case failed(String)
    case empty
    case loaded
}

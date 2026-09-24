import Foundation

nonisolated struct VideoDetailCommentListSignature: Equatable {
    let items: [VideoDetailCommentSignature]

    init(_ comments: [Comment]) {
        items = comments.map(VideoDetailCommentSignature.init)
    }
}

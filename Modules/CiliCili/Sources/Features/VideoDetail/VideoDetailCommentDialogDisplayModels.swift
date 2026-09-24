import Foundation

nonisolated struct VideoDetailCommentDialogDisplayItem: Identifiable, Equatable {
    let id: Int
    let reply: Comment
    let display: VideoDetailCommentDisplayModel

    init(reply: Comment) {
        id = reply.id
        self.reply = reply
        display = VideoDetailCommentDisplayModel(comment: reply)
    }
}

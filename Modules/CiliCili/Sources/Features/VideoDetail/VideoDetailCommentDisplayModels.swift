import Foundation

nonisolated struct VideoDetailCommentDisplayItem: Identifiable, Equatable {
    let id: Int
    let comment: Comment
    let display: VideoDetailCommentDisplayModel

    init(comment: Comment) {
        id = comment.id
        self.comment = comment
        display = VideoDetailCommentDisplayModel(comment: comment)
    }
}

nonisolated struct VideoDetailCommentDisplayModel: Equatable {
    let authorName: String
    let authorOwner: VideoOwner?
    let avatarURLString: String?
    let timeText: String
    let likeText: String
    let isLiked: Bool
    let replyPreviews: [Comment]
    let visibleReplyCount: Int
    let pictures: [DynamicImageItem]

    init(comment: Comment) {
        authorName = Self.displayName(comment.member?.uname)
        authorOwner = comment.member?.videoOwner
        avatarURLString = comment.member?.avatar
        timeText = BiliFormatters.relativeTime(comment.ctime)
        likeText = BiliFormatters.compactCount(comment.like)
        isLiked = comment.likeState == 1
        replyPreviews = Array((comment.replies ?? []).prefix(2))
        visibleReplyCount = comment.replyCount ?? comment.replies?.count ?? 0
        pictures = comment.content?.pictures ?? []
    }

    nonisolated func isVideoUploader(ownerMID: Int?) -> Bool {
        guard let ownerMID, ownerMID > 0 else { return false }
        return authorOwner?.mid == ownerMID
    }

    private static func displayName(_ name: String?) -> String {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedName.isEmpty ? "Unknown" : trimmedName
    }
}

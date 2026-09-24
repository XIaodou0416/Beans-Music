import Foundation

struct DynamicCommentRowItem: Identifiable, Equatable {
    let id: Int
    let comment: Comment
    let display: DynamicCommentRowDisplayModel

    init(comment: Comment) {
        id = comment.id
        self.comment = comment
        display = DynamicCommentRowDisplayModel(comment: comment)
    }
}

struct DynamicCommentRowDisplayModel: Equatable {
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

    private static func displayName(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Unknown" : trimmed
    }
}

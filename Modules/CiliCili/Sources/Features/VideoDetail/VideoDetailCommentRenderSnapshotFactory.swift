import Foundation

struct VideoDetailCommentRenderSnapshotFactory {
    static func makeCommentItems(_ comments: [Comment]) -> [VideoDetailCommentDisplayItem] {
        comments.map(VideoDetailCommentDisplayItem.init(comment:))
    }

    static func makeReplyCountText(detail: VideoItem?) -> String? {
        guard let reply = detail?.stat?.reply else { return nil }
        return BiliFormatters.compactCount(reply)
    }
}

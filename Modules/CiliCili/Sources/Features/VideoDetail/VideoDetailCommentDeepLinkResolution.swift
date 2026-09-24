import Foundation

nonisolated enum VideoDetailCommentDeepLinkResolution {
    static let repliesPerPage = 20
    static let maximumTargetSearchPages = 8

    static func additionalPageNumbers(
        replyCount: Int?,
        knownReplyIDs: Set<Int>,
        targetReplyID: Int?
    ) -> [Int] {
        guard let targetReplyID,
              targetReplyID > 0,
              !knownReplyIDs.contains(targetReplyID)
        else {
            return []
        }

        let totalPages: Int
        if let replyCount, replyCount > 0 {
            totalPages = max(1, Int(ceil(Double(replyCount) / Double(repliesPerPage))))
        } else {
            totalPages = maximumTargetSearchPages
        }
        let lastPage = min(totalPages, maximumTargetSearchPages)
        guard lastPage >= 2 else { return [] }
        return Array(2...lastPage)
    }

    static func focusedReplyID(
        requestedReplyID: Int?,
        rootID: Int,
        replies: [Comment]
    ) -> Int? {
        guard let requestedReplyID,
              requestedReplyID > 0,
              requestedReplyID != rootID,
              replies.contains(where: { $0.id == requestedReplyID })
        else {
            return nil
        }
        return requestedReplyID
    }

    static func hasMoreReplies(
        replyCount: Int?,
        loadedReplyCount: Int,
        reachedEmptyPage: Bool
    ) -> Bool {
        guard !reachedEmptyPage else { return false }
        guard let replyCount else { return true }
        return loadedReplyCount < replyCount
    }
}

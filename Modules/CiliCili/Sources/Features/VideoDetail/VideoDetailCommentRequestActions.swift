import Foundation

extension VideoDetailViewModel {
    func fetchCommentsWithTimeout(
        target: VideoDetailCommentTarget,
        cursor: String,
        sort: CommentSort
    ) async throws -> CommentPage {
        try await withThrowingTaskGroup(of: CommentPage.self) { group in
            group.addTask(priority: .userInitiated) {
                try await self.api.fetchComments(
                    oid: target.oid,
                    type: target.type,
                    cursor: cursor,
                    sort: sort
                )
            }
            group.addTask(priority: .utility) {
                try await Task.sleep(nanoseconds: 8_000_000_000)
                throw BiliAPIError.api(code: -1, message: "评论加载超时，请稍后重试")
            }
            guard let page = try await group.next() else {
                group.cancelAll()
                throw BiliAPIError.emptyData
            }
            group.cancelAll()
            return page
        }
    }
}

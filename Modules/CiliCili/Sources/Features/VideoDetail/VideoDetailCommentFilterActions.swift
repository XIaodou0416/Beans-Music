import Foundation

extension VideoDetailViewModel {
    func appendUniqueComments(_ more: [Comment]) {
        let existing = Set(comments.map(\.id))
        comments.append(contentsOf: more.filter { !existing.contains($0.id) })
    }

    func filteredComments(_ values: [Comment]) -> [Comment] {
        guard libraryStore.blocksGoodsComments else { return values }
        return values.filter { !$0.containsGoodsPromotion }
    }

    func refilterLoadedComments() {
        guard !isPlaybackInvalidatedForNavigation else { return }
        if libraryStore.blocksGoodsComments {
            comments = filteredComments(comments)
            replyThreads = replyThreads.mapValues(filteredComments)
            dialogThreads = dialogThreads.mapValues(filteredComments)
        } else {
            let reloadTask = Task { @MainActor [weak self] in
                guard let self, !self.isPlaybackInvalidatedForNavigation else { return }
                await self.reloadCommentRelatedData()
            }
            trackBackgroundTask(reloadTask)
        }
    }

    func reloadCommentRelatedData() async {
        guard !isPlaybackInvalidatedForNavigation else { return }
        await loadInitialComments()
    }

    func dialogKey(root: Comment, reply: Comment) -> String {
        VideoDetailCommentThreadResolver.dialogKey(root: root, reply: reply)
    }

    func localDialogReplies(root: Comment, reply: Comment) -> [Comment] {
        VideoDetailCommentThreadResolver.localDialogReplies(reply, siblings: replies(for: root))
    }

    func uniqueComments(_ comments: [Comment]) -> [Comment] {
        VideoDetailCommentThreadResolver.uniqueComments(comments)
    }
}

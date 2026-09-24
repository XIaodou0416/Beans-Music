import Foundation

nonisolated struct VideoDetailCommentDeepLinkLoadResult: Equatable {
    let rootComment: Comment
    let focusedReplyID: Int?
}

extension VideoDetailViewModel {
    func loadCommentRoot(for anchor: VideoCommentAnchor) async -> VideoDetailCommentDeepLinkLoadResult? {
        guard let target = commentTarget else { return nil }

        do {
            let page = try await api.fetchCommentReplies(
                oid: target.oid,
                type: target.type,
                root: anchor.rootID,
                page: 1,
                sort: .time
            )
            guard !Task.isCancelled,
                  isCurrentCommentTarget(target)
            else {
                return nil
            }

            guard let rootComment = page.root
                ?? page.replies?.first(where: { $0.id == anchor.rootID })
            else {
                return nil
            }

            var rawReplies = page.replies ?? []
            var replies = uniqueComments(filteredComments(rawReplies))
            var lastLoadedPage = 1
            var reachedEmptyPage = rawReplies.isEmpty
            let additionalPages = VideoDetailCommentDeepLinkResolution.additionalPageNumbers(
                replyCount: rootComment.replyCount,
                knownReplyIDs: Set(replies.map(\.id)),
                targetReplyID: anchor.secondaryID
            )

            for pageNumber in additionalPages {
                guard VideoDetailCommentDeepLinkResolution.focusedReplyID(
                    requestedReplyID: anchor.secondaryID,
                    rootID: rootComment.id,
                    replies: replies
                ) == nil
                else {
                    break
                }

                do {
                    let nextPage = try await api.fetchCommentReplies(
                        oid: target.oid,
                        type: target.type,
                        root: anchor.rootID,
                        page: pageNumber,
                        sort: .time
                    )
                    guard !Task.isCancelled,
                          isCurrentCommentTarget(target)
                    else {
                        return nil
                    }

                    let nextRawReplies = nextPage.replies ?? []
                    guard !nextRawReplies.isEmpty else {
                        reachedEmptyPage = true
                        break
                    }
                    rawReplies += nextRawReplies
                    replies = uniqueComments(filteredComments(rawReplies))
                    lastLoadedPage = pageNumber
                } catch {
                    break
                }
            }

            cacheDeepLinkedReplyThread(
                rootComment: rootComment,
                replies: replies,
                lastLoadedPage: lastLoadedPage,
                reachedEmptyPage: reachedEmptyPage,
                target: target
            )
            return VideoDetailCommentDeepLinkLoadResult(
                rootComment: rootComment,
                focusedReplyID: VideoDetailCommentDeepLinkResolution.focusedReplyID(
                    requestedReplyID: anchor.secondaryID,
                    rootID: rootComment.id,
                    replies: replies
                )
            )
        } catch {
            return nil
        }
    }

    private func cacheDeepLinkedReplyThread(
        rootComment: Comment,
        replies: [Comment],
        lastLoadedPage: Int,
        reachedEmptyPage: Bool,
        target: VideoDetailCommentTarget
    ) {
        commentThreadState.deepLinkAnchor = VideoDetailCommentThreadAnchor(
            contextKey: target.contextKey,
            rootID: rootComment.id
        )
        replyThreads[rootComment.id] = replies
        replyThreadPages[rootComment.id] = lastLoadedPage
        replyThreadHasMore[rootComment.id] = VideoDetailCommentDeepLinkResolution.hasMoreReplies(
            replyCount: rootComment.replyCount,
            loadedReplyCount: replies.count,
            reachedEmptyPage: reachedEmptyPage
        )
        replyThreadStates[rootComment.id] = .loaded
    }

    func replies(for comment: Comment) -> [Comment] {
        replyThreads[comment.id] ?? comment.replies ?? []
    }

    func hasMoreReplies(for comment: Comment) -> Bool {
        if let hasMore = replyThreadHasMore[comment.id] {
            return hasMore
        }
        let loadedCount = replies(for: comment).count
        let totalCount = comment.replyCount ?? comment.replies?.count ?? loadedCount
        return loadedCount < totalCount
    }

    func replyState(for comment: Comment) -> LoadingState {
        replyThreadStates[comment.id] ?? .idle
    }

    func loadReplies(for comment: Comment) async {
        guard replyThreads[comment.id] == nil else { return }
        replyThreadPages[comment.id] = 0
        replyThreadHasMore[comment.id] = true
        await loadReplyPage(for: comment, reset: true)
    }

    func reloadReplies(for comment: Comment) async {
        replyThreads[comment.id] = nil
        replyThreadPages[comment.id] = 0
        replyThreadHasMore[comment.id] = true
        await loadReplyPage(for: comment, reset: true)
    }

    func loadMoreReplies(for comment: Comment) async {
        guard replyThreadHasMore[comment.id] != false,
              !(replyThreadStates[comment.id]?.isLoading ?? false) else { return }
        await loadReplyPage(for: comment, reset: false)
    }
}

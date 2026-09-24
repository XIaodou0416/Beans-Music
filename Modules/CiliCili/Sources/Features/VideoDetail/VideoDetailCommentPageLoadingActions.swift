import Foundation

extension VideoDetailViewModel {
    func loadCommentsPage(presentsErrors: Bool, emptyPageSkipLimit: Int = 0) async {
        guard let target = commentTarget else {
            if comments.isEmpty {
                commentState = .idle
            }
            return
        }
        let sort = selectedCommentSort
        let generation = advanceCommentPageLoadGeneration()
        let isInitialPage = comments.isEmpty && commentCursor.isEmpty
        let isLoadingMore = !isInitialPage
        var remainingEmptyPageSkips = emptyPageSkipLimit
        var didResolveLoadingState = false
        beginCommentPageLoad(isLoadingMore: isLoadingMore)
        defer {
            if !didResolveLoadingState,
               isCurrentCommentPageLoad(target: target, sort: sort, generation: generation) {
                resetCommentStateAfterCancellation(isInitialPage: isInitialPage, wasLoadingMore: isLoadingMore)
            }
        }
        while true {
            guard isCurrentCommentPageLoad(target: target, sort: sort, generation: generation) else {
                return
            }
            let previousCount = comments.count
            let previousCursor = commentCursor
            do {
                let page = try await fetchCommentsWithTimeout(target: target, cursor: commentCursor, sort: sort)
                guard isCurrentCommentPageLoad(target: target, sort: sort, generation: generation) else {
                    return
                }
                guard !Task.isCancelled else {
                    didResolveLoadingState = true
                    resetCommentStateAfterCancellation(isInitialPage: isInitialPage, wasLoadingMore: isLoadingMore)
                    return
                }
                applyLoadedCommentPage(page, previousCount: previousCount, isInitialPage: isInitialPage)

                guard shouldSkipEmptyCommentPage(
                    previousCount: previousCount,
                    previousCursor: previousCursor,
                    remainingEmptyPageSkips: remainingEmptyPageSkips
                ) else {
                    finishCommentPageLoadWithoutSkip(
                        isLoadingMore: isLoadingMore,
                        previousCount: previousCount
                    )
                    didResolveLoadingState = true
                    return
                }
                remainingEmptyPageSkips -= 1
                continueCommentPageLoadAfterEmptySkip(isLoadingMore: isLoadingMore)
            } catch is CancellationError {
                guard isCurrentCommentPageLoad(target: target, sort: sort, generation: generation) else {
                    return
                }
                didResolveLoadingState = true
                resetCommentStateAfterCancellation(isInitialPage: isInitialPage, wasLoadingMore: isLoadingMore)
                return
            } catch {
                guard isCurrentCommentPageLoad(target: target, sort: sort, generation: generation) else {
                    return
                }
                guard !Task.isCancelled else {
                    didResolveLoadingState = true
                    resetCommentStateAfterCancellation(isInitialPage: isInitialPage, wasLoadingMore: isLoadingMore)
                    return
                }
                didResolveLoadingState = true
                failCommentPageLoad(error, presentsErrors: presentsErrors)
                return
            }
        }
    }

}

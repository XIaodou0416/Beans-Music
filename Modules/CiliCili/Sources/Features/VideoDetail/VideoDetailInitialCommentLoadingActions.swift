import Foundation

extension VideoDetailViewModel {
    func loadInitialCommentsIfNeeded() async {
        guard comments.isEmpty, !commentState.isLoading else { return }
        await loadInitialComments()
    }

    func beginInitialCommentsLoadIfNeeded(waitForPlaybackStart: Bool = true) {
        guard commentTarget != nil else {
            if comments.isEmpty, !commentState.isLoading {
                commentState = .idle
            }
            return
        }
        if commentState.isLoading, commentsLoadingTask == nil {
            commentState = comments.isEmpty ? .idle : .loaded
        }
        guard comments.isEmpty, !commentState.isLoading else { return }
        cancelCommentsLoadingTask()
        let waitsForPlaybackStart = waitForPlaybackStart
            && !isAwaitingInitialManualPlayback
            && !isAwaitingRelatedVideoReturnPlayback
        let token = UUID()
        commentsLoadingToken = token
        commentsLoadingTask = Task(priority: waitsForPlaybackStart ? .utility : .userInitiated) { [weak self] in
            guard let self else { return }
            defer {
                self.clearCommentsLoadingTaskIfCurrent(token)
            }
            if waitsForPlaybackStart {
                guard let release = await self.waitForPlaybackStartupRelease(acceptsFailure: true),
                      !Task.isCancelled,
                      !self.isPlaybackInvalidatedForNavigation
                else { return }
                if case .firstFrame = release {
                    try? await Task.sleep(nanoseconds: 320_000_000)
                    guard !Task.isCancelled, !self.isPlaybackInvalidatedForNavigation else { return }
                }
            }
            await self.loadInitialComments()
        }
    }

    func loadInitialComments() async {
        guard commentTarget != nil else {
            if comments.isEmpty {
                commentState = .idle
            }
            return
        }
        commentCursor = ""
        commentsEnd = false
        resetCommentThreadStateForNewComments()
        comments = []
        commentLoadMoreState = .idle
        didCompleteInitialCommentLoad = false
        await loadCommentsPage(presentsErrors: true)
    }
}

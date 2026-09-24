import Foundation

extension VideoDetailViewModel {
    func trackBackgroundTask(_ task: Task<Void, Never>) {
        let id = UUID()
        backgroundTasks[id] = task
        Task(priority: .utility) { [weak self, task] in
            _ = await task.value
            await MainActor.run {
                guard let self,
                      self.backgroundTasks[id] != nil
                else { return }
                self.backgroundTasks[id] = nil
            }
        }
    }

    func clearDetailLoadingTaskIfCurrent(_ token: UUID) {
        guard detailLoadingToken == token else { return }
        detailLoadingTask = nil
        detailLoadingToken = nil
    }

    func clearPageLoadingTaskIfCurrent(_ token: UUID) {
        guard pageLoadingToken == token else { return }
        pageLoadingTask = nil
        pageLoadingToken = nil
    }

    func clearCommentsLoadingTaskIfCurrent(_ token: UUID) {
        guard commentsLoadingToken == token else { return }
        commentsLoadingTask = nil
        commentsLoadingToken = nil
    }

    @discardableResult
    func advanceCommentPageLoadGeneration() -> Int {
        commentPageLoadGeneration += 1
        return commentPageLoadGeneration
    }

    func isCurrentCommentPageLoad(
        target: VideoDetailCommentTarget,
        sort: CommentSort,
        generation: Int
    ) -> Bool {
        commentPageLoadGeneration == generation
            && selectedCommentSort == sort
            && isCurrentCommentTarget(target)
    }

    func clearDanmakuStartupLoadTaskIfCurrent(_ token: UUID) {
        guard danmakuStartupLoadToken == token else { return }
        danmakuStartupLoadTask = nil
        danmakuStartupLoadToken = nil
    }

    @discardableResult
    func advanceStartupPlayURLGeneration() -> Int {
        startupPlayURLGeneration += 1
        return startupPlayURLGeneration
    }

    func clearStartupPlayURLTaskIfCurrent(key: String, generation: Int) {
        guard startupPlayURLTaskKey == key,
              startupPlayURLGeneration == generation
        else { return }
        startupPlayURLTask = nil
        startupPlayURLTaskKey = nil
        startupPlayURLRequestLease = nil
    }

    func cancelBackgroundTasks() {
        backgroundTasks.values.forEach { $0.cancel() }
        backgroundTasks.removeAll()
        cloudHistoryResumeTask?.cancel()
        cloudHistoryResumeTask = nil
        cloudHistoryResumeTaskAid = nil
    }
}

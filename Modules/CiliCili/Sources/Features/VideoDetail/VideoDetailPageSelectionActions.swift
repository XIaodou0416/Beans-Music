import Foundation

extension VideoDetailViewModel {
    func resumeDurationHint(for cid: Int?) -> TimeInterval? {
        if let cid,
           let pageDuration = detail.pages?.first(where: { $0.cid == cid })?.duration,
           pageDuration > 0 {
            return TimeInterval(pageDuration)
        }
        return detail.duration.map(TimeInterval.init)
    }

    func selectPage(_ page: VideoPage) {
        guard !isPlaybackTerminatedForNavigation else { return }
        captureVideoListenPlaybackIntentForContentSwitch()
        isPlaybackInvalidatedForNavigation = false
        cancelBackgroundTasks()
        manuallySelectedPageCID = page.cid
        pendingPlaybackHistoryResumeTime = nil
        pendingPlaybackHistoryResumeCID = nil
        didResolveCloudHistoryResume = true
        selectedCID = page.cid
        resetPlaybackStateForSelectedPage()
        pageLoadingTask?.cancel()
        let token = UUID()
        pageLoadingToken = token
        pageLoadingTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            defer {
                self.clearPageLoadingTaskIfCurrent(token)
            }
            guard !Task.isCancelled,
                  !self.isPlaybackInvalidatedForNavigation,
                  self.pageLoadingToken == token,
                  self.selectedCID == page.cid
            else { return }
            await self.loadPlayURL()
        }
    }
}

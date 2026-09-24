import Foundation

extension VideoDetailViewModel {
    func selectPgcEpisode(_ video: VideoItem) {
        guard !isPlaybackTerminatedForNavigation else { return }
        guard video.isPGCEpisode, video.bvid != detail.bvid || video.cid != selectedCID else { return }
        captureVideoListenPlaybackIntentForContentSwitch()
        saveCurrentPlaybackProgressBeforeContentSwitch()

        isPlaybackInvalidatedForNavigation = false
        cancelBackgroundTasks()
        detail = video
        selectedCID = video.cid ?? video.pages?.first?.cid
        hasResolvedDetailMetadata = true
        manuallySelectedPageCID = nil
        didResolveCloudHistoryResume = false
        pendingPlaybackHistoryResumeTime = nil
        pendingPlaybackHistoryResumeCID = nil
        resumeDiagnostics = .none
        resetPlaybackStateForSelectedPage()
        resetInlineStateForContentSwitch()
        syncCommentsRenderStore()
        syncRelatedRenderStore()

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
                  self.detail.bvid == video.bvid,
                  self.selectedCID == (video.cid ?? video.pages?.first?.cid)
            else { return }
            await self.loadPlayURL()
        }
    }

    func resetInlineStateForContentSwitch() {
        comments = []
        commentCursor = ""
        commentsEnd = false
        commentState = .idle
        commentLoadMoreState = .idle
        didCompleteInitialCommentLoad = false
        resetCommentThreadStateForNewComments()
        related = []
        relatedState = .idle
        lastRelatedLoadTimedOut = false
        interactionState = VideoInteractionState()
        interactionMessage = nil
        favoriteFolders = []
        favoriteFolderState = .idle
        uploaderProfile = nil
    }

    func saveCurrentPlaybackProgressBeforeContentSwitch() {
        guard playbackOptions.recordsPlaybackHistory else { return }
        guard !libraryStore.incognitoModeEnabled else { return }
        let time = currentPlaybackResumeTime()
        guard time.isFinite,
              time >= TimeInterval(libraryStore.playbackHistorySyncThresholdSeconds)
        else { return }
        let previousDetail = detail
        let cid = selectedCID ?? previousDetail.cid
        let duration = previousDetail.duration.map(TimeInterval.init)
        libraryStore.recordPlaybackProgress(
            video: previousDetail,
            cid: cid,
            progress: time,
            duration: duration
        )
        Task {
            try? await api.reportVideoHistory(
                aid: previousDetail.aid,
                cid: cid,
                progress: time,
                duration: duration,
                bvid: previousDetail.bvid
            )
        }
    }
}

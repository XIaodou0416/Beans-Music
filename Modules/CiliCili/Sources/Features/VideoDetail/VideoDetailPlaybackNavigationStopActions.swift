import Foundation

extension VideoDetailViewModel {
    func stopPlaybackForNavigation() {
        guard !isPlaybackInvalidatedForNavigation else { return }
        let resumeTime = currentPlaybackResumeTime()
        capturePlaybackStateForNavigation(resumeTime: resumeTime)
        flushPlaybackProgressForNavigation(resumeTime: resumeTime)
        isPlaybackTerminatedForNavigation = true
        isPlaybackInvalidatedForNavigation = true

        // A related-video push keeps this detail page alive underneath the new
        // route. Suspend the existing engine, but retain its media and model so
        // popping back does not trigger a full detail/playback reload.
        if isAwaitingRelatedVideoReturnPlayback {
            stablePlayerViewModel?.pauseForNavigation()
            return
        }

        schedulePlaybackStopForNavigation()
    }

    private func capturePlaybackStateForNavigation(resumeTime: TimeInterval) {
        let suspendedState = stablePlayerViewModel?.pendingNavigationResumeState()
        let bestResumeTime = max(resumeTime, suspendedState?.resumeTime ?? 0)
        pendingNavigationResumeTime = bestResumeTime > 0.25 ? bestResumeTime : nil
        shouldResumePlaybackAfterCancelledNavigation = suspendedState?.shouldResumePlayback
            ?? currentPlaybackIntent()
        videoListenPlaybackSessionStore.removeState(for: detail)
        pendingVideoListenPlaybackSessionState = nil
        hasPendingNavigationInterruption = true
    }

    private func flushPlaybackProgressForNavigation(resumeTime: TimeInterval) {
        guard playbackOptions.recordsPlaybackHistory else { return }
        guard !libraryStore.incognitoModeEnabled else { return }
        guard resumeTime.isFinite,
              resumeTime >= TimeInterval(libraryStore.playbackHistorySyncThresholdSeconds)
        else { return }
        let cid = selectedCID ?? detail.cid
        let duration = detail.duration.map(TimeInterval.init)
        libraryStore.recordPlaybackProgress(
            video: detail,
            cid: cid,
            progress: resumeTime,
            duration: duration
        )
        let api = api
        let detail = detail
        Task {
            try? await api.reportVideoHistory(
                aid: detail.aid,
                cid: cid,
                progress: resumeTime,
                duration: duration,
                bvid: detail.bvid
            )
        }
    }

    private func schedulePlaybackStopForNavigation() {
        guard navigationState.playbackStopTask == nil else { return }
        navigationState.playbackStopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard let self, !Task.isCancelled else { return }
            self.navigationState.playbackStopTask = nil
            self.finishStoppingPlaybackForNavigation()
        }
    }

    private func finishStoppingPlaybackForNavigation() {
        cancelPlaybackWorkForNavigation()
        resetPlaybackLoadingStateForNavigation()
        stopStablePlaybackForNavigation()
        resetPlaybackRecoveryStateForNavigation()
    }

    private func cancelPlaybackWorkForNavigation() {
        cancelVideoListenQueueTasks(resetSession: false)
        cancelSupplementalWork()
        Self.cancelMediaWarmupsPreservingCache()
        cancelRelatedLoad()
        cancelCommentsLoadingTask()
        clearCommentThreadLoads()
        resetDanmakuLoad(clearItems: true)
        detailLoadingTask?.cancel()
        detailLoadingTask = nil
        detailLoadingToken = nil
        cancelSponsorBlockTask()
        sponsorBlockSegments = []
        sponsorBlockIdentity = nil
        renderStoreSyncTask?.cancel()
        renderStoreSyncTask = nil
        pendingRenderStoreSyncs = []
        renderStoreSyncGeneration += 1
    }

    private func resetPlaybackLoadingStateForNavigation() {
        currentPlayURLData = nil
        clearVideoListenAudioVariants()
        selectedPlayVariant = nil
        if state.isLoading {
            state = .idle
        }
        finishPlaybackStartupWaiters(with: nil)
        playURLState = .idle
    }

    private func stopStablePlaybackForNavigation() {
        stablePlayerViewModel?.stop()
        stablePlayerViewModel = nil
        clearPlaybackTransitionPlayer()
        stablePlayerIdentity = nil
        stablePlayerErrorCancellable = nil
        stablePlayerFirstFrameCancellable = nil
        syncPlayerIdentityRenderStore()
    }

    private func resetPlaybackRecoveryStateForNavigation() {
        pendingVideoListenPlaybackIntent = nil
        cancelVideoListenSleepTimer()
        playbackFallbackMessage = nil
        clearManualPlayVariantSelection()
        failedPlayVariantIDs.removeAll()
        playbackRecoveryAttemptCount = 0
        playbackRecoveryCoordinator.reset()
        lastBufferingCDNRefreshCount = 0
        cancelPlaybackRecoveryReloadTask()
        cancelBufferingCDNRefreshTask()
        lastUserSeekAt = nil
        resumeDiagnostics = .none
    }
}

import Foundation

extension VideoDetailViewModel {
    func prepareHistoryResumeBeforeApplyingPlayURL(_ data: PlayURLData, cid: Int) async -> Bool {
        guard stablePlayerViewModel == nil else { return false }
        guard playbackOptions.resumesPlaybackHistory else { return false }
        if VideoDetailPlaybackHistorySelectionPolicy.preservesManualPage(
            manuallySelectedCID: manuallySelectedPageCID,
            currentCID: cid
        ) {
            if pendingPlaybackHistoryResumeTime == nil,
               let resumeTime = libraryStore.localPlaybackResumeTime(
                   for: detail,
                   cid: cid,
                   duration: resumeDurationHint(for: cid)
               ) {
                setPendingPlaybackHistoryResumeTime(resumeTime, cid: cid)
            }
            return false
        }
        if redirectToHistoryCIDIfNeeded(data.lastPlayCID, currentCID: cid) {
            return true
        }
        if usesMainAccountHistoryMetadata,
           redirectToHistoryCIDIfNeeded(detail.historyCID, currentCID: cid) {
            return true
        }
        let minimumProgress = playbackHistoryResumeMinimumProgress
        if let localProgress = libraryStore.localPlaybackProgress(
            for: detail,
            duration: historyResumeDurationHint
        ),
           redirectToHistoryCIDIfNeeded(localProgress.cid, currentCID: cid) {
            return true
        }
        if let resumeTime = libraryStore.localPlaybackResumeTime(
            for: detail,
            cid: cid,
            duration: historyResumeDurationHint
        ) {
            setPendingPlaybackHistoryResumeTime(resumeTime, cid: cid)
            return false
        }
        if let resumeTime = data.resumeTime(
            duration: historyResumeDurationHint,
            minimumProgress: minimumProgress
        ) {
            setPendingPlaybackHistoryResumeTime(resumeTime, cid: cid)
            return false
        }
        if usesMainAccountHistoryMetadata,
           let resumeTime = detail.historyResumeTime,
           resumeTime >= minimumProgress,
           detail.historyCID == nil || detail.historyCID == cid {
            setPendingPlaybackHistoryResumeTime(resumeTime, cid: cid)
            return false
        }
        guard pendingPlaybackHistoryResumeTime == nil else { return false }
        await prepareCloudHistoryResumeIfNeeded(currentCID: cid)
        return selectedCID != cid
    }

    func consumePendingPlaybackHistoryResumeTime(for cid: Int?) -> TimeInterval? {
        guard stablePlayerViewModel == nil,
              let resumeTime = pendingPlaybackHistoryResumeTime,
              resumeTime > 0.25
        else { return nil }
        if let pendingCID = pendingPlaybackHistoryResumeCID,
           let cid,
           pendingCID != cid {
            return nil
        }
        pendingPlaybackHistoryResumeTime = nil
        pendingPlaybackHistoryResumeCID = nil
        return resumeTime
    }

    private var historyResumeDurationHint: TimeInterval? {
        detail.duration.map(TimeInterval.init)
    }

    private var playbackHistoryResumeMinimumProgress: TimeInterval {
        TimeInterval(libraryStore.playbackHistorySyncThresholdSeconds)
    }

    private var usesMainAccountHistoryMetadata: Bool {
        let snapshot = sessionStore.credentialSnapshot(
            for: .historyRead,
            multiAccountEnabled: libraryStore.multiAccountExperimentEnabled
        )
        return snapshot.accountMID == sessionStore.mainAccountMID
    }

    private func prepareCloudHistoryResumeIfNeeded(currentCID: Int) async {
        guard !VideoDetailPlaybackHistorySelectionPolicy.preservesManualPage(
            manuallySelectedCID: manuallySelectedPageCID,
            currentCID: currentCID
        ) else { return }
        guard !didResolveCloudHistoryResume else { return }
        guard !libraryStore.incognitoModeEnabled,
              let aid = detail.aid
        else { return }
        let bvid = detail.bvid
        beginCloudHistoryResumeFetchIfNeeded()
        didResolveCloudHistoryResume = true
        guard let task = cloudHistoryResumeTask,
              cloudHistoryResumeTaskAid == aid
        else { return }
        let history = await task.value
        if cloudHistoryResumeTaskAid == aid {
            cloudHistoryResumeTask = nil
            cloudHistoryResumeTaskAid = nil
        }
        guard let history,
              !Task.isCancelled,
              !isPlaybackInvalidatedForNavigation,
              detail.bvid == bvid,
              selectedCID == currentCID
        else { return }

        let targetCID = matchingHistoryCID(history.lastPlayCid) ?? currentCID
        if let resumeTime = history.resumeTime(
            duration: historyResumeDurationHint,
            minimumProgress: playbackHistoryResumeMinimumProgress
        ) {
            setPendingPlaybackHistoryResumeTime(resumeTime, cid: targetCID)
        }
        if targetCID != currentCID {
            selectedCID = targetCID
        }
    }

    func beginCloudHistoryResumeFetchIfNeeded() {
        guard playbackOptions.resumesPlaybackHistory else { return }
        guard manuallySelectedPageCID == nil else { return }
        guard !didResolveCloudHistoryResume,
              pendingPlaybackHistoryResumeTime == nil,
              !libraryStore.incognitoModeEnabled,
              let aid = detail.aid,
              aid > 0
        else { return }
        guard cloudHistoryResumeTask == nil || cloudHistoryResumeTaskAid != aid else { return }

        cloudHistoryResumeTask?.cancel()
        cloudHistoryResumeTaskAid = aid
        let api = api
        cloudHistoryResumeTask = Task(priority: .utility) {
            try? await api.fetchVideoHistoryProgress(aid: aid)
        }
    }

    private func redirectToHistoryCIDIfNeeded(_ rawCID: Int?, currentCID: Int) -> Bool {
        guard let targetCID = matchingHistoryCID(rawCID),
              targetCID != currentCID
        else { return false }
        selectedCID = targetCID
        return true
    }

    private func matchingHistoryCID(_ rawCID: Int?) -> Int? {
        guard let rawCID, rawCID > 0 else { return nil }
        guard let pages = detail.pages, !pages.isEmpty else { return rawCID }
        return pages.contains(where: { $0.cid == rawCID }) ? rawCID : nil
    }

    private func setPendingPlaybackHistoryResumeTime(
        _ resumeTime: TimeInterval,
        cid: Int?
    ) {
        pendingPlaybackHistoryResumeTime = resumeTime
        pendingPlaybackHistoryResumeCID = cid
    }
}

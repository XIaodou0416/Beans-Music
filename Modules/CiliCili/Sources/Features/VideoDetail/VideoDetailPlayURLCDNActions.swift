import Foundation

extension VideoDetailViewModel {
    func prepareAutomaticCDNRecommendationForPlayback() async {
        let previousCDNPreference = libraryStore.effectivePlaybackCDNPreference
        await PlayerMetricsLog.withSignpostedInterval(
            "VideoDetailCDNRecommendation",
            message: "bvid=\(detail.bvid) preference=\(previousCDNPreference.rawValue)"
        ) {
            await PlaybackCDNProbeCoordinator.shared.prepareRecommendationForImmediatePlaybackIfNeeded(
                libraryStore: libraryStore,
                timeout: cdnRecommendationStartupBudget
            )
        }
        let updatedCDNPreference = libraryStore.effectivePlaybackCDNPreference
        guard updatedCDNPreference != previousCDNPreference,
              updatedCDNPreference != .automatic
        else { return }
        PlayerMetricsLog.record(
            .network,
            metricsID: detail.bvid,
            title: detail.title,
            message: "cdnStartupRecommendation=\(updatedCDNPreference.title)"
        )
    }

    func scheduleAutomaticCDNRecommendationForPlayback() {
        guard libraryStore.playbackCDNPreference == .automatic else { return }
        PlaybackCDNProbeCoordinator.shared.refreshIfNeeded(libraryStore: libraryStore)
    }

    func scheduleAutomaticCDNRecommendationAfterFirstFrameIfNeeded(
        variant: PlayVariant?,
        cid: Int?,
        page: Int?
    ) {
        guard libraryStore.playbackCDNPreference == .automatic,
              let cid,
              let variant,
              !isPlaybackInvalidatedForNavigation
        else { return }

        let playbackURLs = automaticCDNProbeURLs(for: variant)
        guard !playbackURLs.isEmpty else { return }

        let bvid = detail.bvid
        trackBackgroundTask(
            Task(priority: .utility) { [weak self] in
                guard let self else { return }
                let didPresentPlayback = await self.waitForFirstFrameOrFailure()
                guard didPresentPlayback,
                      !Task.isCancelled,
                      !self.isPlaybackInvalidatedForNavigation,
                      self.detail.bvid == bvid,
                      self.selectedCID == cid,
                      self.selectedPageNumber == page,
                      self.libraryStore.playbackCDNPreference == .automatic
                else { return }

                PlayerMetricsLog.signpostEvent(
                    "VideoDetailCDNRecommendation",
                    message: "postFirstFrame bvid=\(bvid) cid=\(cid)"
                )
                PlaybackCDNProbeCoordinator.shared.refreshAfterSuccessfulPlaybackIfNeeded(
                    libraryStore: self.libraryStore,
                    playbackURLs: playbackURLs
                )
            }
        )
    }

    private func automaticCDNProbeURLs(for variant: PlayVariant) -> [URL] {
        var urls = [variant.videoURL, variant.audioURL].compactMap { $0 }
        if let stream = variant.videoStream {
            urls += [URL(string: stream.baseURL)].compactMap { $0 }
            urls += stream.backupPlayURLs
        }
        if let stream = variant.audioStream {
            urls += [URL(string: stream.baseURL)].compactMap { $0 }
            urls += stream.backupPlayURLs
        }
        var seen = Set<String>()
        return urls.filter { seen.insert($0.absoluteString).inserted }
    }
}

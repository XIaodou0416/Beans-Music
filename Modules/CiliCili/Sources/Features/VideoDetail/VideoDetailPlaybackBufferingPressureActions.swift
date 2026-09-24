import Foundation

extension VideoDetailViewModel {
    func handleBufferingPressure(_ count: Int) {
        guard !isPlaybackInvalidatedForNavigation,
              count >= 2,
              count != lastBufferingCDNRefreshCount
        else { return }
        lastBufferingCDNRefreshCount = count
        let bvid = detail.bvid
        let cid = selectedCID
        let page = selectedPageNumber
        let title = detail.title
        let previousPreference = libraryStore.effectivePlaybackCDNPreference
        temporarilyAvoidCurrentAutomaticPlaybackCDN(reason: "bufferingPressure count=\(count)")
        PlayerMetricsLog.record(
            .network,
            metricsID: bvid,
            title: title,
            message: "bufferingPressure count=\(count) cdnRefresh=queued"
        )
        PlaybackCDNProbeCoordinator.shared.refreshForPlaybackPressure(libraryStore: libraryStore)
        cancelBufferingCDNRefreshTask(advancesGeneration: false)
        let refreshGeneration = advanceBufferingCDNRefreshGeneration()
        bufferingCDNRefreshTask = Task { @MainActor [weak self, previousPreference] in
            defer {
                self?.clearBufferingCDNRefreshTaskIfCurrent(generation: refreshGeneration)
            }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard let self,
                  self.isCurrentPlaybackContext(bvid: bvid, cid: cid, page: page),
                  self.bufferingCDNRefreshGeneration == refreshGeneration
            else { return }
            let updatedPreference = self.libraryStore.effectivePlaybackCDNPreference
            if updatedPreference != previousPreference {
                PlayerMetricsLog.record(
                    .network,
                    metricsID: bvid,
                    title: title,
                    message: "bufferingPressure cdnPreference \(previousPreference.rawValue)->\(updatedPreference.rawValue)"
                )
            }
        }
    }

    func cancelBufferingCDNRefreshTask(advancesGeneration: Bool = true) {
        bufferingCDNRefreshTask?.cancel()
        bufferingCDNRefreshTask = nil
        if advancesGeneration {
            advanceBufferingCDNRefreshGeneration()
        }
    }

    @discardableResult
    func advanceBufferingCDNRefreshGeneration() -> Int {
        bufferingCDNRefreshGeneration += 1
        return bufferingCDNRefreshGeneration
    }

    func clearBufferingCDNRefreshTaskIfCurrent(generation: Int) {
        guard bufferingCDNRefreshGeneration == generation else { return }
        bufferingCDNRefreshTask = nil
    }
}

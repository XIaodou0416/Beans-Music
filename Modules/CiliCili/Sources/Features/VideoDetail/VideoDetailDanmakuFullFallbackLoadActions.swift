import Foundation

extension VideoDetailViewModel {
    func loadFullDanmakuFallback(cid: Int, generation: Int) async {
        guard danmakuLoadGeneration == generation else { return }
        didFallbackToFullDanmakuLoad = true
        danmakuSegmentTasks.values.forEach { $0.cancel() }
        danmakuSegmentTasks.removeAll()
        loadingDanmakuSegments.removeAll()
        loadedDanmakuSegments.removeAll()
        danmakuSegmentItems.removeAll()
        danmakuTask?.cancel()
        let fallbackGeneration = advanceDanmakuLoadGeneration()
        danmakuState = .loading

        danmakuTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            defer {
                self.clearFullDanmakuTaskIfCurrent(generation: fallbackGeneration)
            }
            do {
                let items = try await self.api.fetchDanmaku(cid: cid)
                guard !Task.isCancelled,
                      !self.isPlaybackInvalidatedForNavigation,
                      self.selectedCID == cid,
                      self.isDanmakuEnabled,
                      self.danmakuLoadGeneration == fallbackGeneration
                else { return }
                self.updateDanmakuItems(self.sortedDanmakuItems(items))
                self.danmakuState = .loaded
            } catch {
                guard !Task.isCancelled,
                      !self.isPlaybackInvalidatedForNavigation,
                      self.selectedCID == cid,
                      self.danmakuLoadGeneration == fallbackGeneration
                else { return }
                self.updateDanmakuItems([])
                self.danmakuState = .failed(error.localizedDescription)
            }
        }
    }
}

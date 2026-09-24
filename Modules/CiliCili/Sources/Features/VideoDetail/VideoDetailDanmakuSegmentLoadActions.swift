import Foundation

extension VideoDetailViewModel {
    func loadDanmakuSegment(cid: Int, segmentIndex: Int, generation: Int) {
        guard danmakuLoadGeneration == generation else { return }
        loadingDanmakuSegments.insert(segmentIndex)
        let task = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            defer {
                self.clearDanmakuSegmentTaskIfCurrent(segmentIndex: segmentIndex, generation: generation)
            }

            do {
                let items = try await self.api.fetchDanmakuSegment(cid: cid, segmentIndex: segmentIndex)
                guard !Task.isCancelled,
                      !self.isPlaybackInvalidatedForNavigation,
                      self.selectedCID == cid,
                      self.isDanmakuEnabled,
                      !self.didFallbackToFullDanmakuLoad,
                      self.danmakuLoadGeneration == generation
                else { return }

                self.loadedDanmakuSegments.insert(segmentIndex)
                self.danmakuSegmentItems[segmentIndex] = self.sortedDanmakuItems(items)
                self.refreshDanmakuItemsFromSegments()
                self.danmakuState = .loaded
            } catch {
                guard !Task.isCancelled,
                      !self.isPlaybackInvalidatedForNavigation,
                      self.selectedCID == cid,
                      self.isDanmakuEnabled,
                      self.danmakuLoadGeneration == generation
                else { return }

                if segmentIndex == 1, self.danmakuItems.isEmpty, !self.didFallbackToFullDanmakuLoad {
                    await self.loadFullDanmakuFallback(cid: cid, generation: generation)
                } else if self.loadedDanmakuSegments.isEmpty,
                          self.danmakuItems.isEmpty,
                          self.danmakuSegmentTasks.count <= 1 {
                    self.danmakuState = .failed(error.localizedDescription)
                }
            }
        }
        danmakuSegmentTasks[segmentIndex] = task
    }

}

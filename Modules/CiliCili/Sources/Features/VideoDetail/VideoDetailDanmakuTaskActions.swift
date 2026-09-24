import Foundation

extension VideoDetailViewModel {
    @discardableResult
    func advanceDanmakuLoadGeneration() -> Int {
        danmakuLoadGeneration += 1
        return danmakuLoadGeneration
    }

    func clearFullDanmakuTaskIfCurrent(generation: Int) {
        guard danmakuLoadGeneration == generation else { return }
        danmakuTask = nil
    }

    func clearDanmakuSegmentTaskIfCurrent(segmentIndex: Int, generation: Int) {
        guard danmakuLoadGeneration == generation else { return }
        loadingDanmakuSegments.remove(segmentIndex)
        danmakuSegmentTasks[segmentIndex] = nil
        if danmakuSegmentTasks.isEmpty, danmakuTask == nil, danmakuState.isLoading {
            danmakuState = .loaded
        }
    }
}

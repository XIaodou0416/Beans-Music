import Foundation

@MainActor
extension VideoDetailDanmakuOverlayState {
    func firstItemIndex(atOrAfter time: TimeInterval) -> Int {
        var lower = 0
        var upper = allItems.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if allItems[middle].time < time {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    func firstItemIndex(after time: TimeInterval) -> Int {
        var lower = 0
        var upper = allItems.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if allItems[middle].time <= time {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }
}

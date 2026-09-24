import Foundation

extension VideoDetailViewModel {
    func refreshDanmakuItemsFromSegments() {
        var seen = Set<String>()
        var merged = [DanmakuItem]()
        let segments = danmakuSegmentItems.keys.sorted()
        let totalItemCount = segments.reduce(0) { count, segment in
            count + (danmakuSegmentItems[segment]?.count ?? 0)
        }
        merged.reserveCapacity(totalItemCount)
        var previousItem: DanmakuItem?
        var isAlreadySorted = true

        for segment in segments {
            for item in danmakuSegmentItems[segment] ?? [] where seen.insert(item.id).inserted {
                if let previousItem,
                   item.time < previousItem.time || (item.time == previousItem.time && item.id < previousItem.id) {
                    isAlreadySorted = false
                }
                merged.append(item)
                previousItem = item
            }
        }
        updateDanmakuItems(isAlreadySorted ? merged : sortedDanmakuItems(merged))
    }

    func updateDanmakuItems(_ items: [DanmakuItem]) {
        danmakuItems = items
        danmakuItemsRevision &+= 1
        syncDanmakuRenderStore()
    }

    func sortedDanmakuItems(_ items: [DanmakuItem]) -> [DanmakuItem] {
        items.sorted { lhs, rhs in
            if lhs.time != rhs.time {
                return lhs.time < rhs.time
            }
            return lhs.id < rhs.id
        }
    }
}

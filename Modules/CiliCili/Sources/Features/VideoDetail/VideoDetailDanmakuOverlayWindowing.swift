import Foundation

@MainActor
extension VideoDetailDanmakuOverlayState {
    func updateWindow(around playbackTime: TimeInterval, force: Bool) {
        let sanitizedTime = max(0, playbackTime)
        let centerBucket = Int(sanitizedTime / max(windowRecenterInterval, 1))
        guard force || lastWindowCenterBucket != centerBucket else { return }
        lastWindowCenterBucket = centerBucket

        let lowerTime = max(0, sanitizedTime - effectiveWindowLookBehind)
        let upperTime = sanitizedTime + effectiveWindowLookAhead
        let lowerIndex = firstItemIndex(atOrAfter: lowerTime)
        let upperIndex = firstItemIndex(after: upperTime)
        let nextRange = lowerIndex..<upperIndex
        let didChangeSource = publishedSourceItemsRevision != sourceItemsRevision
        guard force || didChangeSource || publishedWindowRange != nextRange else { return }

        publishedWindowRange = nextRange
        publishedSourceItemsRevision = sourceItemsRevision
        PlayerMetricsLog.signpostEvent(
            "VideoDetailDanmakuWindow",
            message: "count=\(nextRange.count) force=\(force) revision=\(sourceItemsRevision)"
        )
        if nextRange.isEmpty {
            updateSnapshot {
                $0.items = []
                $0.itemsRevision &+= 1
            }
        } else {
            updateSnapshot {
                $0.items = Array(allItems[nextRange])
                $0.itemsRevision &+= 1
            }
        }
    }

    var effectiveWindowLookBehind: TimeInterval {
        snapshot.isLoadShedding ? 6 : normalWindowLookBehind
    }

    var effectiveWindowLookAhead: TimeInterval {
        if snapshot.isLoadShedding {
            return 24
        }
        if snapshot.playbackRate > 1.15 || PlaybackEnvironment.current.isThermallyElevated {
            return 32
        }
        return normalWindowLookAhead
    }
}

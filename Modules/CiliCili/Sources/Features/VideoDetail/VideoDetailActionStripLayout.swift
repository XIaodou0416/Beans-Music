import SwiftUI

struct VideoDetailActionStripLayout {
    let contentWidth: CGFloat

    var columnSpacing: CGFloat { VideoDetailActionStrip.Metrics.columnSpacing }
    var rowHeight: CGFloat { VideoDetailActionStrip.Metrics.rowHeight }
    var columnWidth: CGFloat { max((contentWidth - columnSpacing * 5) / 6, 1) }
}

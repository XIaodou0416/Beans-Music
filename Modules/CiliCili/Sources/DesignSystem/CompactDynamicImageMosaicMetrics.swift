import SwiftUI

enum CompactDynamicImageMosaicMetrics {
    static let spacing: CGFloat = 6
    static let compactWidth: CGFloat = 270
    static let smallSide: CGFloat = 86
    static let mediumSide: CGFloat = 132
    static let largeSide: CGFloat = 178
    static let footerSide: CGFloat = 63

    static func gridWidth(columns: Int, side: CGFloat) -> CGFloat {
        side * CGFloat(columns) + spacing * CGFloat(max(columns - 1, 0))
    }
}

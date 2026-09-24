import SwiftUI

enum DynamicImageGridMetrics {
    static let spacing: CGFloat = 4

    static func tileSide(for width: CGFloat, columns: Int) -> CGFloat {
        floor((width - spacing * CGFloat(max(columns - 1, 0))) / CGFloat(max(columns, 1)))
    }
}

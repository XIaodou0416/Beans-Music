import SwiftUI

struct HomeFeedLayoutMetrics {
    let mode: HomeFeedLayout
    let doubleColumns: [GridItem]
    let feedColumns: [GridItem]
    let feedSpacing: CGFloat
    let feedHorizontalPadding: CGFloat
    let singleColumnHorizontalPadding: CGFloat
    let singleColumnFixedCoverSize: CGSize?
    let doubleColumnFixedCoverSize: CGSize?
    let borderedSingleColumnCoverSize: CGSize?

    init(mode: HomeFeedLayout, containerWidth: CGFloat) {
        self.mode = mode
        let doubleColumnSpacing: CGFloat = mode == .borderedDoubleColumn ? 12 : 14
        let doubleColumnCoverHeightRatio: CGFloat = mode == .borderedDoubleColumn ? 10 / 16 : 9 / 16
        doubleColumns = [
            GridItem(.flexible(), spacing: doubleColumnSpacing),
            GridItem(.flexible(), spacing: doubleColumnSpacing)
        ]
        singleColumnHorizontalPadding = mode == .borderedSingleColumn ? 16 : 12

        switch mode {
        case .singleColumn, .borderedSingleColumn:
            feedColumns = [
                GridItem(.flexible(minimum: 0), spacing: 0)
            ]
            feedSpacing = 0
            feedHorizontalPadding = 0
        case .doubleColumn:
            feedColumns = doubleColumns
            feedSpacing = 22
            feedHorizontalPadding = 16
        case .borderedDoubleColumn:
            feedColumns = doubleColumns
            feedSpacing = 18
            feedHorizontalPadding = 12
        }

        let singleWidth = containerWidth - singleColumnHorizontalPadding * 2
        if singleWidth > 0 {
            singleColumnFixedCoverSize = CGSize(width: singleWidth, height: singleWidth * 9 / 16)
        } else {
            singleColumnFixedCoverSize = nil
        }

        let doubleWidth = (containerWidth - (feedHorizontalPadding * 2) - doubleColumnSpacing) / 2
        if doubleWidth > 0 {
            doubleColumnFixedCoverSize = CGSize(width: doubleWidth, height: doubleWidth * doubleColumnCoverHeightRatio)
        } else {
            doubleColumnFixedCoverSize = nil
        }

        if singleWidth > 0 {
            borderedSingleColumnCoverSize = CGSize(width: 140, height: 88)
        } else {
            borderedSingleColumnCoverSize = nil
        }
    }
}

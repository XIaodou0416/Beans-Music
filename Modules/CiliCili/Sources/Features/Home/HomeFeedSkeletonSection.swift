import SwiftUI

struct HomeFeedSkeletonSection: View {
    let metrics: HomeFeedLayoutMetrics

    var body: some View {
        if metrics.mode.isDoubleColumn {
            LazyVGrid(columns: metrics.doubleColumns, spacing: metrics.feedSpacing) {
                ForEach(0..<12, id: \.self) { _ in
                    VideoFeedSkeletonCard(style: .grid)
                }
            }
            .padding(.horizontal, metrics.feedHorizontalPadding)
            .padding(.top, 2)
            .allowsHitTesting(false)
        } else if metrics.mode == .borderedSingleColumn {
            LazyVStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { _ in
                    VideoFeedSkeletonCard(
                        style: .borderedSingleColumn(
                            coverSize: metrics.borderedSingleColumnCoverSize ?? CGSize(width: 140, height: 88)
                        )
                    )
                }
            }
            .padding(.horizontal, metrics.singleColumnHorizontalPadding)
            .padding(.top, 2)
            .allowsHitTesting(false)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { _ in
                    VideoFeedSkeletonCard(style: .singleColumn)
                }
            }
            .padding(.horizontal, metrics.singleColumnHorizontalPadding)
            .padding(.top, 2)
            .allowsHitTesting(false)
        }
    }
}

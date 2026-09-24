import SwiftUI

struct VideoDetailRelatedListLayout {
    let layoutWidth: CGFloat
    let horizontalPadding: CGFloat = VideoDetailRelatedStyle.horizontalPadding

    var contentWidth: CGFloat {
        max(layoutWidth - horizontalPadding * 2, 1)
    }

    var coverWidth: CGFloat {
        min(
            max(contentWidth * VideoDetailRelatedStyle.coverWidthRatio, VideoDetailRelatedStyle.minimumCoverWidth),
            VideoDetailRelatedStyle.maximumCoverWidth
        )
    }

    var coverSize: CGSize {
        CGSize(width: coverWidth, height: coverWidth * VideoDetailRelatedStyle.coverAspectRatio)
    }

    var dividerLeadingPadding: CGFloat {
        coverWidth + VideoDetailRelatedStyle.dividerSpacingAfterCover
    }
}

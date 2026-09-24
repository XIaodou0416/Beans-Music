import SwiftUI

struct CompactDynamicImageMosaicContent: View {
    let imageCount: Int
    let displayedImages: [CompactDynamicImageDisplayItem]
    let layout: CompactDynamicImageMosaicLayout
    let previewItems: [ZoomyImagePreviewItem]
    let previewGroup: ZoomyImagePreviewGroup
    let accessibilityName: String
    let placeholderFill: Color

    var body: some View {
        content
    }

    @ViewBuilder
    private var content: some View {
        switch displayedImages.count {
        case 0:
            EmptyView()
        case 1:
            CompactDynamicSingleImageMosaicLayout(tileContext: tileContext, item: displayedImages.first)
        case 2:
            CompactDynamicEqualImageGrid(tileContext: tileContext, layout: layout, columns: 2, side: CompactDynamicImageMosaicMetrics.mediumSide)
        case 3:
            CompactDynamicThreeImageMosaicLayout(tileContext: tileContext, layout: layout)
        case 4:
            CompactDynamicEqualImageGrid(tileContext: tileContext, layout: layout, columns: 2, side: CompactDynamicImageMosaicMetrics.mediumSide)
        case 5:
            CompactDynamicFiveImageMosaicLayout(tileContext: tileContext, layout: layout)
        case 6:
            CompactDynamicEqualImageGrid(tileContext: tileContext, layout: layout, columns: 3, side: CompactDynamicImageMosaicMetrics.smallSide)
        case 7:
            CompactDynamicSevenImageMosaicLayout(tileContext: tileContext, layout: layout)
        case 8:
            CompactDynamicEightImageMosaicLayout(tileContext: tileContext, layout: layout)
        default:
            CompactDynamicEqualImageGrid(tileContext: tileContext, layout: layout, columns: 3, side: CompactDynamicImageMosaicMetrics.smallSide)
        }
    }

    private var tileContext: CompactDynamicImageTileContext {
        CompactDynamicImageTileContext(
            imageCount: imageCount,
            previewItems: previewItems,
            previewGroup: previewGroup,
            accessibilityName: accessibilityName,
            placeholderFill: placeholderFill
        )
    }
}

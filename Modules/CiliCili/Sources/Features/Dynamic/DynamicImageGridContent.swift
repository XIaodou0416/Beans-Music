import SwiftUI

struct DynamicImageGridContent: View {
    let images: [DynamicImageItem]
    let displayedImages: [DynamicImageDisplayItem]
    let layout: DynamicImageGridLayout
    let previewItems: [ZoomyImagePreviewItem]
    let previewGroup: ZoomyImagePreviewGroup
    let width: CGFloat

    var body: some View {
        content(width: width)
    }

    @ViewBuilder
    private func content(width: CGFloat) -> some View {
        switch displayedImages.count {
        case 0:
            EmptyView()
        case 1:
            DynamicSingleImageLayout(
                item: displayedImages.first,
                imagesCount: images.count,
                previewItems: previewItems,
                previewGroup: previewGroup,
                width: width
            )
        case 2:
            DynamicEqualImageGrid(
                imagesCount: images.count,
                layout: layout,
                previewItems: previewItems,
                previewGroup: previewGroup,
                width: width,
                columns: 2
            )
        case 3:
            DynamicThreeImageMosaicLayout(
                imagesCount: images.count,
                layout: layout,
                previewItems: previewItems,
                previewGroup: previewGroup,
                width: width
            )
        case 4:
            DynamicEqualImageGrid(
                imagesCount: images.count,
                layout: layout,
                previewItems: previewItems,
                previewGroup: previewGroup,
                width: width,
                columns: 2
            )
        case 5:
            DynamicFiveImageMosaicLayout(
                imagesCount: images.count,
                layout: layout,
                previewItems: previewItems,
                previewGroup: previewGroup,
                width: width
            )
        case 6:
            DynamicEqualImageGrid(
                imagesCount: images.count,
                layout: layout,
                previewItems: previewItems,
                previewGroup: previewGroup,
                width: width,
                columns: 3
            )
        case 7:
            DynamicSevenImageMosaicLayout(
                imagesCount: images.count,
                layout: layout,
                previewItems: previewItems,
                previewGroup: previewGroup,
                width: width
            )
        case 8:
            DynamicEightImageMosaicLayout(
                imagesCount: images.count,
                layout: layout,
                previewItems: previewItems,
                previewGroup: previewGroup,
                width: width
            )
        default:
            DynamicEqualImageGrid(
                imagesCount: images.count,
                layout: layout,
                previewItems: previewItems,
                previewGroup: previewGroup,
                width: width,
                columns: 3
            )
        }
    }
}

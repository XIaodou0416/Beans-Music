import SwiftUI

struct DynamicSingleImageLayout: View {
    let item: DynamicImageDisplayItem?
    let imagesCount: Int
    let previewItems: [ZoomyImagePreviewItem]
    let previewGroup: ZoomyImagePreviewGroup
    let width: CGFloat

    var body: some View {
        if let item {
            let imageWidth = floor(width * 0.82)
            let aspectRatio = item.aspectRatio
            let displayMode: DynamicImageCell.DisplayMode = item.isLongImage
                ? .longImage(cornerRadius: 8)
                : .single
            let imageHeight = item.isLongImage
                ? ceil(imageWidth * 16 / 9)
                : min(max(imageWidth / aspectRatio, 150), 360)

            HStack {
                DynamicImageGridTile(
                    item: item,
                    imagesCount: imagesCount,
                    previewItems: previewItems,
                    previewGroup: previewGroup,
                    displayMode: displayMode
                )
                .frame(width: imageWidth, height: imageHeight)

                Spacer(minLength: 0)
            }
            .frame(width: width, alignment: .leading)
        }
    }
}

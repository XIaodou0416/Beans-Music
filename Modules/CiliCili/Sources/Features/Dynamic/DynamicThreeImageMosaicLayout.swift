import SwiftUI

struct DynamicThreeImageMosaicLayout: View {
    let imagesCount: Int
    let layout: DynamicImageGridLayout
    let previewItems: [ZoomyImagePreviewItem]
    let previewGroup: ZoomyImagePreviewGroup
    let width: CGFloat

    var body: some View {
        let smallSide = floor((width - DynamicImageGridMetrics.spacing * 2) / 3)
        let largeSide = smallSide * 2 + DynamicImageGridMetrics.spacing

        HStack(spacing: DynamicImageGridMetrics.spacing) {
            if let first = layout.primaryTile {
                tile(first, cornerRadius: 10)
                    .frame(width: largeSide, height: largeSide)
            }

            VStack(spacing: DynamicImageGridMetrics.spacing) {
                ForEach(layout.trailingTiles) { item in
                    tile(item)
                        .frame(width: smallSide, height: smallSide)
                }
            }
        }
        .frame(width: width, height: largeSide, alignment: .leading)
    }

    private func tile(
        _ item: DynamicImageDisplayItem,
        cornerRadius: CGFloat = 8
    ) -> some View {
        DynamicImageGridTile(
            item: item,
            imagesCount: imagesCount,
            previewItems: previewItems,
            previewGroup: previewGroup,
            displayMode: .square(cornerRadius: cornerRadius)
        )
    }
}

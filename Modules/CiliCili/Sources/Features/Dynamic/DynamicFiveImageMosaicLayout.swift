import SwiftUI

struct DynamicFiveImageMosaicLayout: View {
    let imagesCount: Int
    let layout: DynamicImageGridLayout
    let previewItems: [ZoomyImagePreviewItem]
    let previewGroup: ZoomyImagePreviewGroup
    let width: CGFloat

    var body: some View {
        let largeSide = floor((width - DynamicImageGridMetrics.spacing) / 2)
        let smallSide = DynamicImageGridMetrics.tileSide(for: width, columns: 3)

        VStack(spacing: DynamicImageGridMetrics.spacing) {
            HStack(spacing: DynamicImageGridMetrics.spacing) {
                ForEach(layout.topTiles) { item in
                    tile(item, cornerRadius: 10)
                        .frame(width: largeSide, height: largeSide)
                }
            }

            HStack(spacing: DynamicImageGridMetrics.spacing) {
                ForEach(layout.middleTiles) { item in
                    tile(item)
                        .frame(width: smallSide, height: smallSide)
                }
            }
        }
        .frame(
            width: width,
            height: largeSide + DynamicImageGridMetrics.spacing + smallSide,
            alignment: .topLeading
        )
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

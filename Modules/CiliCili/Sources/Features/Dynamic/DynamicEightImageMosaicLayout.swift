import SwiftUI

struct DynamicEightImageMosaicLayout: View {
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

            DynamicImageFixedRows(
                imagesCount: imagesCount,
                rows: layout.eightImageRows,
                previewItems: previewItems,
                previewGroup: previewGroup,
                width: width,
                tileSide: smallSide
            )
        }
        .frame(
            width: width,
            height: largeSide + DynamicImageGridMetrics.spacing + smallSide * 2 + DynamicImageGridMetrics.spacing,
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

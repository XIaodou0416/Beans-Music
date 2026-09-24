import SwiftUI

struct DynamicSevenImageMosaicLayout: View {
    let imagesCount: Int
    let layout: DynamicImageGridLayout
    let previewItems: [ZoomyImagePreviewItem]
    let previewGroup: ZoomyImagePreviewGroup
    let width: CGFloat

    var body: some View {
        let smallSide = DynamicImageGridMetrics.tileSide(for: width, columns: 3)
        let largeSide = smallSide * 2 + DynamicImageGridMetrics.spacing
        let footerSide = DynamicImageGridMetrics.tileSide(for: width, columns: 4)

        VStack(spacing: DynamicImageGridMetrics.spacing) {
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

            HStack(spacing: DynamicImageGridMetrics.spacing) {
                ForEach(layout.bottomTiles) { item in
                    tile(item)
                        .frame(width: footerSide, height: footerSide)
                }
            }
        }
        .frame(
            width: width,
            height: largeSide + DynamicImageGridMetrics.spacing + footerSide,
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

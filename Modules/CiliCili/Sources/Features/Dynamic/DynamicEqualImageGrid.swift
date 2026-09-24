import SwiftUI

struct DynamicEqualImageGrid: View {
    let imagesCount: Int
    let layout: DynamicImageGridLayout
    let previewItems: [ZoomyImagePreviewItem]
    let previewGroup: ZoomyImagePreviewGroup
    let width: CGFloat
    let columns: Int

    var body: some View {
        let side = DynamicImageGridMetrics.tileSide(for: width, columns: columns)

        VStack(spacing: DynamicImageGridMetrics.spacing) {
            ForEach(layout.rows(for: columns)) { row in
                HStack(spacing: DynamicImageGridMetrics.spacing) {
                    ForEach(row.items) { item in
                        tile(item, cornerRadius: columns == 2 ? 10 : 8)
                            .frame(width: side, height: side)
                    }

                    if row.items.count < columns {
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .frame(width: width, alignment: .topLeading)
    }

    private func tile(
        _ item: DynamicImageDisplayItem,
        cornerRadius: CGFloat
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

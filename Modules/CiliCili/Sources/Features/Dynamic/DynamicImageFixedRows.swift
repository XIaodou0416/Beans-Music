import SwiftUI

struct DynamicImageFixedRows: View {
    let imagesCount: Int
    let rows: [DynamicImageGridRow]
    let previewItems: [ZoomyImagePreviewItem]
    let previewGroup: ZoomyImagePreviewGroup
    let width: CGFloat
    let tileSide: CGFloat

    var body: some View {
        VStack(spacing: DynamicImageGridMetrics.spacing) {
            ForEach(rows) { row in
                HStack(spacing: DynamicImageGridMetrics.spacing) {
                    ForEach(row.items) { item in
                        DynamicImageGridTile(
                            item: item,
                            imagesCount: imagesCount,
                            previewItems: previewItems,
                            previewGroup: previewGroup,
                            displayMode: .square(cornerRadius: 8)
                        )
                        .frame(width: tileSide, height: tileSide)
                    }
                }
            }
        }
        .frame(width: width, alignment: .topLeading)
    }
}

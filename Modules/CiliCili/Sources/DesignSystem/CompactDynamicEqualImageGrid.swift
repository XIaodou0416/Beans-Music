import SwiftUI

struct CompactDynamicEqualImageGrid: View {
    let tileContext: CompactDynamicImageTileContext
    let layout: CompactDynamicImageMosaicLayout
    let columns: Int
    let side: CGFloat

    var body: some View {
        VStack(spacing: CompactDynamicImageMosaicMetrics.spacing) {
            ForEach(layout.rows(for: columns)) { row in
                HStack(spacing: CompactDynamicImageMosaicMetrics.spacing) {
                    ForEach(row.items) { item in
                        CompactDynamicImageTile(
                            context: tileContext,
                            item: item,
                            size: CGSize(width: side, height: side)
                        )
                    }
                }
            }
        }
        .frame(
            width: CompactDynamicImageMosaicMetrics.gridWidth(columns: columns, side: side),
            alignment: .topLeading
        )
    }
}

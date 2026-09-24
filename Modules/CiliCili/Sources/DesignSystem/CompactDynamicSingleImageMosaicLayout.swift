import SwiftUI

struct CompactDynamicSingleImageMosaicLayout: View {
    let tileContext: CompactDynamicImageTileContext
    let item: CompactDynamicImageDisplayItem?

    var body: some View {
        HStack {
            if let item {
                CompactDynamicImageTile(context: tileContext, item: item)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: CompactDynamicImageMosaicMetrics.compactWidth, alignment: .leading)
    }
}

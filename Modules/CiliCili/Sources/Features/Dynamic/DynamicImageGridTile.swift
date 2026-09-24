import SwiftUI

struct DynamicImageGridTile: View {
    let item: DynamicImageDisplayItem
    let imagesCount: Int
    let previewItems: [ZoomyImagePreviewItem]
    let previewGroup: ZoomyImagePreviewGroup
    let displayMode: DynamicImageCell.DisplayMode

    var body: some View {
        DynamicImageButton(
            image: item.image,
            previewItems: previewItems,
            previewItemID: item.id,
            previewGroup: previewGroup,
            displayMode: displayMode
        ) {
            overflowOverlay
        }
        .accessibilityLabel(
            imagesCount > 1
                ? "查看第 \(item.index + 1) 张图片，共 \(imagesCount) 张"
                : "查看图片"
        )
    }

    @ViewBuilder
    private var overflowOverlay: some View {
        if item.index == 8, imagesCount > 9 {
            ZStack {
                Color.clear
                Text("+\(imagesCount - 9)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .videoCoverBadgeBackground(style: .regular, in: Capsule())
            }
        }
    }
}

import SwiftUI

struct CompactDynamicImageTileContext {
    let imageCount: Int
    let previewItems: [ZoomyImagePreviewItem]
    let previewGroup: ZoomyImagePreviewGroup
    let accessibilityName: String
    let placeholderFill: Color
}

struct CompactDynamicImageTile: View {
    let context: CompactDynamicImageTileContext
    let item: CompactDynamicImageDisplayItem
    let size: CGSize?

    init(
        context: CompactDynamicImageTileContext,
        item: CompactDynamicImageDisplayItem,
        size: CGSize? = nil
    ) {
        self.context = context
        self.item = item
        self.size = size
    }

    var body: some View {
        CompactDynamicImageThumbnail(
            image: item.image,
            previewItems: context.previewItems,
            previewItemID: item.id,
            previewGroup: context.previewGroup,
            imageCount: context.imageCount,
            aspectRatio: item.aspectRatio,
            placeholderFill: context.placeholderFill,
            thumbnailSizeOverride: size
        )
        .overlay {
            overflowOverlay
        }
        .overlay(alignment: .bottomTrailing) {
            DynamicImageBadgeRow(
                mediaBadgeText: item.image.mediaBadgeText,
                showsLongImage: item.isLongImage
            )
            .padding(6)
        }
        .accessibilityLabel(accessibilityTitle(for: item.index))
    }

    @ViewBuilder
    private var overflowOverlay: some View {
        if item.index == 8, context.imageCount > 9 {
            ZStack {
                Color.clear
                Text("+\(context.imageCount - 9)")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .videoCoverBadgeBackground(style: .regular, in: Capsule())
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func accessibilityTitle(for index: Int) -> String {
        context.imageCount > 1
            ? "第 \(index + 1) 张\(context.accessibilityName)，共 \(context.imageCount) 张"
            : context.accessibilityName
    }
}

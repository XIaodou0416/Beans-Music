import SwiftUI

struct DynamicImageCellRemoteContent: View {
    let normalizedURLString: String?
    let mediaBadgeText: String?
    let showsLongImage: Bool
    let previewItems: [ZoomyImagePreviewItem]
    let previewItemID: String?
    let previewGroup: ZoomyImagePreviewGroup?
    let targetPixelSize: Int
    let cornerRadius: CGFloat
    let contentMode: ZoomyImageContentMode
    let contentAlignment: ZoomyImageContentAlignment
    let onViewerPresentationChange: (Bool) -> Void

    var body: some View {
        ZStack {
            BiliMediaPlaceholder(style: .image, iconSize: 19)

            ZoomyRemoteImage(
                url: normalizedURLString
                    .map { $0.biliImageThumbnailURL(maxSide: targetPixelSize) }
                    .flatMap(URL.init(string:)),
                fallbackURL: normalizedURLString.flatMap(URL.init(string:)),
                viewerURL: normalizedURLString.flatMap(URL.init(string:)),
                viewerItems: previewItems,
                viewerItemID: previewItemID,
                viewerGroup: previewGroup,
                targetPixelSize: targetPixelSize,
                cornerRadius: cornerRadius,
                contentMode: contentMode,
                contentAlignment: contentAlignment,
                onViewerPresentationChange: onViewerPresentationChange
            ) { phase in
                BiliMediaPlaceholder(
                    style: .image,
                    phase: phase,
                    iconSize: 19
                )
            }

            DynamicImageBadgeRow(
                mediaBadgeText: mediaBadgeText,
                showsLongImage: showsLongImage
            )
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
    }
}

import SwiftUI

struct CompactDynamicImageThumbnail: View {
    let image: DynamicImageItem
    let previewItems: [ZoomyImagePreviewItem]
    let previewItemID: String
    let previewGroup: ZoomyImagePreviewGroup
    let imageCount: Int
    let placeholderFill: Color
    @State private var thumbnailShadowOpacityScale = 1.0
    private let normalizedURLString: String?
    private let thumbnailSize: CGSize
    @Environment(\.displayScale) private var displayScale

    init(
        image: DynamicImageItem,
        previewItems: [ZoomyImagePreviewItem],
        previewItemID: String,
        previewGroup: ZoomyImagePreviewGroup,
        imageCount: Int,
        aspectRatio: CGFloat,
        placeholderFill: Color,
        thumbnailSizeOverride: CGSize? = nil
    ) {
        self.image = image
        self.previewItems = previewItems
        self.previewItemID = previewItemID
        self.previewGroup = previewGroup
        self.imageCount = imageCount
        self.placeholderFill = placeholderFill
        let normalizedURLString = image.normalizedURL
        self.normalizedURLString = normalizedURLString
        self.thumbnailSize = thumbnailSizeOverride ?? Self.thumbnailSize(imageCount: imageCount, aspectRatio: aspectRatio)
    }

    var body: some View {
        ZoomyRemoteImage(
            url: thumbnailURL,
            fallbackURL: normalizedURLString.flatMap(URL.init(string:)),
            viewerURL: normalizedURLString.flatMap(URL.init(string:)),
            viewerItems: previewItems,
            viewerItemID: previewItemID,
            viewerGroup: previewGroup,
            targetPixelSize: targetPixelSize,
            cornerRadius: 8,
            onViewerPresentationChange: updateThumbnailShadowVisibility
        ) { phase in
            BiliMediaPlaceholder(
                style: .image,
                phase: phase,
                iconSize: 15
            )
                .background(placeholderFill)
        }
        .frame(width: thumbnailSize.width, height: thumbnailSize.height)
        .videoCoverSurface(
            cornerRadius: 8,
            shadowLevel: .subtle,
            shadowOpacityScale: thumbnailShadowOpacityScale,
            borderOpacityScale: thumbnailShadowOpacityScale,
            appliesUnifiedBorder: false
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func updateThumbnailShadowVisibility(isViewerPresented: Bool) {
        if isViewerPresented {
            thumbnailShadowOpacityScale = 0
        } else {
            withAnimation(.easeOut(duration: 0.18)) {
                thumbnailShadowOpacityScale = 1
            }
        }
    }

    private var thumbnailURL: URL? {
        normalizedURLString
            .map { $0.biliCoverThumbnailURL(fitting: thumbnailSize, scale: displayScale) }
            .flatMap(URL.init(string:))
    }

    private var targetPixelSize: Int {
        Int(ceil(max(thumbnailSize.width, thumbnailSize.height) * displayScale))
    }

    private static func thumbnailSize(imageCount: Int, aspectRatio: CGFloat) -> CGSize {
        if imageCount == 1 {
            let width: CGFloat = 132
            let ratio = min(max(aspectRatio, 0.55), 1.85)
            let height = min(max(width / ratio, 78), 176)
            return CGSize(width: width, height: height)
        }
        return CGSize(width: 86, height: 86)
    }
}

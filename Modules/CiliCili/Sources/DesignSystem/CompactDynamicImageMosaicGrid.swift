import SwiftUI

struct CompactDynamicImageMosaicGrid: View {
    @StateObject private var previewGroup = ZoomyImagePreviewGroup()
    private let imageCount: Int
    private let displayedImages: [CompactDynamicImageDisplayItem]
    private let layout: CompactDynamicImageMosaicLayout
    private let previewItems: [ZoomyImagePreviewItem]
    private let accessibilityName: String
    private let placeholderFill: Color

    init(
        images: [DynamicImageItem],
        accessibilityName: String,
        placeholderFill: Color
    ) {
        let visibleImages = images.filter { $0.normalizedURL != nil }
        let displayedImages = CompactDynamicImageDisplayItems.make(from: visibleImages, limit: 9)
        self.imageCount = visibleImages.count
        self.displayedImages = displayedImages
        self.layout = CompactDynamicImageMosaicLayout(displayedImages: displayedImages)
        self.previewItems = CompactDynamicImageDisplayItems.previewItems(
            from: CompactDynamicImageDisplayItems.make(from: visibleImages)
        )
        self.accessibilityName = accessibilityName
        self.placeholderFill = placeholderFill
    }

    var body: some View {
        if imageCount > 0 {
            CompactDynamicImageMosaicContent(
                imageCount: imageCount,
                displayedImages: displayedImages,
                layout: layout,
                previewItems: previewItems,
                previewGroup: previewGroup,
                accessibilityName: accessibilityName,
                placeholderFill: placeholderFill
            )
        }
    }
}

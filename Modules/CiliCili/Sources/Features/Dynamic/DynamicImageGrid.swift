import SwiftUI

struct DynamicImageGrid: View {
    @StateObject private var previewGroup = ZoomyImagePreviewGroup()
    @State private var availableWidth: CGFloat = Self.defaultWidth
    let images: [DynamicImageItem]
    let knownAvailableWidth: CGFloat?
    private let displayedImages: [DynamicImageDisplayItem]
    private let layout: DynamicImageGridLayout
    private let previewItems: [ZoomyImagePreviewItem]
    private static let defaultWidth: CGFloat = 330
    private static let spacing: CGFloat = 4

    init(images: [DynamicImageItem], availableWidth: CGFloat? = nil) {
        self.images = images
        self.knownAvailableWidth = availableWidth.map { floor($0) }.flatMap { $0 > 1 ? $0 : nil }
        let displayedImages = DynamicImageDisplayItems.make(from: images, limit: 9)
        self.displayedImages = displayedImages
        self.layout = DynamicImageGridLayout(displayedImages: displayedImages)
        self.previewItems = DynamicImageDisplayItems.previewItems(
            from: DynamicImageDisplayItems.make(from: images)
        )
    }

    var body: some View {
        measuredContent {
            DynamicImageGridContent(
                images: images,
                displayedImages: displayedImages,
                layout: layout,
                previewItems: previewItems,
                previewGroup: previewGroup,
                width: resolvedWidth
            )
        }
    }

    private var resolvedWidth: CGFloat {
        if let knownAvailableWidth {
            return knownAvailableWidth
        }
        guard availableWidth > 1 else { return Self.defaultWidth }
        return floor(availableWidth)
    }

    @ViewBuilder
    private func measuredContent<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if knownAvailableWidth != nil {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(widthReader)
                .onPreferenceChange(DynamicImageGridWidthPreferenceKey.self) { width in
                    updateAvailableWidth(width)
                }
        }
    }

    private var widthReader: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: DynamicImageGridWidthPreferenceKey.self,
                    value: proxy.size.width
                )
        }
    }

    private func updateAvailableWidth(_ width: CGFloat) {
        let roundedWidth = floor(width)
        guard roundedWidth > 1, abs(availableWidth - roundedWidth) > 0.5 else { return }
        availableWidth = roundedWidth
    }
}

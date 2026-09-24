import SwiftUI

struct DynamicImageThumbnailStrip: View {
    @StateObject private var previewGroup = ZoomyImagePreviewGroup()
    @State private var availableWidth: CGFloat = Self.defaultWidth
    let images: [DynamicImageItem]
    var horizontalBleed: CGFloat = 0
    let knownAvailableWidth: CGFloat?
    private let displayedImages: [DynamicImageDisplayItem]
    private let previewItems: [ZoomyImagePreviewItem]
    private static let defaultWidth: CGFloat = 330
    private static let singleImageMaxWidthRatio: CGFloat = 0.60
    private static let minSingleImageWidth: CGFloat = 96

    init(
        images: [DynamicImageItem],
        horizontalBleed: CGFloat = 0,
        availableWidth: CGFloat? = nil
    ) {
        self.images = images
        self.horizontalBleed = horizontalBleed
        self.knownAvailableWidth = availableWidth.map { floor($0) }.flatMap { $0 > 1 ? $0 : nil }
        let displayedImages = DynamicImageDisplayItems.make(from: images)
        self.displayedImages = displayedImages
        self.previewItems = DynamicImageDisplayItems.previewItems(from: displayedImages)
    }

    var body: some View {
        switch displayedImages.count {
        case 0:
            EmptyView()
        case 1:
            measuredContent {
                singleImageContent(width: resolvedWidth)
            }
        default:
            DynamicImageGrid(
                images: images,
                availableWidth: knownAvailableWidth.map { max($0 + horizontalBleed * 2, 1) }
            )
            .padding(.horizontal, -horizontalBleed)
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

    @ViewBuilder
    private func singleImageContent(width: CGFloat) -> some View {
        if let item = displayedImages.first {
            let fullWidth = max(width + horizontalBleed * 2, 1)
            let imageWidth = floor(max(fullWidth * Self.singleImageMaxWidthRatio, Self.minSingleImageWidth))
            let aspectRatio = max(item.aspectRatio, 0.1)
            let displayMode: DynamicImageCell.DisplayMode = item.isLongImage
                ? .longImage(cornerRadius: 8)
                : .single
            let imageHeight = item.isLongImage
                ? ceil(imageWidth * 16 / 9)
                : ceil(imageWidth / aspectRatio)

            HStack {
                DynamicImageButton(
                    image: item.image,
                    previewItems: previewItems,
                    previewItemID: item.id,
                    previewGroup: previewGroup,
                    displayMode: displayMode
                )
                .frame(width: imageWidth, height: imageHeight)
                .accessibilityLabel(accessibilityTitle(for: item.index))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, horizontalBleed)
            .frame(width: fullWidth, height: imageHeight, alignment: .leading)
            .padding(.horizontal, -horizontalBleed)
        }
    }

    private func accessibilityTitle(for index: Int) -> String {
        images.count > 1 ? "查看第 \(index + 1) 张图片，共 \(images.count) 张" : "查看图片"
    }
}

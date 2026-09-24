import SwiftUI

struct CommentImageButton: View {
    private let visibleImages: [DynamicImageItem]

    init(images: [DynamicImageItem], transitionScope: String) {
        self.visibleImages = images.filter { $0.normalizedURL != nil }
        _ = transitionScope
    }

    var body: some View {
        if !visibleImages.isEmpty {
            CompactDynamicImageMosaicGrid(
                images: visibleImages,
                accessibilityName: "图片",
                placeholderFill: VideoDetailTheme.secondarySurface
            )
            .padding(.top, 2)
        }
    }
}

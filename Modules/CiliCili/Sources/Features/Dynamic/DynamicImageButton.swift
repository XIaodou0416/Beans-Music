import SwiftUI

struct DynamicImageButton<Overlay: View>: View {
    let image: DynamicImageItem
    let previewItems: [ZoomyImagePreviewItem]
    let previewItemID: String?
    let previewGroup: ZoomyImagePreviewGroup?
    let displayMode: DynamicImageCell.DisplayMode
    @ViewBuilder let overlay: () -> Overlay

    init(
        image: DynamicImageItem,
        previewItems: [ZoomyImagePreviewItem] = [],
        previewItemID: String? = nil,
        previewGroup: ZoomyImagePreviewGroup? = nil,
        displayMode: DynamicImageCell.DisplayMode,
        @ViewBuilder overlay: @escaping () -> Overlay
    ) {
        self.image = image
        self.previewItems = previewItems
        self.previewItemID = previewItemID
        self.previewGroup = previewGroup
        self.displayMode = displayMode
        self.overlay = overlay
    }

    var body: some View {
        DynamicImageCell(
            image: image,
            previewItems: previewItems,
            previewItemID: previewItemID,
            previewGroup: previewGroup,
            displayMode: displayMode
        )
        .overlay(overlay())
        .contentShape(RoundedRectangle(cornerRadius: displayMode.cornerRadius, style: .continuous))
    }
}

extension DynamicImageButton where Overlay == EmptyView {
    init(
        image: DynamicImageItem,
        previewItems: [ZoomyImagePreviewItem] = [],
        previewItemID: String? = nil,
        previewGroup: ZoomyImagePreviewGroup? = nil,
        displayMode: DynamicImageCell.DisplayMode
    ) {
        self.init(
            image: image,
            previewItems: previewItems,
            previewItemID: previewItemID,
            previewGroup: previewGroup,
            displayMode: displayMode
        ) {
            EmptyView()
        }
    }
}

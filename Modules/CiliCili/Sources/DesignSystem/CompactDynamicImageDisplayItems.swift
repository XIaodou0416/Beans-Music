import SwiftUI

struct CompactDynamicImageDisplayItem: Identifiable {
    let id: String
    let index: Int
    let image: DynamicImageItem
    let aspectRatio: CGFloat

    var isLongImage: Bool {
        image.isLongImage || aspectRatio < 0.62
    }
}

enum CompactDynamicImageDisplayItems {
    static func make(from images: [DynamicImageItem], limit: Int? = nil) -> [CompactDynamicImageDisplayItem] {
        let source = limit.map { Array(images.prefix($0)) } ?? images
        var seenIDs = [String: Int]()
        return source.enumerated().map { index, image in
            let normalizedURLString = image.normalizedURL
            let baseID = stableBaseID(
                for: image,
                normalizedURLString: normalizedURLString,
                fallbackIndex: index
            )
            let occurrence = seenIDs[baseID, default: 0]
            seenIDs[baseID] = occurrence + 1
            let id = occurrence == 0 ? baseID : "\(baseID)#\(occurrence)"
            return CompactDynamicImageDisplayItem(
                id: id,
                index: index,
                image: image,
                aspectRatio: aspectRatio(for: image, normalizedURLString: normalizedURLString)
            )
        }
    }

    static func previewItems(from displayItems: [CompactDynamicImageDisplayItem]) -> [ZoomyImagePreviewItem] {
        displayItems.compactMap { item in
            guard let normalizedURLString = item.image.normalizedURL,
                  let url = URL(string: normalizedURLString)
            else { return nil }
            return ZoomyImagePreviewItem(
                id: item.id,
                fallbackURL: url,
                viewerURL: item.image.normalizedAnimatedImageURL.flatMap { URL(string: $0) } ?? url,
                mediaBadgeText: item.image.mediaBadgeText,
                liveVideoURL: item.image.normalizedLiveVideoURL.flatMap(URL.init(string:)),
                aspectRatio: item.aspectRatio
            )
        }
    }

    private static func stableBaseID(
        for image: DynamicImageItem,
        normalizedURLString: String?,
        fallbackIndex: Int
    ) -> String {
        if let normalizedURLString {
            return normalizedURLString
        }
        let trimmedURL = image.url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedURL.isEmpty {
            return trimmedURL
        }
        return "compact-image-\(fallbackIndex)"
    }

    private static func aspectRatio(for image: DynamicImageItem, normalizedURLString: String?) -> CGFloat {
        if let width = image.width, let height = image.height, width > 0, height > 0 {
            return max(CGFloat(width) / CGFloat(height), 0.1)
        }
        if let ratio = normalizedURLString?.biliImageURLAspectRatio {
            return max(CGFloat(ratio), 0.1)
        }
        return 1
    }
}

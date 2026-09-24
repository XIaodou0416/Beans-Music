import SwiftUI

nonisolated enum DynamicImageCellDisplayMode {
    case single
    case longImage(cornerRadius: CGFloat)
    case square(cornerRadius: CGFloat)
    case hero(aspectRatio: CGFloat, cornerRadius: CGFloat)
    case fixedHeight(height: CGFloat, cornerRadius: CGFloat)
}

nonisolated struct DynamicImagePrefetchRequest: Hashable, Sendable {
    let source: RemoteImageSource
    let targetPixelSize: Int
}

nonisolated enum DynamicImageThumbnailSizing {
    static func targetPixelSize(
        usesExpandedImage: Bool,
        usesCompactImages: Bool
    ) -> Int {
        switch (usesExpandedImage, usesCompactImages) {
        case (true, false):
            return 1280
        case (true, true):
            return 960
        case (false, false):
            return 420
        case (false, true):
            return 360
        }
    }

    static func targetPixelSize(
        for displayMode: DynamicImageCellDisplayMode,
        usesCompactImages: Bool
    ) -> Int {
        let usesExpandedImage: Bool
        switch displayMode {
        case .single, .longImage, .hero:
            usesExpandedImage = true
        case .square, .fixedHeight:
            usesExpandedImage = false
        }
        return targetPixelSize(
            usesExpandedImage: usesExpandedImage,
            usesCompactImages: usesCompactImages
        )
    }

    static func prefetchRequest(
        for image: DynamicImageItem,
        imageCount: Int,
        usesCompactImages: Bool
    ) -> DynamicImagePrefetchRequest? {
        guard let sourceURLString = image.normalizedURL,
              let sourceURL = URL(string: sourceURLString)
        else { return nil }

        let targetPixelSize = targetPixelSize(
            usesExpandedImage: imageCount == 1,
            usesCompactImages: usesCompactImages
        )
        let thumbnailURL = URL(
            string: sourceURLString.biliImageThumbnailURL(maxSide: targetPixelSize)
        ) ?? sourceURL
        return DynamicImagePrefetchRequest(
            source: RemoteImageSource(url: thumbnailURL, fallbackURL: sourceURL),
            targetPixelSize: targetPixelSize
        )
    }
}

extension DynamicImageCellDisplayMode {
    var cornerRadius: CGFloat {
        switch self {
        case .single:
            return 8
        case .longImage(let cornerRadius),
             .square(let cornerRadius),
             .hero(_, let cornerRadius),
             .fixedHeight(_, let cornerRadius):
            return cornerRadius
        }
    }

    var isLongImage: Bool {
        if case .longImage = self {
            return true
        }
        return false
    }

    var thumbnailContentMode: ZoomyImageContentMode {
        switch self {
        case .fixedHeight:
            return .fit
        case .single, .longImage, .square, .hero:
            return .fill
        }
    }

    var thumbnailContentAlignment: ZoomyImageContentAlignment {
        switch self {
        case .longImage:
            return .top
        case .single, .square, .hero, .fixedHeight:
            return .center
        }
    }

    func displayAspectRatio(imageAspectRatio: CGFloat) -> CGFloat {
        switch self {
        case .single:
            return imageAspectRatio
        case .longImage:
            return 9 / 16
        case .square:
            return 1
        case .hero(let aspectRatio, _):
            return aspectRatio
        case .fixedHeight:
            return imageAspectRatio
        }
    }

    func thumbnailMaxSide(usesCompactImages: Bool) -> Int {
        DynamicImageThumbnailSizing.targetPixelSize(
            for: self,
            usesCompactImages: usesCompactImages
        )
    }
}

extension DynamicImageCell {
    typealias DisplayMode = DynamicImageCellDisplayMode
}

struct LongImageBadge: View {
    var body: some View {
        GlassEffectContainer(spacing: 8) {
            DynamicImageLongBadgeContent()
        }
    }
}

struct DynamicImageBadgeRow: View {
    let mediaBadgeText: String?
    let showsLongImage: Bool

    var body: some View {
        if mediaBadgeText != nil || showsLongImage {
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    if let mediaBadgeText {
                        DynamicImageMediaBadge(title: mediaBadgeText)
                    }
                    if showsLongImage {
                        DynamicImageLongBadgeContent()
                    }
                }
            }
        }
    }
}

struct DynamicImageMediaBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .videoCoverBadgeForeground(opacity: 0)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .videoCoverBadgeBackground(style: .clear, in: Capsule())
            .accessibilityLabel(title)
    }
}

private struct DynamicImageLongBadgeContent: View {
    var body: some View {
        Label("长图", systemImage: "scroll")
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .videoCoverBadgeForeground(opacity: 0)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .videoCoverBadgeBackground(style: .clear, in: Capsule())
            .accessibilityLabel("长图")
    }
}

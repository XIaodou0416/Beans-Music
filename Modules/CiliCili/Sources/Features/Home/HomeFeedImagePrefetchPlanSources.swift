import SwiftUI

nonisolated struct HomeFeedCoverPrefetchProfile: Equatable {
    private enum Style: String {
        case maxSide
        case exactCrop
    }

    private let style: Style
    private let size: CGSize
    private let displayScale: CGFloat
    private let maximumPixelLength: Int

    var targetPixelSize: Int {
        String.biliThumbnailMaxPixelSide(
            fitting: size,
            scale: displayScale,
            maximumPixelLength: maximumPixelLength
        )
    }

    var cacheIdentity: String {
        "\(style.rawValue)|\(Int(size.width.rounded()))x\(Int(size.height.rounded()))|\(displayScale)|\(maximumPixelLength)"
    }

    static func make(
        layout: HomeFeedLayout,
        metrics: HomeFeedLayoutMetrics,
        displayScale: CGFloat
    ) -> HomeFeedCoverPrefetchProfile {
        let maximumPixelLength: Int
        let style: Style
        let size: CGSize?
        switch layout {
        case .singleColumn:
            maximumPixelLength = 720
            style = .maxSide
            size = metrics.singleColumnFixedCoverSize
        case .borderedSingleColumn:
            maximumPixelLength = 480
            style = .exactCrop
            size = metrics.borderedSingleColumnCoverSize
        case .doubleColumn, .borderedDoubleColumn:
            maximumPixelLength = 480
            style = .exactCrop
            size = metrics.doubleColumnFixedCoverSize
        }

        guard let size, size.width > 0, size.height > 0 else {
            return fallback(for: layout)
        }
        return HomeFeedCoverPrefetchProfile(
            style: style,
            size: size,
            displayScale: max(displayScale, 1),
            maximumPixelLength: maximumPixelLength
        )
    }

    static func fallback(for layout: HomeFeedLayout) -> HomeFeedCoverPrefetchProfile {
        switch layout {
        case .singleColumn:
            HomeFeedCoverPrefetchProfile(
                style: .maxSide,
                size: CGSize(width: 240, height: 135),
                displayScale: 3,
                maximumPixelLength: 720
            )
        case .borderedSingleColumn:
            HomeFeedCoverPrefetchProfile(
                style: .exactCrop,
                size: CGSize(width: 140, height: 88),
                displayScale: 3,
                maximumPixelLength: 480
            )
        case .doubleColumn:
            HomeFeedCoverPrefetchProfile(
                style: .exactCrop,
                size: CGSize(width: 160, height: 90),
                displayScale: 3,
                maximumPixelLength: 480
            )
        case .borderedDoubleColumn:
            HomeFeedCoverPrefetchProfile(
                style: .exactCrop,
                size: CGSize(width: 160, height: 100),
                displayScale: 3,
                maximumPixelLength: 480
            )
        }
    }

    func source(for originalSource: String) -> RemoteImageSource? {
        let source = originalSource.normalizedBiliURL()
        let urlString: String
        switch style {
        case .maxSide:
            urlString = source.biliImageThumbnailURL(
                fitting: size,
                scale: displayScale,
                maximumPixelLength: maximumPixelLength
            )
        case .exactCrop:
            urlString = source.biliCoverThumbnailURL(
                fitting: size,
                scale: displayScale,
                maximumPixelLength: maximumPixelLength
            )
        }
        guard let url = URL(string: urlString) else { return nil }
        return RemoteImageSource(url: url, fallbackURL: URL(string: source))
    }
}

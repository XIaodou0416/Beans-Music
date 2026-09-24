import CoreGraphics

enum PlaybackDetailStableLayout {
    static func portraitWidth(
        containerSize: CGSize,
        fullscreenSize: CGSize,
        windowSize: CGSize?
    ) -> CGFloat {
        min(
            shortSide(of: containerSize),
            shortSide(of: fullscreenSize),
            windowSize.map { shortSide(of: $0) } ?? .greatestFiniteMagnitude
        )
    }

    private static func shortSide(of size: CGSize) -> CGFloat {
        min(size.width, size.height)
    }
}

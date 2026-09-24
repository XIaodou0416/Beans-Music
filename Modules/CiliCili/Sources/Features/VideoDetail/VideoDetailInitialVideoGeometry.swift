import CoreGraphics

enum VideoDetailInitialVideoGeometry {
    static let defaultAspectRatio: CGFloat = 16.0 / 9.0

    static func metadataAspectRatio(for video: VideoItem) -> CGFloat? {
        let candidates = [
            video.dimension?.aspectRatio,
            video.pages?.first?.dimension?.aspectRatio,
        ]

        for candidate in candidates {
            guard let candidate else { continue }
            let ratio = CGFloat(candidate)
            guard ratio.isFinite, ratio > 0.1 else { continue }
            return ratio
        }
        return nil
    }
}

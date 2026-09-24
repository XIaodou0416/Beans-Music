import Foundation
import OSLog

extension VideoDetailViewModel {
    func shouldRefetchForPreferredQuality(_ data: PlayURLData) -> Bool {
        guard let preferredQuality = targetPlaybackPreferredQuality else { return false }
        let variants = playVariants(from: data)
        if variants.contains(where: { $0.satisfiesPreferredQuality(preferredQuality) }) {
            return false
        }
        let playableVariants = variants.filter(\.isPlayable)
        let highestPlayableQuality = playableVariants.map(\.quality).max() ?? 0
        if preferredQuality > highestPlayableQuality,
           !playableVariants.isEmpty,
           playableVariants.allSatisfy(\.isProgressiveFastStart) {
            return true
        }
        return data.shouldRefetchForPreferredQuality(preferredQuality)
    }

    func shouldRefetchForStartupQuality(_ data: PlayURLData) -> Bool {
        !playVariants(from: data)
            .contains(where: \.isPlayable)
    }

    func logSelectedPlayVariant(
        _ variant: PlayVariant?,
        availableVariants: [PlayVariant],
        source: String
    ) {
        let environment = PlaybackEnvironment.current
        let selectedFPS = variant.flatMap { DASHStream.displayFrameRate(from: $0.frameRate) } ?? "-"
        PlayerMetricsLog.logger.info(
            "selectedVariant source=\(source, privacy: .public) bvid=\(self.detail.bvid, privacy: .public) preferred=\(self.libraryStore.effectivePreferredVideoQuality ?? 0, privacy: .public) selectedQ=\(variant?.quality ?? 0, privacy: .public) selectedTitle=\(variant?.title ?? "-", privacy: .public) codec=\(variant?.codec ?? "-", privacy: .public) fps=\(selectedFPS, privacy: .public) bandwidth=\(variant?.bandwidth ?? 0, privacy: .public) progressive=\((variant?.isProgressiveFastStart ?? false), privacy: .public) conservative=\(environment.shouldPreferConservativePlayback, privacy: .public) available=\(Self.qualitySummary(availableVariants), privacy: .public)"
        )
    }
}

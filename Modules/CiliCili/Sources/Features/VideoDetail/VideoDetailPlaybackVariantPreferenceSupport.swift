import Foundation

extension VideoDetailViewModel {
    var requestedPlaybackQuality: Int? {
        didSelectPlayVariantManually
            ? manuallySelectedPlayVariantQuality
            : targetPlaybackPreferredQuality
    }

    func hasRequestedPlayableVariant(in variants: [PlayVariant]) -> Bool {
        guard let requestedPlaybackQuality else { return true }
        return variants.contains { $0.satisfiesPreferredQuality(requestedPlaybackQuality) }
    }

    func preferredDefaultVariant(in variants: [PlayVariant]) -> PlayVariant? {
        preferredDefaultVariant(in: variants, preferredQuality: nil)
    }

    func preferredDefaultVariant(in variants: [PlayVariant], preferredQuality: Int?) -> PlayVariant? {
        let playableVariants = sortedPlayVariants(variants).filter(\.isPlayable)
        let requestedQuality = preferredQuality ?? requestedPlaybackQuality
        guard let requestedQuality else { return playableVariants.first ?? variants.first }
        return Self.preferredPlayableVariant(
            in: playableVariants,
            preferredQuality: requestedQuality
        )
    }

    nonisolated static func preferredPlayableVariant(
        in sortedPlayableVariants: [PlayVariant],
        preferredQuality: Int
    ) -> PlayVariant? {
        if let exactVariant = sortedPlayableVariants.first(where: { $0.satisfiesPreferredQuality(preferredQuality) }) {
            return exactVariant
        }

        guard let preferredIndex = LibraryStore.supportedVideoQualities.firstIndex(of: preferredQuality) else {
            return nil
        }
        let fallbackQualities = LibraryStore.supportedVideoQualities.dropFirst(preferredIndex + 1)
        for quality in fallbackQualities {
            if let variant = sortedPlayableVariants.first(where: { $0.quality == quality }) {
                return variant
            }
        }
        return nil
    }
}

import Foundation

extension VideoDetailViewModel {
    func hlsAlternatePlayVariantCandidates(
        startupVariant: PlayVariant,
        targetVariant: PlayVariant
    ) -> [PlayVariant] {
        let limit = hlsAlternateVideoRenditionLimit
        guard limit > 0 else { return [] }
        let candidates = sortedPlayVariants(playVariants)
            .filter { isHLSAlternateVideoVariant($0, forStartupVariant: startupVariant) }
        guard !candidates.isEmpty else { return [] }

        var selected = [PlayVariant]()
        var seen = Set<String>()
        func append(_ variant: PlayVariant?) {
            guard selected.count < limit,
                  let variant,
                  seen.insert(variant.id).inserted
            else { return }
            selected.append(variant)
        }

        if isHLSAlternateVideoVariant(targetVariant, forStartupVariant: startupVariant) {
            append(targetVariant)
        }
        for quality in hlsManualSwitchWarmupQualityOrder(targetQuality: targetVariant.quality) {
            append(candidates.first { $0.quality == quality })
        }
        for candidate in candidates {
            append(candidate)
        }
        return selected
    }
}

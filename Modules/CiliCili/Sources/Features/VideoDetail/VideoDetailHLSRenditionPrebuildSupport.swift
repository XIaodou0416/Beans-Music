import Foundation

extension VideoDetailViewModel {
    var hlsRenditionPrebuildLimit: Int {
        let environment = PlaybackEnvironment.current
        guard !environment.shouldPreferConservativePlayback else { return 0 }
        switch environment.networkClass {
        case .wifi:
            return 2
        case .unknown:
            return 1
        case .cellular, .constrained:
            return 0
        }
    }

    func hlsRenditionPrebuildCandidates(
        startupVariant: PlayVariant,
        targetVariant: PlayVariant?
    ) -> [PlayVariant] {
        let limit = hlsRenditionPrebuildLimit
        guard limit > 0,
              let startupAudioURL = startupVariant.audioURL
        else { return [] }
        let candidates = sortedPlayVariants(playVariants)
            .filter {
                $0.isPlayable
                    && $0.id != startupVariant.id
                    && $0.audioURL == startupAudioURL
                    && $0.videoStream?.isHardwareDecodingCompatibleVideo == true
                    && $0.videoURL != nil
            }
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
        append(candidates.first { $0.id == targetVariant?.id })
        let targetQuality = targetVariant?.quality ?? startupVariant.quality
        for quality in hlsManualSwitchWarmupQualityOrder(targetQuality: targetQuality) {
            append(candidates.first { $0.quality == quality })
        }
        for candidate in candidates {
            append(candidate)
        }
        return selected
    }
}

import Foundation

extension VideoDetailViewModel {
    func seekWarmupVariants(
        primary variant: PlayVariant,
        pressureReason: String?,
        variantLimit: Int
    ) -> [PlayVariant] {
        var result = [PlayVariant]()
        var seen = Set<String>()

        func append(_ candidate: PlayVariant?) {
            guard let candidate,
                  candidate.isPlayable,
                  candidate.videoURL != nil,
                  candidate.videoStream?.isHardwareDecodingCompatibleVideo == true,
                  seen.insert(candidate.id).inserted
            else { return }
            result.append(candidate)
        }

        append(variant)
        guard variantLimit > 1,
              variant.audioURL != nil
        else { return result }
        let preferred = preferredDefaultVariant(in: playVariants)
        let audioMatchedPreferred = preferred?.audioURL == variant.audioURL ? preferred : nil
        append(audioMatchedPreferred)
        if result.count < variantLimit {
            append(seekWarmupFallbackVariant(
                primary: variant,
                preferred: audioMatchedPreferred,
                pressureReason: pressureReason
            ))
        }
        return Array(result.prefix(variantLimit))
    }
}

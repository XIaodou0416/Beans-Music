import Foundation

extension VideoDetailViewModel {
    func seekWarmupFallbackVariant(
        primary variant: PlayVariant,
        preferred: PlayVariant?,
        pressureReason: String?
    ) -> PlayVariant? {
        guard pressureReason != nil else { return nil }
        let referenceQuality = min(variant.quality, preferred?.quality ?? variant.quality)
        let candidates = sortedPlayVariants(playVariants)
            .filter {
                $0.isPlayable
                    && $0.id != variant.id
                    && $0.id != preferred?.id
                    && $0.audioURL == variant.audioURL
                    && $0.quality < referenceQuality
                    && $0.dynamicRange != .dolbyVision
                    && $0.videoStream?.isHardwareDecodingCompatibleVideo == true
                    && $0.videoURL != nil
            }
        return candidates.first(where: { !$0.isProgressiveFastStart })
            ?? candidates.first
    }
}

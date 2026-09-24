import Foundation

extension VideoDetailViewModel {
    func hlsManualSwitchWarmupQualityOrder(targetQuality: Int) -> [Int] {
        var qualities = [Int]()
        func append(_ quality: Int) {
            guard !qualities.contains(quality) else { return }
            qualities.append(quality)
        }
        append(targetQuality)
        [112, 80, 64, 32].forEach(append)
        return qualities
    }

    func isHLSAlternateVideoVariant(_ variant: PlayVariant, forStartupVariant startupVariant: PlayVariant) -> Bool {
        variant.isPlayable
            && variant.id != startupVariant.id
            && variant.audioURL == startupVariant.audioURL
            && variant.dynamicRange == startupVariant.dynamicRange
            && variant.videoStream?.isHardwareDecodingCompatibleVideo == true
            && variant.videoURL != nil
            && variantsShareVideoCodecFamily(variant, startupVariant)
            && variantsShareStartupFrameRateClass(variant, startupVariant)
    }

    var hlsAlternateVideoRenditionLimit: Int {
        switch PlaybackEnvironment.current.networkClass {
        case .wifi:
            return 3
        case .unknown:
            return 2
        case .cellular, .constrained:
            return 1
        }
    }
}

import Foundation

extension VideoDetailViewModel {
    func sortedPlayVariants(_ variants: [PlayVariant]) -> [PlayVariant] {
        let shouldPreferEfficientVideo = playbackAdaptationProfile.prefersEnergyEfficientVideo
            || PlaybackEnvironment.current.shouldPreferConservativePlayback
        return variants.sorted { lhs, rhs in
            if lhs.isPlayable != rhs.isPlayable {
                return lhs.isPlayable && !rhs.isPlayable
            }
            if shouldPreferEfficientVideo {
                if lhs.isHardwareDecodingCompatible != rhs.isHardwareDecodingCompatible {
                    return lhs.isHardwareDecodingCompatible && !rhs.isHardwareDecodingCompatible
                }
                let lhsFPS = variantFrameRate(lhs)
                let rhsFPS = variantFrameRate(rhs)
                let lhsIsHighFrameRate = lhsFPS >= 50
                let rhsIsHighFrameRate = rhsFPS >= 50
                if lhsIsHighFrameRate != rhsIsHighFrameRate {
                    return !lhsIsHighFrameRate && rhsIsHighFrameRate
                }
            }
            if lhs.isProgressiveFastStart != rhs.isProgressiveFastStart {
                return !lhs.isProgressiveFastStart && rhs.isProgressiveFastStart
            }
            if lhs.quality != rhs.quality {
                return lhs.quality > rhs.quality
            }
            let lhsFPS = variantFrameRate(lhs)
            let rhsFPS = variantFrameRate(rhs)
            if lhsFPS != rhsFPS {
                return lhsFPS > rhsFPS
            }
            return (lhs.bandwidth ?? 0) > (rhs.bandwidth ?? 0)
        }
    }
}

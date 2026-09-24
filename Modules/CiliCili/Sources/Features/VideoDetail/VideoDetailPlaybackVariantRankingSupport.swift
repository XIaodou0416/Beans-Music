import Foundation

extension VideoDetailViewModel {
    func variant(_ candidate: PlayVariant, isBetterThan current: PlayVariant) -> Bool {
        if candidate.isProgressiveFastStart != current.isProgressiveFastStart {
            return !candidate.isProgressiveFastStart && current.isProgressiveFastStart
        }
        if candidate.quality != current.quality {
            return candidate.quality > current.quality
        }
        let candidateFPS = variantFrameRate(candidate)
        let currentFPS = variantFrameRate(current)
        if candidateFPS != currentFPS {
            return candidateFPS > currentFPS
        }
        return (candidate.bandwidth ?? 0) > (current.bandwidth ?? 0)
    }

    func energyEfficientVariant(in variants: [PlayVariant], preferredQuality: Int) -> PlayVariant? {
        let sortedVariants = sortedPlayVariants(variants)
            .filter {
                $0.quality <= preferredQuality
                    && $0.dynamicRange != .dolbyVision
            }
        let hardwareDecoded = sortedVariants.filter(\.isHardwareDecodingCompatible)
        let candidates = hardwareDecoded.isEmpty ? sortedVariants : hardwareDecoded
        if let lowFrameRate = candidates.first(where: { variantFrameRate($0) < 50 }) {
            return lowFrameRate
        }
        return candidates.first
    }
}

import Foundation

extension VideoDetailViewModel {
    func seekWarmupPlan(primary variant: PlayVariant) -> VideoDetailSeekWarmupPlan {
        let pressureReason = seekWarmupPressureReason(primary: variant)
        let variantLimit = seekWarmupVariantLimit(pressureReason: pressureReason)
        let variants = seekWarmupVariants(
            primary: variant,
            pressureReason: pressureReason,
            variantLimit: variantLimit
        )
        return VideoDetailSeekWarmupPlan(
            variants: variants,
            variantLimit: variantLimit,
            pressureReason: pressureReason ?? "normal"
        )
    }
}

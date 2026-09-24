import Foundation

extension VideoDetailViewModel {
    func variantFrameRate(_ variant: PlayVariant) -> Double {
        if let frameRate = DASHStream.numericFrameRate(from: variant.frameRate) {
            return frameRate
        }
        if [116, 74].contains(variant.quality) {
            return 60
        }
        if variant.title.contains("高帧")
            || variant.title.contains("60")
            || variant.badge?.contains("高帧") == true
            || variant.badge?.contains("60") == true {
            return 60
        }
        return 0
    }
}

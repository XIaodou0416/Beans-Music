import Foundation

extension VideoDetailViewModel {
    func variantsShareStartupFrameRateClass(_ lhs: PlayVariant, _ rhs: PlayVariant) -> Bool {
        let lhsIsHighFrameRate = variantFrameRate(lhs) >= 50
        let rhsIsHighFrameRate = variantFrameRate(rhs) >= 50
        return lhsIsHighFrameRate == rhsIsHighFrameRate
    }

    func variantsShareVideoCodecFamily(_ lhs: PlayVariant, _ rhs: PlayVariant) -> Bool {
        guard let lhsCodec = videoCodecFamily(lhs),
              let rhsCodec = videoCodecFamily(rhs)
        else {
            return true
        }
        return lhsCodec == rhsCodec
    }

    func videoCodecFamily(_ variant: PlayVariant) -> String? {
        if let codecid = variant.videoStream?.codecid {
            switch codecid {
            case 7:
                return "avc"
            case 12:
                return "hevc"
            case 13:
                return "av1"
            default:
                break
            }
        }

        let codec = (variant.videoStream?.codecs ?? variant.codec ?? "").lowercased()
        if codec.contains("avc1") || codec.contains("avc3") {
            return "avc"
        }
        if codec.contains("hvc1") || codec.contains("hev1") || codec.contains("dvh1") || codec.contains("dvhe") {
            return "hevc"
        }
        if codec.contains("av01") {
            return "av1"
        }
        return nil
    }
}

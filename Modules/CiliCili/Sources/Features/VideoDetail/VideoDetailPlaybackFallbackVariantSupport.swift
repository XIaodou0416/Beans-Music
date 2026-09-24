import Foundation

enum VideoDetailPlaybackFallbackKind: String, Sendable {
    case progressiveStream
    case sameQualityCodec
    case hdrToSDR
    case lowerQuality
    case alternateVariant
}

struct VideoDetailPlaybackFallbackContext: Equatable, Sendable {
    let failedVariant: PlayVariant
    let fallbackVariant: PlayVariant

    var kind: VideoDetailPlaybackFallbackKind {
        if fallbackVariant.isProgressiveFastStart {
            return .progressiveStream
        }
        if isSameQualityCodecFallback {
            return .sameQualityCodec
        }
        if failedVariant.dynamicRange.isHDR, fallbackVariant.dynamicRange == .sdr {
            return .hdrToSDR
        }
        if fallbackVariant.quality != failedVariant.quality {
            return .lowerQuality
        }
        return .alternateVariant
    }

    var userMessage: String {
        let target = fallbackTargetTitle
        switch failedVariant.dynamicRange {
        case .dolbyVision:
            return "杜比视界当前不可播放，已切换到 \(target)"
        case .hdr10, .hlg:
            return "HDR 当前不可播放，已切换到 \(target)"
        case .sdr:
            if isSameQualityCodecFallback {
                return "\(failedCodecTitle) 当前不可播放，已切换到 \(target)"
            }
            return "当前线路播放失败，已切换到 \(target)"
        }
    }

    var metricParts: [String] {
        [
            "fallbackQ=\(fallbackVariant.quality)",
            "fallbackCodec=\(fallbackCodecTitle)",
            "fallbackRange=\(fallbackVariant.dynamicRange.rawValue)",
            "fallbackKind=\(kind.rawValue)",
            "hardwareFallback=\(hardwareFallbackMetricValue)"
        ]
    }

    var logDescription: String {
        [
            "from=\(failedVariant.quality)",
            "to=\(fallbackVariant.quality)",
            "fromCodec=\(failedCodecTitle)",
            "toCodec=\(fallbackCodecTitle)",
            "fromRange=\(failedVariant.dynamicRange.rawValue)",
            "toRange=\(fallbackVariant.dynamicRange.rawValue)",
            "kind=\(kind.rawValue)"
        ].joined(separator: " ")
    }

    private var isSameQualityCodecFallback: Bool {
        failedVariant.quality == fallbackVariant.quality
            && failedCodecFamily != fallbackCodecFamily
            && fallbackCodecFamily != .unknown
    }

    private var fallbackTargetTitle: String {
        if fallbackVariant.isProgressiveFastStart {
            return "\(fallbackVariant.title) 单流"
        }
        let parts = [fallbackCodecTitle, dynamicRangeTitle(fallbackVariant.dynamicRange)]
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return fallbackVariant.title }
        return parts.joined(separator: " / ")
    }

    private var failedCodecFamily: VideoCodecFamily {
        codecFamily(for: failedVariant)
    }

    private var fallbackCodecFamily: VideoCodecFamily {
        codecFamily(for: fallbackVariant)
    }

    private var failedCodecTitle: String {
        codecTitle(family: failedCodecFamily, fallback: failedVariant.codec)
    }

    private var fallbackCodecTitle: String {
        if fallbackVariant.isProgressiveFastStart {
            return "Progressive"
        }
        return codecTitle(family: fallbackCodecFamily, fallback: fallbackVariant.codec)
    }

    private var hardwareFallbackMetricValue: String {
        switch kind {
        case .progressiveStream:
            return "progressive"
        case .sameQualityCodec:
            return "sameQualityCodec"
        case .hdrToSDR:
            return "hdrToSDR"
        case .lowerQuality:
            return "lowerQuality"
        case .alternateVariant:
            return "alternateVariant"
        }
    }

    private func codecFamily(for variant: PlayVariant) -> VideoCodecFamily {
        if let videoStream = variant.videoStream {
            return videoStream.videoCodecFamily
        }
        let codec = (variant.codec ?? "").lowercased()
        if codec.contains("hvc1") || codec.contains("hev1") || codec.contains("dvh1") || codec.contains("dvhe") {
            return .hevc
        }
        if codec.contains("avc1") || codec.contains("avc3") || codec.contains("avc") {
            return .h264
        }
        if codec.contains("av01") {
            return .av1
        }
        return .unknown
    }

    private func codecTitle(family: VideoCodecFamily, fallback: String?) -> String {
        if family != .unknown {
            return family.title
        }
        let value = fallback?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "codec未知" : value
    }

    private func dynamicRangeTitle(_ dynamicRange: BiliVideoDynamicRange) -> String {
        switch dynamicRange {
        case .sdr:
            return "SDR"
        case .hdr10:
            return "HDR10"
        case .hlg:
            return "HLG"
        case .dolbyVision:
            return "Dolby Vision"
        }
    }
}

extension VideoDetailViewModel {
    func playbackFallbackVariant(excluding failedVariant: PlayVariant) -> PlayVariant? {
        if let progressiveFallback = sameQualityProgressiveFallbackVariant(excluding: failedVariant) {
            return progressiveFallback
        }
        if let codecFallback = sameQualityCodecFallbackVariant(excluding: failedVariant) {
            return codecFallback
        }
        if failedVariant.dynamicRange.isHDR,
           let hdrFallback = sdrPlaybackFallbackVariant(excluding: failedVariant) {
            return hdrFallback
        }

        let candidates = sortedPlayVariants(playVariants)
            .filter {
                $0.isPlayable
                    && $0.id != failedVariant.id
                    && !failedPlayVariantIDs.contains($0.id)
            }
        guard !candidates.isEmpty else { return nil }

        let lowerOrEqualQuality = candidates
            .filter { $0.quality <= failedVariant.quality }
        if let fallback = lowerOrEqualQuality
            .first(where: { !$0.isProgressiveFastStart }) {
            return fallback
        }
        return lowerOrEqualQuality.first
            ?? candidates.first(where: { !$0.isProgressiveFastStart })
            ?? candidates.first
    }

    private func sdrPlaybackFallbackVariant(excluding failedVariant: PlayVariant) -> PlayVariant? {
        let candidates = sortedPlayVariants(playVariants)
            .filter {
                $0.isPlayable
                    && $0.id != failedVariant.id
                    && !failedPlayVariantIDs.contains($0.id)
                    && $0.dynamicRange == .sdr
                    && !$0.isProgressiveFastStart
            }
        let preferredFallbackQualities = [116, 112, 80, 120, 74, 64, 32]
        for quality in preferredFallbackQualities {
            if let variant = candidates.first(where: { $0.quality == quality }) {
                return variant
            }
        }
        return candidates.first
            ?? sortedPlayVariants(playVariants).first {
                $0.isPlayable
                    && $0.id != failedVariant.id
                    && $0.dynamicRange == .sdr
            }
    }

    private func sameQualityCodecFallbackVariant(excluding failedVariant: PlayVariant) -> PlayVariant? {
        guard let fallback = HLSVideoRenditionPlanner.codecFallbackVariant(
            startupVariant: failedVariant,
            playURLData: currentPlayURLData,
            cdnPreference: libraryStore.effectivePlaybackCDNPreference,
            codecPreference: libraryStore.videoCodecPreference,
            allowsHDRStartupFallback: true
        ), !failedPlayVariantIDs.contains(fallback.id)
        else { return nil }
        return fallback
    }

    private func sameQualityProgressiveFallbackVariant(excluding failedVariant: PlayVariant) -> PlayVariant? {
        guard let fallback = HLSVideoRenditionPlanner.progressiveFallbackVariant(
            startupVariant: failedVariant,
            playURLData: currentPlayURLData,
            cdnPreference: libraryStore.effectivePlaybackCDNPreference,
            codecPreference: libraryStore.videoCodecPreference
        ), !failedPlayVariantIDs.contains(fallback.id)
        else { return nil }
        return fallback
    }
}

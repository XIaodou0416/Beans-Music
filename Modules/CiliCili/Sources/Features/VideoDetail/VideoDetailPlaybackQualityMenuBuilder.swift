import Foundation

enum VideoDetailPlaybackQualityMenuBuilder {
    static func inlineQualityButtonTitle(
        selectedPlayVariant: PlayVariant?,
        isSwitchingPlayQuality: Bool
    ) -> String {
        if isSwitchingPlayQuality {
            return "切换中"
        }
        return selectedPlayVariant?.compactAccessoryTitle ?? "清晰度"
    }

    static func accessoryQualityButtonTitle(
        selectedPlayVariant: PlayVariant?,
        isSwitchingPlayQuality: Bool
    ) -> String {
        if isSwitchingPlayQuality {
            return "切换中"
        }
        return selectedPlayVariant?.compactAccessoryTitle ?? "清晰度"
    }

    static func makeQualityMenuItems(
        playVariants: [PlayVariant],
        selectedPlayVariant: PlayVariant?,
        pendingPlayVariantID: String?,
        isSwitchingPlayQuality: Bool
    ) -> [VideoDetailPlaybackQualityMenuItem] {
        compactQualityVariants(from: playVariants).map { variant in
            let systemImage: String
            if isPending(variant, pendingPlayVariantID: pendingPlayVariantID, playVariants: playVariants) {
                systemImage = "arrow.triangle.2.circlepath"
            } else if selectedPlayVariant?.quality == variant.quality {
                systemImage = "checkmark"
            } else if variant.isAvailabilityPending {
                systemImage = "arrow.down.circle"
            } else {
                systemImage = variant.isPlayable ? "circle" : "lock.fill"
            }
            return VideoDetailPlaybackQualityMenuItem(
                variant: variant,
                title: variant.qualityMenuTitle,
                subtitle: routeSubtitle(for: variant, selectedPlayVariant: selectedPlayVariant),
                systemImage: systemImage,
                isDisabled: !variant.isSelectableFromQualityMenu || isSwitchingPlayQuality
            )
        }
    }

    private static func compactQualityVariants(from playVariants: [PlayVariant]) -> [PlayVariant] {
        var seenQualities = Set<Int>()
        var result = [PlayVariant]()
        for variant in playVariants {
            guard seenQualities.insert(variant.quality).inserted else { continue }
            result.append(variant)
        }
        return result
    }

    private static func isPending(
        _ menuVariant: PlayVariant,
        pendingPlayVariantID: String?,
        playVariants: [PlayVariant]
    ) -> Bool {
        guard let pendingPlayVariantID else { return false }
        if pendingPlayVariantID == menuVariant.id { return true }
        return playVariants.first { $0.id == pendingPlayVariantID }?.quality == menuVariant.quality
    }

    private static func routeSubtitle(
        for menuVariant: PlayVariant,
        selectedPlayVariant: PlayVariant?
    ) -> String? {
        if menuVariant.isAvailabilityPending {
            return advertisedFormatSubtitle(for: menuVariant)
        }
        let isSelectedQuality = selectedPlayVariant?.quality == menuVariant.quality
        let routeVariant = isSelectedQuality ? (selectedPlayVariant ?? menuVariant) : menuVariant
        let isFallbackRoute = isSelectedQuality && selectedPlayVariant?.id != menuVariant.id
        return routeSubtitle(for: routeVariant, isFallbackRoute: isFallbackRoute)
    }

    private static func advertisedFormatSubtitle(for variant: PlayVariant) -> String {
        let details = variant.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return details.isEmpty ? "DASH" : "\(details) · DASH"
    }

    private static func routeSubtitle(
        for variant: PlayVariant,
        isFallbackRoute: Bool
    ) -> String? {
        guard variant.isPlayable else { return nil }
        if variant.isProgressiveFastStart {
            return isFallbackRoute ? "单流兜底" : "单流"
        }
        guard let videoStream = variant.videoStream else { return "DASH" }
        if !videoStream.isHardwareDecodingCompatibleVideo {
            return isFallbackRoute ? "软解兜底" : "软解 DASH"
        }
        switch videoStream.videoCodecFamily {
        case .h264:
            return isFallbackRoute ? "H.264 兜底" : "H.264 DASH"
        case .hevc:
            return isFallbackRoute ? "HEVC 兜底" : "硬解 DASH"
        case .av1:
            return isFallbackRoute ? "AV1 兜底" : "AV1 DASH"
        case .unknown:
            return isFallbackRoute ? "编码兜底" : "硬解 DASH"
        }
    }
}

import Foundation

extension BiliAPIClient {
    nonisolated static func canUseUnavailablePreferredStartupFallback(
        _ data: PlayURLData,
        requestedQuality: Int,
        isAuthoritativeSource: Bool
    ) -> Bool {
        guard isAuthoritativeSource,
            data.hasPlayableStreamPayload,
            !data.shouldRefetchForPreferredQuality(requestedQuality)
        else {
            return false
        }

        // Prefer the server's explicit quality ladder. Without one, keep the
        // conservative adjacent-rung check because q116 responses can omit q112.
        if data.hasExplicitlyUnavailableQuality(requestedQuality) {
            guard
                let fallbackQuality = BiliVideoQuality.supportedQualities.first(where: {
                    $0 < requestedQuality && data.advertisedQualities.contains($0)
                })
            else {
                return false
            }
            return data.hasPlayableMediaQuality(fallbackQuality)
        }

        guard let fallbackQuality = nextLowerVideoQuality(after: requestedQuality) else { return true }
        return data.hasPlayableMediaQuality(fallbackQuality)
    }

    nonisolated static func canUsePiliPlusCompatibilityResponse(
        _ data: PlayURLData,
        requestedQuality: Int
    ) -> Bool {
        data.hasPlayableMediaQuality(requestedQuality)
            || canUseUnavailablePreferredStartupFallback(
                data,
                requestedQuality: requestedQuality,
                isAuthoritativeSource: true
            )
    }

    struct TargetQualityUnavailableError: LocalizedError, Sendable {
        let requestedQuality: Int
        let fallbackQuality: Int?
        let fallbackData: PlayURLData?

        init(
            requestedQuality: Int,
            fallbackQuality: Int?,
            fallbackData: PlayURLData? = nil
        ) {
            self.requestedQuality = requestedQuality
            self.fallbackQuality = fallbackQuality
            self.fallbackData = fallbackData
        }

        var playableFallbackData: PlayURLData? {
            guard let fallbackData,
                BiliAPIClient.canUseUnavailablePreferredStartupFallback(
                    fallbackData,
                    requestedQuality: requestedQuality,
                    isAuthoritativeSource: true
                )
            else { return nil }
            return fallbackData
        }

        var errorDescription: String? {
            "目标清晰度 \(requestedQuality) 明确不可用"
        }
    }
}

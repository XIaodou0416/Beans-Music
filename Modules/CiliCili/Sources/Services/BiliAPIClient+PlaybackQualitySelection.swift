import OSLog

extension BiliAPIClient {
    nonisolated static func hasPlayableDASHMedia(
        in data: PlayURLData,
        quality: Int,
        codecFamily: VideoCodecFamily
    ) -> Bool {
        guard data.dash?.bestAudioStream?.playURL(cdnPreference: .automatic) != nil else {
            return false
        }
        return (data.dash?.video ?? []).contains { stream in
            guard stream.id == quality,
                stream.videoCodecFamily == codecFamily,
                stream.isHardwareDecodingCompatibleVideo,
                stream.playURL(cdnPreference: .automatic) != nil
            else { return false }
            guard [116, 74].contains(quality) else { return true }
            return DASHStream.numericFrameRate(from: stream.frameRate).map { $0 >= 50 } ?? false
        }
    }

    nonisolated func shouldAcceptPlayURLData(_ data: PlayURLData, requestedQuality: Int) -> Bool {
        data.hasPlayableMediaQuality(requestedQuality)
    }

    nonisolated func preferredPlayURLCandidate(
        _ lhs: PlayURLData?,
        _ rhs: PlayURLData,
        requestedQuality: Int
    ) -> PlayURLData {
        guard let lhs else { return rhs }
        let lhsMatches = shouldAcceptPlayURLData(lhs, requestedQuality: requestedQuality)
        let rhsMatches = shouldAcceptPlayURLData(rhs, requestedQuality: requestedQuality)
        if lhsMatches != rhsMatches {
            return rhsMatches ? rhs : lhs
        }
        let lhsQuality = Self.startupCandidateQuality(in: lhs, requestedQuality: requestedQuality)
        let rhsQuality = Self.startupCandidateQuality(in: rhs, requestedQuality: requestedQuality)
        guard let rhsQuality else { return lhs }
        guard let lhsQuality else { return rhs }
        return rhsQuality > lhsQuality ? rhs : lhs
    }

    func logPreferredQualityMiss(
        stage: String,
        bvid: String,
        cid: Int,
        requestedQuality: Int,
        data: PlayURLData
    ) {
        PlayerMetricsLog.logger.info(
            "preferredQualityMiss stage=\(stage, privacy: .public) bvid=\(bvid, privacy: .public) cid=\(cid, privacy: .public) requested=\(requestedQuality, privacy: .public) available=\(self.qualitySummary(data.playVariants), privacy: .public)"
        )
    }

    private func qualitySummary(_ variants: [PlayVariant]) -> String {
        let qualities =
            variants
            .filter(\.isPlayable)
            .map { "\($0.quality)\($0.audioURL == nil ? "p" : "d")" }
            .joined(separator: ",")
        return qualities.isEmpty ? "-" : qualities
    }

    nonisolated static func requiresAutomaticCodecNegotiation(requestedQuality: Int) -> Bool {
        switch requestedQuality {
        case 125, 126, 129:
            return true
        default:
            return false
        }
    }

    nonisolated static func shouldContinueCodecFallback(
        for data: PlayURLData,
        requestedQuality: Int,
        requestedCodecFamily: VideoCodecFamily? = nil,
        allowsUnavailableQualityFallback: Bool = false
    ) -> Bool {
        if data.hasPlayableMediaQuality(requestedQuality) {
            guard let requestedCodecFamily else { return false }
            return !hasPlayableDASHMedia(
                in: data,
                quality: requestedQuality,
                codecFamily: requestedCodecFamily
            )
        }
        guard allowsUnavailableQualityFallback,
            let requestedCodecFamily,
            data.hasExplicitlyUnavailableQuality(requestedQuality),
            let fallbackQuality = BiliVideoQuality.supportedQualities.first(where: {
                $0 < requestedQuality && data.advertisedQualities.contains($0)
            })
        else { return true }
        return !hasPlayableDASHMedia(
            in: data,
            quality: fallbackQuality,
            codecFamily: requestedCodecFamily
        )
    }

    nonisolated static func startupCandidateQuality(
        in data: PlayURLData,
        requestedQuality: Int
    ) -> Int? {
        data.playVariants
            .filter { variant in
                guard variant.isPlayable, variant.quality <= requestedQuality else {
                    return false
                }
                return variant.quality < requestedQuality
                    || variant.satisfiesPreferredQuality(requestedQuality)
            }
            .map(\.quality)
            .max()
    }

    nonisolated static func nextLowerVideoQuality(after quality: Int) -> Int? {
        BiliVideoQuality.supportedQualities.first { $0 < quality }
    }
}

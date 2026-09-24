import Foundation

extension VideoDetailViewModel {
    func hlsAlternateVideoRenditions(for startupVariant: PlayVariant) -> [PlayerVideoRenditionSource] {
        let limit = hlsAlternateVideoRenditionLimit
        guard limit > 0 else { return [] }

        var renditions = [PlayerVideoRenditionSource]()
        var seenURLs = Set<URL>()
        if let startupURL = startupVariant.videoURL {
            seenURLs.insert(startupURL)
        }

        func append(_ rendition: PlayerVideoRenditionSource) {
            guard renditions.count < limit,
                  seenURLs.insert(rendition.videoURL).inserted
            else { return }
            renditions.append(rendition)
        }

        HLSVideoRenditionPlanner.codecFallbackRenditions(
            startupVariant: startupVariant,
            playURLData: currentPlayURLData,
            cdnPreference: libraryStore.effectivePlaybackCDNPreference,
            codecPreference: libraryStore.videoCodecPreference,
            limit: limit
        ).forEach(append)

        for variant in hlsAlternatePlayVariantCandidates(
            startupVariant: startupVariant,
            targetVariant: startupVariant
        ) {
            guard let videoURL = variant.videoURL,
                  let videoStream = variant.videoStream
            else { continue }
            append(PlayerVideoRenditionSource(
                quality: variant.quality,
                title: variant.title,
                videoURL: videoURL,
                videoStream: videoStream,
                dynamicRange: variant.dynamicRange
            ))
        }

        return renditions
    }
}

nonisolated enum HLSVideoRenditionPlanner {
    static func progressiveFallbackVariant(
        startupVariant: PlayVariant,
        playURLData: PlayURLData?,
        cdnPreference: PlaybackCDNPreference,
        codecPreference: VideoCodecPreference
    ) -> PlayVariant? {
        guard let playURLData,
              startupVariant.audioURL != nil
        else { return nil }

        return playURLData.playVariants(
            cdnPreference: cdnPreference,
            codecPreference: codecPreference,
            requiresHardwareDecode: false
        )
        .first {
            $0.isPlayable
                && $0.isProgressiveFastStart
                && $0.quality == startupVariant.quality
                && $0.id != startupVariant.id
        }
    }

    static func codecFallbackVariant(
        startupVariant: PlayVariant,
        playURLData: PlayURLData?,
        cdnPreference: PlaybackCDNPreference,
        codecPreference: VideoCodecPreference,
        allowsHDRStartupFallback: Bool = false
    ) -> PlayVariant? {
        guard let rendition = codecFallbackRenditions(
            startupVariant: startupVariant,
            playURLData: playURLData,
            cdnPreference: cdnPreference,
            codecPreference: codecPreference,
            limit: 1,
            allowsHDRStartupFallback: allowsHDRStartupFallback
        ).first else { return nil }

        let dynamicRange = rendition.dynamicRange
        return PlayVariant(
            quality: startupVariant.quality,
            title: startupVariant.title,
            videoURL: rendition.videoURL,
            audioURL: startupVariant.audioURL,
            videoStream: rendition.videoStream,
            audioStream: startupVariant.audioStream,
            codec: rendition.videoStream.codecLabel,
            resolution: rendition.videoStream.resolutionLabel,
            frameRate: rendition.videoStream.frameRate,
            bandwidth: rendition.videoStream.bandwidth,
            isHDR: dynamicRange.isHDR,
            badge: dynamicRange.isHDR ? startupVariant.badge : nil,
            dynamicRangeOverride: dynamicRange
        )
    }

    static func codecFallbackRenditions(
        startupVariant: PlayVariant,
        playURLData: PlayURLData?,
        cdnPreference: PlaybackCDNPreference,
        codecPreference: VideoCodecPreference,
        limit: Int,
        allowsHDRStartupFallback: Bool = false
    ) -> [PlayerVideoRenditionSource] {
        guard limit > 0,
              (startupVariant.dynamicRange == .sdr || allowsHDRStartupFallback),
              let playURLData,
              let startupURL = startupVariant.videoURL,
              startupVariant.audioURL != nil,
              let startupFamily = codecFamily(for: startupVariant)
        else { return [] }

        let fallbackFamilies = fallbackCodecFamilies(after: startupFamily, preference: codecPreference)
        guard !fallbackFamilies.isEmpty else { return [] }

        let startupIsHighFrameRate = isHighFrameRate(
            quality: startupVariant.quality,
            title: startupVariant.title,
            badge: startupVariant.badge,
            frameRate: startupVariant.frameRate
        )
        var seenURLs = Set([startupURL])
        return (playURLData.dash?.video ?? [])
            .filter { stream in
                guard stream.id == startupVariant.quality,
                      stream.isHardwareDecodingCompatibleVideo,
                      fallbackFamilies.contains(stream.videoCodecFamily),
                      let url = stream.playURL(cdnPreference: cdnPreference),
                      seenURLs.insert(url).inserted
                else { return false }
                return isHighFrameRate(
                    quality: startupVariant.quality,
                    title: startupVariant.title,
                    badge: startupVariant.badge,
                    frameRate: stream.frameRate
                ) == startupIsHighFrameRate
            }
            .sorted { lhs, rhs in
                streamRank(lhs, preference: codecPreference)
                    .isHigherPriority(than: streamRank(rhs, preference: codecPreference))
            }
            .prefix(limit)
            .compactMap { stream in
                guard let url = stream.playURL(cdnPreference: cdnPreference) else { return nil }
                return PlayerVideoRenditionSource(
                    quality: startupVariant.quality,
                    title: startupVariant.title,
                    videoURL: url,
                    videoStream: stream,
                    dynamicRange: fallbackDynamicRange(for: stream, startupVariant: startupVariant)
                )
            }
    }

    private static func fallbackDynamicRange(
        for stream: DASHStream,
        startupVariant: PlayVariant
    ) -> BiliVideoDynamicRange {
        if stream.isDolbyVisionVideoCodec {
            return .dolbyVision
        }
        if stream.videoCodecFamily == .h264 {
            return .sdr
        }
        return startupVariant.dynamicRange
    }

    private static func fallbackCodecFamilies(
        after startupFamily: VideoCodecFamily,
        preference: VideoCodecPreference
    ) -> Set<VideoCodecFamily> {
        let order = preference.codecOrder
        guard let startupIndex = order.firstIndex(of: startupFamily) else { return [] }
        return Set(order.dropFirst(startupIndex + 1).filter { $0 != .unknown })
    }

    private static func streamRank(
        _ stream: DASHStream,
        preference: VideoCodecPreference
    ) -> StreamRank {
        let codecIndex = preference.codecOrder.firstIndex(of: stream.videoCodecFamily) ?? Int.max
        return StreamRank(codecIndex: codecIndex, negativeBandwidth: -(stream.bandwidth ?? 0))
    }

    private static func codecFamily(for variant: PlayVariant) -> VideoCodecFamily? {
        if let videoStream = variant.videoStream {
            return videoStream.videoCodecFamily
        }
        let codec = (variant.codec ?? "").lowercased()
        if codec.contains("av01") {
            return .av1
        }
        if codec.contains("hvc1") || codec.contains("hev1") || codec.contains("dvh1") || codec.contains("dvhe") {
            return .hevc
        }
        if codec.contains("avc1") || codec.contains("avc3") || codec.contains("avc") {
            return .h264
        }
        return nil
    }

    private static func isHighFrameRate(
        quality: Int,
        title: String,
        badge: String?,
        frameRate: String?
    ) -> Bool {
        if let frameRate = DASHStream.numericFrameRate(from: frameRate) {
            return frameRate >= 50
        }
        return [116, 74].contains(quality)
            || title.contains("高帧")
            || title.contains("60")
            || badge?.contains("高帧") == true
            || badge?.contains("60") == true
    }
}

nonisolated private struct StreamRank {
    let codecIndex: Int
    let negativeBandwidth: Int

    func isHigherPriority(than other: StreamRank) -> Bool {
        if codecIndex != other.codecIndex {
            return codecIndex < other.codecIndex
        }
        return negativeBandwidth < other.negativeBandwidth
    }
}

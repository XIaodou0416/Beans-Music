import Foundation
import OSLog

struct BiliHLSPlaybackManifest: Sendable {
    let masterPlaylistURL: URL
    let bridge: LocalHLSBridge?
    let progressiveLoader: BiliHeaderResourceLoaderDelegate?
    let headers: [String: String]
    let mediaTimeOffset: TimeInterval
}

enum BiliHLSManifestBuilderError: LocalizedError {
    case missingVideoURL
    case missingAudioURL
    case unsupportedCodec
    case manifestGenerationFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingVideoURL:
            return "DASH video URL is missing."
        case .missingAudioURL:
            return "DASH audio URL is missing."
        case .unsupportedCodec:
            return "This DASH codec is not supported by Apple's hardware decoder."
        case .manifestGenerationFailed(let message):
            return "Failed to generate local HLS manifest: \(message)"
        }
    }
}

enum BiliHLSManifestBuilder {
    static func make(
        source: PlayerStreamSource,
        shouldValidateHardwareDecoding: Bool = true,
        includesAlternateVideoRenditions: Bool = true,
        onRemoteFailure: HLSRemoteFailureHandler? = nil
    ) async throws -> BiliHLSPlaybackManifest {
        if source.playbackContentMode == .audioOnly {
            return try await makeAudioOnlyManifest(
                source: source,
                shouldValidateHardwareDecoding: shouldValidateHardwareDecoding,
                onRemoteFailure: onRemoteFailure
            )
        }
        guard let videoURL = source.videoURL else {
            PlayerMetricsLog.logger.error("hlsManifestRejected reason=missingVideoURL")
            throw BiliHLSManifestBuilderError.missingVideoURL
        }
        guard let audioURL = source.audioURL else {
            return try await makeProgressiveManifest(
                mediaURL: videoURL,
                source: source,
                shouldValidateHardwareDecoding: shouldValidateHardwareDecoding
            )
        }
        if shouldValidateHardwareDecoding {
            try validateHardwareDecoding(for: source)
        }

        let headers = source.httpHeaders
        let bridge: LocalHLSBridge
        do {
            let primaryVideoTrack = HLSBridgeTrack(
                url: videoURL,
                fallbackURLs: source.videoStream?.backupPlayURLs(cdnPreference: source.cdnPreference) ?? [],
                stream: source.videoStream,
                mediaType: .video,
                dynamicRange: source.dynamicRange
            )
            let alternateVideoTracks = includesAlternateVideoRenditions
                ? source.alternateVideoRenditions.map { rendition in
                    HLSBridgeTrack(
                        url: rendition.videoURL,
                        fallbackURLs: rendition.videoStream.backupPlayURLs(cdnPreference: source.cdnPreference),
                        stream: rendition.videoStream,
                        mediaType: .video,
                        dynamicRange: rendition.dynamicRange
                    )
                }
                : []
            bridge = try await LocalHLSBridge.make(
                videoTracks: [primaryVideoTrack] + alternateVideoTracks,
                audioTrack: HLSBridgeTrack(
                    url: audioURL,
                    fallbackURLs: source.audioStream?.fallbackPlayURLs(
                        cdnPreference: source.cdnPreference,
                        selectedURL: audioURL
                    ) ?? [],
                    stream: source.audioStream,
                    mediaType: .audio
                ),
                durationHint: source.durationHint,
                headers: headers,
                metricsID: source.metricsID,
                onRemoteFailure: onRemoteFailure
            )
        } catch {
            PlayerMetricsLog.logger.error(
                "hlsManifestFailed error=\(error.localizedDescription, privacy: .public)"
            )
            throw BiliHLSManifestBuilderError.manifestGenerationFailed(error.localizedDescription)
        }

        return BiliHLSPlaybackManifest(
            masterPlaylistURL: bridge.masterPlaylistURL,
            bridge: bridge,
            progressiveLoader: nil,
            headers: headers,
            mediaTimeOffset: bridge.mediaTimeOffset
        )
    }

    private static func makeAudioOnlyManifest(
        source: PlayerStreamSource,
        shouldValidateHardwareDecoding: Bool,
        onRemoteFailure: HLSRemoteFailureHandler?
    ) async throws -> BiliHLSPlaybackManifest {
        guard let audioURL = source.audioURL else {
            PlayerMetricsLog.logger.error("hlsManifestRejected reason=missingAudioURL")
            throw BiliHLSManifestBuilderError.missingAudioURL
        }
        if shouldValidateHardwareDecoding {
            try validateHardwareDecoding(for: source)
        }

        guard let audioStream = source.audioStream,
              audioStream.segmentBase?.indexByteRange != nil
        else {
            return try await makeProgressiveManifest(
                mediaURL: audioURL,
                source: source,
                shouldValidateHardwareDecoding: false
            )
        }

        let headers = source.httpHeaders
        do {
            let bridge = try await LocalHLSBridge.makeAudioOnly(
                audioTrack: HLSBridgeTrack(
                    url: audioURL,
                    fallbackURLs: audioStream.fallbackPlayURLs(
                        cdnPreference: source.cdnPreference,
                        selectedURL: audioURL
                    ),
                    stream: audioStream,
                    mediaType: .audio
                ),
                durationHint: source.durationHint,
                headers: headers,
                metricsID: source.metricsID,
                onRemoteFailure: onRemoteFailure
            )
            return BiliHLSPlaybackManifest(
                masterPlaylistURL: bridge.masterPlaylistURL,
                bridge: bridge,
                progressiveLoader: nil,
                headers: headers,
                mediaTimeOffset: bridge.mediaTimeOffset
            )
        } catch {
            PlayerMetricsLog.logger.error(
                "hlsAudioOnlyManifestFailed error=\(error.localizedDescription, privacy: .public)"
            )
            throw BiliHLSManifestBuilderError.manifestGenerationFailed(error.localizedDescription)
        }
    }

    static func httpHeaders(referer: String, cookieHeader: String? = nil) -> [String: String] {
        var headers = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1",
            "Referer": referer,
            "Origin": "https://www.bilibili.com",
            "Accept": "*/*",
            "Accept-Language": "zh-CN,zh;q=0.9"
        ]
        if let cookieHeader, !cookieHeader.isEmpty {
            headers["Cookie"] = cookieHeader
        }
        return headers
    }

    private static func makeProgressiveManifest(
        mediaURL: URL,
        source: PlayerStreamSource,
        shouldValidateHardwareDecoding: Bool = true
    ) async throws -> BiliHLSPlaybackManifest {
        if shouldValidateHardwareDecoding {
            try validateHardwareDecoding(for: source)
        }
        let headers = source.httpHeaders
        let loader = BiliHeaderResourceLoaderDelegate(originalURL: mediaURL, headers: headers)
        return BiliHLSPlaybackManifest(
            masterPlaylistURL: loader.assetURL,
            bridge: nil,
            progressiveLoader: loader,
            headers: headers,
            mediaTimeOffset: 0
        )
    }

    private static func validateHardwareDecoding(for source: PlayerStreamSource) throws {
        if source.playbackContentMode == .video {
            if let videoStream = source.videoStream {
                guard videoStream.isHardwareDecodingCompatibleVideo else {
                    PlayerMetricsLog.logger.error(
                        "hlsManifestRejected media=video codec=\(videoStream.codecs ?? "-", privacy: .public) codecid=\(videoStream.codecid ?? -1, privacy: .public)"
                    )
                    throw BiliHLSManifestBuilderError.unsupportedCodec
                }
            } else if source.audioURL != nil {
                PlayerMetricsLog.logger.error("hlsManifestRejected media=video codec=missing")
                throw BiliHLSManifestBuilderError.unsupportedCodec
            }
            for rendition in source.alternateVideoRenditions {
                guard rendition.videoStream.isHardwareDecodingCompatibleVideo else {
                    PlayerMetricsLog.logger.error(
                        "hlsManifestRejected media=alternateVideo codec=\(rendition.videoStream.codecs ?? "-", privacy: .public) codecid=\(rendition.videoStream.codecid ?? -1, privacy: .public)"
                    )
                    throw BiliHLSManifestBuilderError.unsupportedCodec
                }
            }
        }

        if let audioStream = source.audioStream {
            guard audioStream.isHardwareDecodingCompatibleAudio else {
                PlayerMetricsLog.logger.error(
                    "hlsManifestRejected media=audio codec=\(audioStream.codecs ?? "-", privacy: .public) codecid=\(audioStream.codecid ?? -1, privacy: .public)"
                )
                throw BiliHLSManifestBuilderError.unsupportedCodec
            }
        } else if source.audioURL != nil {
            PlayerMetricsLog.logger.error("hlsManifestRejected media=audio codec=missing")
            throw BiliHLSManifestBuilderError.missingAudioURL
        }
    }
}

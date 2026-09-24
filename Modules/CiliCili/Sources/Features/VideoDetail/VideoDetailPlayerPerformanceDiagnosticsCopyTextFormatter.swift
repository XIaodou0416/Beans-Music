import Foundation

@MainActor
enum PlayerPerformanceOverlayDiagnosticsCopyTextFormatter {
    static func text(
        metricsID: String,
        session: PlayerPerformanceSession?,
        diagnosticsStore: VideoDetailNetworkDiagnosticsRenderStore,
        playerViewModel: PlayerStateViewModel?,
        experimentSnapshot: VideoDetailPerformanceExperimentSnapshot = VideoDetailPerformanceExperimentSnapshot()
    ) -> String {
        var sections = [
            liveDiagnosticsText(
                metricsID: metricsID,
                diagnosticsStore: diagnosticsStore,
                playerViewModel: playerViewModel
            )
        ]

        sections.append(experimentText(experimentSnapshot))

        sections.append(contentsOf: [
            PlayerPerformanceCopyTextFormatter.performanceCopyText(
                metricsID: metricsID,
                session: session
            )
        ])

        if let session, !session.timeline.isEmpty {
            sections.append(timelineText(session.timeline))
        }

        return sections
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
    }

    private static func experimentText(_ snapshot: VideoDetailPerformanceExperimentSnapshot) -> String {
        [
            "视频详情页刷新优化",
            "enabled: true",
            "contentShell: narrowObservation",
            "playerSurface: \(snapshot.directUIKitSurfaceEnabled ? "directUIKit" : "swiftUIBridge")",
            "playerOverlayObservation: \(snapshot.narrowPlayerOverlayObservationEnabled ? "narrow" : "legacy")",
            "playerOverlayLifecycle: \(snapshot.narrowPlayerOverlayObservationEnabled ? "stableOverlay" : "identityRebuild")",
            "playerReplacementStrategy: \(snapshot.narrowPlayerOverlayObservationEnabled ? "inPlaceRebind" : "legacyRebuild")",
            "playbackClockObservation: leafControls",
            "rotationStrategy: videoSurfaceFirst",
            "bareSurfaceTransition: \(snapshot.isBareSurfaceTransitionActive ? "true" : "false")",
            "rotationTransitionCount: \(snapshot.rotationTransitionCount)",
            "lastBareSurfaceDuration: \(formattedMilliseconds(snapshot.lastBareSurfaceDurationMilliseconds))",
            "totalBareSurfaceDuration: \(formattedMilliseconds(snapshot.totalBareSurfaceDurationMilliseconds))",
            "overlayPublishCount: \(snapshot.overlayPublishCount)",
            "playerStatePublishCount: \(snapshot.playerStatePublishCount)",
            "settingsStatePublishCount: \(snapshot.settingsStatePublishCount)",
            "playerRebindCount: \(snapshot.playerRebindCount)",
            "overlayDeferredCount: \(snapshot.overlayDeferredCount)",
            "overlayFlushCount: \(snapshot.overlayFlushCount)",
            "lastEvent: \(snapshot.lastEvent)"
        ].joined(separator: "\n")
    }

    private static func formattedMilliseconds(_ milliseconds: Int) -> String {
        guard milliseconds > 0 else { return "-" }
        if milliseconds >= 1_000 {
            return String(format: "%.2fs", Double(milliseconds) / 1_000)
        }
        return "\(milliseconds)ms"
    }

    private static func liveDiagnosticsText(
        metricsID: String,
        diagnosticsStore: VideoDetailNetworkDiagnosticsRenderStore,
        playerViewModel: PlayerStateViewModel?
    ) -> String {
        let selectedStream = selectedStreamText(
            diagnosticsStore.selectedPlayVariant,
            playbackContentMode: playerViewModel?.playbackContentMode ?? .video,
            requestedAudioStream: playerViewModel?.requestedAudioStream
        )
        var lines = [
            "播放现场诊断",
            "generated: \(copyDateFormatter.string(from: Date()))",
            "metricsID: \(metricsID)",
            "video: \(diagnosticsStore.videoTitle.isEmpty ? "-" : diagnosticsStore.videoTitle)",
            "selectedQuality: \(selectedQualityText(diagnosticsStore.selectedPlayVariant))",
            "selectedStream: \(selectedStream)",
            "playURLSource: \(PlaybackNetworkDiagnosticFormat.playURLSourceTitle(diagnosticsStore.lastPlayURLSource))",
            "playURLElapsed: \(PlaybackNetworkDiagnosticFormat.formattedMilliseconds(diagnosticsStore.playURLElapsedMilliseconds))",
            "detailElapsed: \(PlaybackNetworkDiagnosticFormat.formattedMilliseconds(diagnosticsStore.detailLoadElapsedMilliseconds))"
        ]

        appendOptional("fallback", diagnosticsStore.playbackFallbackMessage, to: &lines)

        guard let playerViewModel else {
            lines.append("player: unavailable")
            return lines.joined(separator: "\n")
        }

        let diagnostics = playerViewModel.engineDiagnostics
        lines.append("playbackContentMode: \(diagnostics.playbackContentMode.diagnosticTitle)")
        lines.append("playerState: \(PlaybackNetworkPlayerDiagnosticSnapshot.playerStateTitle(playerViewModel))")
        lines.append("playbackPhase: \(playerViewModel.playbackPhase.diagnosticTitle)")
        lines.append("engine: \(diagnostics.engineName)")
        lines.append("decodePath: \(diagnostics.decodePath.title)")
        lines.append("playbackPipeline: \(diagnostics.playbackPipeline.title)")
        lines.append("engineCompact: \(diagnostics.compactDescription)")
        lines.append("sourceDynamicRange: \(diagnostics.sourceDynamicRangeTitle)")
        lines.append("actualDynamicRange: \(diagnostics.renderedDynamicRangeTitle)")
        lines.append("actualCodec: \(diagnostics.codec ?? "-")")
        appendOptional("actualVideoCodecs", codecIdentifierText(diagnostics.videoCodecIdentifier, codecid: diagnostics.videoCodecid), to: &lines)
        appendOptional("actualAudioCodecs", codecIdentifierText(diagnostics.audioCodecIdentifier, codecid: diagnostics.audioCodecid), to: &lines)
        lines.append("actualResolution: \(diagnostics.resolution ?? "-")")
        lines.append("actualFrameRate: \(diagnostics.frameRate ?? "-")")
        lines.append("actualBandwidth: \(diagnostics.bandwidth.map(String.init) ?? "-")")
        lines.append("usesLocalHLSBridge: \(diagnostics.usesLocalHLSBridge ? "true" : "false")")
        appendOptional("localPlaylist", diagnostics.localPlaylistURL, to: &lines)
        lines.append("sourceHosts: \(redactedSourceHosts(videoHost: diagnostics.sourceVideoHost, audioHost: diagnostics.sourceAudioHost))")
        lines.append("cellularBiliTrafficCompatibility: \(diagnostics.cellularBiliTrafficCompatibility.diagnosticSummary)")
        lines.append("sourceHostClasses: \(CellularBiliTrafficCompatibilityExperiment.sourceHostSummary(videoHost: diagnostics.sourceVideoHost, audioHost: diagnostics.sourceAudioHost))")
        if diagnostics.cellularBiliTrafficCompatibility.isActive {
            lines.append("externalMediaRoute: \(CellularBiliTrafficCompatibilityExperiment.hasExternalMediaHost(videoHost: diagnostics.sourceVideoHost, audioHost: diagnostics.sourceAudioHost) ? "active" : "none")")
        }
        lines.append("hlsVariants: \(PlaybackNetworkDiagnosticFormat.hlsVariantText(diagnostics))")
        if !diagnostics.hlsVideoVariantDetails.isEmpty {
            lines.append("hlsVariantDetails: \(diagnostics.hlsVideoVariantDetails.joined(separator: " | "))")
        }
        appendOptional("nativeHDRVideoLayer", diagnostics.nativeHDRVideoLayerSummary, to: &lines)
        lines.append("hardwareDecodeRequested: \(diagnostics.hardwareDecodeRequested ? "true" : "false")")
        lines.append("hardwareDecodeCompatible: \(PlaybackNetworkPlayerDiagnosticSnapshot.hardwareCompatibilityTitle(diagnostics.isHardwareDecodeCompatible))")
        lines.append("asyncDecompression: \(diagnostics.asynchronousDecompressionEnabled ? "true" : "false")")
        lines.append("prepareElapsed: \(PlaybackNetworkDiagnosticFormat.formattedMilliseconds(playerViewModel.prepareElapsedMilliseconds))")
        lines.append("firstFrameElapsed: \(PlaybackNetworkDiagnosticFormat.formattedMilliseconds(playerViewModel.firstFrameElapsedMilliseconds))")
        lines.append("bufferingCount: \(playerViewModel.bufferingCount)")
        lines.append("lastBufferingElapsed: \(PlaybackNetworkDiagnosticFormat.formattedMilliseconds(playerViewModel.lastBufferingElapsedMilliseconds))")
        appendOptional("playerError", playerViewModel.errorMessage, to: &lines)

        if let reason = playerViewModel.lastFailureReason {
            lines.append("failureLayer: \(reason.layer.rawValue)")
            lines.append("failureCategory: \(reason.category.rawValue)")
            lines.append("failureUserMessage: \(reason.playbackMessage)")
            lines.append("failureHTTPStatus: \(reason.statusCode.map(String.init) ?? "-")")
            lines.append("failureHost: \(redactedHost(reason.urlHost))")
            lines.append("failureRange: \(reason.rangeDescription ?? "-")")
            lines.append("failureUnderlying: \(reason.underlyingDescription ?? "-")")
            lines.append("failureActionHint: \(failureActionHint(for: reason))")
            lines.append("failureRecovery: sameSource=\(reason.allowsSameSourceRecovery) rebuild=\(reason.isRecoverableByRebuild)")
        }

        return lines.joined(separator: "\n")
    }

    private static func timelineText(_ timeline: [PlayerPerformanceTimelineEntry]) -> String {
        var lines = ["最近播放时间线"]
        lines.append(contentsOf: timeline.suffix(16).map { "  \($0.compactDescription)" })
        return lines.joined(separator: "\n")
    }

    static func redactedHost(_ host: String?) -> String {
        guard let host,
              !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return "-" }
        let components = host
            .lowercased()
            .split(separator: ".")
            .map(String.init)
        if components.allSatisfy({ Int($0) != nil }) {
            return "<redacted-ip>"
        }
        guard components.count >= 2 else { return "<redacted>" }
        return "*." + components.suffix(2).joined(separator: ".")
    }

    static func redactedSourceHosts(videoHost: String?, audioHost: String?) -> String {
        let video = redactedHost(videoHost)
        let audio = redactedHost(audioHost)
        guard audio != "-", audio != video else { return "video=\(video)" }
        return "video=\(video) audio=\(audio)"
    }

    static func failureActionHint(for reason: HLSBridgeFailureReason) -> String {
        switch reason.category {
        case .authDenied:
            return "鉴权被拒绝，优先检查 Cookie/登录态并重新获取 playurl。"
        case .urlExpired:
            return "播放地址过期，优先重新拉取 playurl 并重建本地 HLS。"
        case .rangeUnsupported:
            return "CDN Range 响应异常，优先切 backupUrl 或刷新 CDN。"
        case .rateLimited:
            return "CDN 限流，优先刷新 CDN 或稍后重试。"
        case .serverUnavailable, .timeout, .network, .invalidResponse:
            return "网络/CDN/proxy 层异常，优先查看 Range、backupUrl 和弱网状态。"
        case .codecUnsupported, .hardwareDecodeRejected, .decoderFailed:
            return "解码或格式不兼容，优先切同清晰度 H.264/SDR。"
        case .terminalStall:
            return "AVPlayer 卡在终态缓冲，优先重建 item 或切换备用流。"
        case .cancelled:
            return "播放请求已取消，通常由切页、返回或新播放请求触发。"
        case .unknown:
            return "未知失败，优先结合 timeline、accessLog 和 proxy 日志定位。"
        }
    }

    private static func selectedQualityText(_ variant: PlayVariant?) -> String {
        guard let variant else { return "-" }
        return "q\(variant.quality) \(variant.title)"
    }

    private static func selectedStreamText(
        _ variant: PlayVariant?,
        playbackContentMode: PlayerPlaybackContentMode,
        requestedAudioStream: DASHStream?
    ) -> String {
        guard let variant else { return "-" }
        if playbackContentMode == .audioOnly {
            let audioStream = requestedAudioStream ?? variant.audioStream
            var parts = ["仅音频"]
            if let codec = PlaybackNetworkDiagnosticFormat.nilIfEmpty(audioStream?.codecLabel) {
                parts.append(codec)
            }
            if let bandwidth = audioStream?.bandwidth, bandwidth > 0 {
                parts.append(String(format: "%.2f Mbps", Double(bandwidth) / 1_000_000))
            }
            if let audioCodecs = audioStream?.codecs, !audioCodecs.isEmpty {
                parts.append("audioCodecs=\(audioCodecs)")
            }
            return parts.joined(separator: " · ")
        }
        var parts = [
            dynamicRangeTitle(variant.dynamicRange),
            PlaybackNetworkDiagnosticFormat.nilIfEmpty(variant.codec) ?? "codec未知",
            PlaybackNetworkDiagnosticFormat.nilIfEmpty(variant.resolution) ?? "分辨率未知",
            PlaybackNetworkDiagnosticFormat.frameRateTitle(for: variant),
            PlaybackNetworkDiagnosticFormat.bandwidthTitle(for: variant)
        ]
        if let videoCodecs = variant.videoStream?.codecs, !videoCodecs.isEmpty {
            parts.append("videoCodecs=\(videoCodecs)")
        }
        if let audioCodecs = variant.audioStream?.codecs, !audioCodecs.isEmpty {
            parts.append("audioCodecs=\(audioCodecs)")
        }
        return parts.joined(separator: " · ")
    }

    private static func appendOptional(_ title: String, _ value: String?, to lines: inout [String]) {
        guard let value = PlaybackNetworkDiagnosticFormat.nilIfEmpty(value) else { return }
        lines.append("\(title): \(value)")
    }

    private static func codecIdentifierText(_ codec: String?, codecid: Int?) -> String? {
        let codecText = PlaybackNetworkDiagnosticFormat.nilIfEmpty(codec)
        let codecidText = codecid.map { "codecid=\($0)" }
        return [codecText, codecidText]
            .compactMap { $0 }
            .joined(separator: " ")
            .nilIfEmpty
    }

    private static func dynamicRangeTitle(_ dynamicRange: BiliVideoDynamicRange) -> String {
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

    private static var copyDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }
}

import SwiftUI

private struct PlayerPerformanceOverlayDiagnosticRow: Identifiable, Equatable {
    let id: String
    let title: String
    let value: String
    let style: Style

    enum Style: Equatable {
        case normal
        case warning
        case failure
        case secondary
    }
}

struct PlayerPerformanceOverlayLiveDiagnosticsSection: View {
    @ObservedObject var diagnosticsStore: VideoDetailNetworkDiagnosticsRenderStore
    let playerViewModel: PlayerStateViewModel?

    var body: some View {
        Group {
            if let playerViewModel {
                PlayerPerformanceOverlayObservedLiveDiagnosticsSection(
                    diagnosticsStore: diagnosticsStore,
                    playerViewModel: playerViewModel
                )
            } else {
                PlayerPerformanceOverlayStaticLiveDiagnosticsSection(
                    diagnosticsStore: diagnosticsStore
                )
            }
        }
    }
}

private struct PlayerPerformanceOverlayObservedLiveDiagnosticsSection: View {
    @ObservedObject var diagnosticsStore: VideoDetailNetworkDiagnosticsRenderStore
    @ObservedObject var playerViewModel: PlayerStateViewModel

    var body: some View {
        PlayerPerformanceOverlayLiveDiagnosticsRows(
            rows: PlayerPerformanceOverlayLiveDiagnosticsRowBuilder.rows(
                diagnosticsStore: diagnosticsStore,
                playerViewModel: playerViewModel
            ),
            isFailure: playerViewModel.errorMessage?.isEmpty == false || playerViewModel.lastFailureReason != nil
        )
    }
}

private struct PlayerPerformanceOverlayStaticLiveDiagnosticsSection: View {
    @ObservedObject var diagnosticsStore: VideoDetailNetworkDiagnosticsRenderStore

    var body: some View {
        PlayerPerformanceOverlayLiveDiagnosticsRows(
            rows: PlayerPerformanceOverlayLiveDiagnosticsRowBuilder.rows(
                diagnosticsStore: diagnosticsStore,
                playerViewModel: nil
            ),
            isFailure: diagnosticsStore.playbackFallbackMessage?.isEmpty == false
        )
    }
}

private struct PlayerPerformanceOverlayLiveDiagnosticsRows: View {
    let rows: [PlayerPerformanceOverlayDiagnosticRow]
    let isFailure: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: isFailure ? "exclamationmark.triangle.fill" : "stethoscope")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isFailure ? .orange : .secondary)
                Text("现场诊断")
                    .font(.caption2.weight(.semibold))
                Spacer(minLength: 0)
            }

            ForEach(rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(row.title)
                        .foregroundStyle(.secondary)
                        .frame(width: 58, alignment: .leading)
                    Text(row.value)
                        .foregroundStyle(color(for: row.style))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption2.monospacedDigit())
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            PlayerPerformanceOverlayFormatting.sectionBackground,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isFailure ? Color.orange.opacity(0.35) : Color(uiColor: .separator).opacity(0.55), lineWidth: 0.7)
        }
    }

    private func color(for style: PlayerPerformanceOverlayDiagnosticRow.Style) -> Color {
        switch style {
        case .normal:
            return .primary
        case .warning:
            return .orange
        case .failure:
            return .red
        case .secondary:
            return .secondary
        }
    }
}

@MainActor
private enum PlayerPerformanceOverlayLiveDiagnosticsRowBuilder {
    static func rows(
        diagnosticsStore: VideoDetailNetworkDiagnosticsRenderStore,
        playerViewModel: PlayerStateViewModel?
    ) -> [PlayerPerformanceOverlayDiagnosticRow] {
        var rows = [PlayerPerformanceOverlayDiagnosticRow]()
        let variant = diagnosticsStore.selectedPlayVariant

        append(&rows, id: "video", title: "视频", value: nonEmpty(diagnosticsStore.videoTitle))
        append(&rows, id: "quality", title: "清晰度", value: variant.map(variantTitle) ?? "未选择")
        append(
            &rows,
            id: "request",
            title: "请求流",
            value: requestedStreamTitle(
                for: variant,
                playbackContentMode: playerViewModel?.playbackContentMode ?? .video,
                requestedAudioStream: playerViewModel?.requestedAudioStream
            )
        )
        append(&rows, id: "playurl", title: "取流", value: playURLTitle(for: diagnosticsStore), style: .secondary)

        guard let playerViewModel else {
            appendOptional(&rows, id: "fallback", title: "降级", value: diagnosticsStore.playbackFallbackMessage, style: .warning)
            return rows
        }

        let diagnostics = playerViewModel.engineDiagnostics
        append(&rows, id: "content-mode", title: "模式", value: diagnostics.playbackContentMode.diagnosticTitle)
        append(&rows, id: "state", title: "状态", value: PlaybackNetworkPlayerDiagnosticSnapshot.playerStateTitle(playerViewModel))
        append(&rows, id: "phase", title: "阶段", value: playerViewModel.playbackPhase.diagnosticTitle, style: phaseStyle(playerViewModel.playbackPhase))
        append(&rows, id: "engine", title: "引擎", value: diagnostics.engineName)
        append(&rows, id: "decode", title: "解码", value: diagnostics.decodePath.title)
        append(&rows, id: "pipeline", title: "链路", value: diagnostics.playbackPipeline.title, style: .secondary)
        append(&rows, id: "actual", title: "实际流", value: actualStreamTitle(for: diagnostics))
        if diagnostics.renderedDynamicRangeTitle != diagnostics.sourceDynamicRangeTitle {
            append(
                &rows,
                id: "source-range",
                title: "源动态范围",
                value: diagnostics.sourceDynamicRangeTitle,
                style: .secondary
            )
        }
        append(&rows, id: "codecs", title: "编码", value: codecIdentifierTitle(for: diagnostics), style: .secondary)
        if let localPlaylistURL = diagnostics.localPlaylistURL {
            append(&rows, id: "local-hls", title: "本地HLS", value: localPlaylistURL, style: .secondary)
        }
        append(
            &rows,
            id: "source-hosts",
            title: "源Host",
            value: PlayerPerformanceOverlayDiagnosticsCopyTextFormatter.redactedSourceHosts(
                videoHost: diagnostics.sourceVideoHost,
                audioHost: diagnostics.sourceAudioHost
            ),
            style: .secondary
        )
        append(&rows, id: "hardware", title: "硬解", value: hardwareTitle(for: diagnostics), style: hardwareStyle(for: diagnostics))
        if diagnostics.hlsVideoVariantCount > 0 {
            append(&rows, id: "hls", title: "HLS", value: PlaybackNetworkDiagnosticFormat.hlsVariantText(diagnostics), style: .secondary)
        }
        if !diagnostics.hlsVideoVariantDetails.isEmpty {
            append(
                &rows,
                id: "hls-details",
                title: "HLS编码",
                value: diagnostics.hlsVideoVariantDetails.joined(separator: " | "),
                style: .secondary
            )
        }
        appendOptional(
            &rows,
            id: "native-hdr-layer",
            title: "原生层",
            value: diagnostics.nativeHDRVideoLayerSummary,
            style: diagnostics.nativeHDRVideoLayerState == "failed" ? .warning : .secondary
        )
        appendOptional(&rows, id: "error", title: "错误", value: playerViewModel.errorMessage, style: .failure)
        appendOptional(&rows, id: "fallback", title: "降级", value: diagnosticsStore.playbackFallbackMessage, style: .warning)
        if let reason = playerViewModel.lastFailureReason {
            append(&rows, id: "reason", title: "失败层", value: "\(reason.layer.rawValue) / \(reason.category.rawValue)", style: .failure)
            append(&rows, id: "message", title: "说明", value: reason.playbackMessage, style: .warning)
            appendOptional(&rows, id: "status", title: "HTTP", value: reason.statusCode.map(String.init), style: .warning)
            appendOptional(
                &rows,
                id: "host",
                title: "Host",
                value: PlayerPerformanceOverlayDiagnosticsCopyTextFormatter.redactedHost(reason.urlHost),
                style: .secondary
            )
            appendOptional(&rows, id: "range", title: "Range", value: reason.rangeDescription, style: .secondary)
            appendOptional(&rows, id: "underlying", title: "底层", value: reason.underlyingDescription, style: .warning)
            append(
                &rows,
                id: "action-hint",
                title: "判断",
                value: PlayerPerformanceOverlayDiagnosticsCopyTextFormatter.failureActionHint(for: reason),
                style: .warning
            )
        }
        return rows
    }

    private static func append(
        _ rows: inout [PlayerPerformanceOverlayDiagnosticRow],
        id: String,
        title: String,
        value: String,
        style: PlayerPerformanceOverlayDiagnosticRow.Style = .normal
    ) {
        rows.append(PlayerPerformanceOverlayDiagnosticRow(id: id, title: title, value: value, style: style))
    }

    private static func appendOptional(
        _ rows: inout [PlayerPerformanceOverlayDiagnosticRow],
        id: String,
        title: String,
        value: String?,
        style: PlayerPerformanceOverlayDiagnosticRow.Style = .normal
    ) {
        guard let value = PlaybackNetworkDiagnosticFormat.nilIfEmpty(value) else { return }
        append(&rows, id: id, title: title, value: value, style: style)
    }

    private static func nonEmpty(_ value: String) -> String {
        PlaybackNetworkDiagnosticFormat.nilIfEmpty(value) ?? "-"
    }

    private static func variantTitle(_ variant: PlayVariant) -> String {
        var parts = ["q\(variant.quality)", variant.title]
        if let badge = variant.qualityBadge, !parts.contains(badge) {
            parts.append(badge)
        }
        return parts.joined(separator: " · ")
    }

    private static func requestedStreamTitle(
        for variant: PlayVariant?,
        playbackContentMode: PlayerPlaybackContentMode,
        requestedAudioStream: DASHStream?
    ) -> String {
        guard let variant else { return "未获取" }
        if playbackContentMode == .audioOnly {
            let audioStream = requestedAudioStream ?? variant.audioStream
            var parts = ["仅音频"]
            if let codec = PlaybackNetworkDiagnosticFormat.nilIfEmpty(audioStream?.codecLabel) {
                parts.append(codec)
            }
            if let bandwidth = audioStream?.bandwidth, bandwidth > 0 {
                parts.append(String(format: "%.2f Mbps", Double(bandwidth) / 1_000_000))
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
            parts.append(videoCodecs)
        }
        return parts.joined(separator: " · ")
    }

    private static func playURLTitle(for diagnosticsStore: VideoDetailNetworkDiagnosticsRenderStore) -> String {
        return [
            PlaybackNetworkDiagnosticFormat.playURLSourceTitle(diagnosticsStore.lastPlayURLSource),
            PlaybackNetworkDiagnosticFormat.formattedMilliseconds(diagnosticsStore.playURLElapsedMilliseconds)
        ].joined(separator: " · ")
    }

    private static func actualStreamTitle(for diagnostics: PlayerEngineDiagnostics) -> String {
        if diagnostics.playbackContentMode == .audioOnly {
            var parts = [PlaybackNetworkDiagnosticFormat.nilIfEmpty(diagnostics.codec) ?? "codec未知"]
            if let bandwidth = diagnostics.bandwidth, bandwidth > 0 {
                parts.append(String(format: "%.2f Mbps", Double(bandwidth) / 1_000_000))
            }
            return parts.joined(separator: " · ")
        }
        return [
            diagnostics.renderedDynamicRangeTitle,
            PlaybackNetworkDiagnosticFormat.nilIfEmpty(diagnostics.codec) ?? "codec未知",
            PlaybackNetworkDiagnosticFormat.nilIfEmpty(diagnostics.resolution) ?? "分辨率未知",
            PlaybackNetworkDiagnosticFormat.nilIfEmpty(diagnostics.frameRate).map { "\($0)fps" } ?? "帧率未知",
            diagnostics.bandwidth.map { PlaybackNetworkDiagnosticFormat.bandwidthTitle(for: PlayVariant(
                quality: 0,
                title: "",
                videoURL: nil,
                audioURL: nil,
                videoStream: nil,
                audioStream: nil,
                codec: nil,
                resolution: nil,
                frameRate: nil,
                bandwidth: $0,
                isHDR: diagnostics.dynamicRange.isHDR,
                badge: nil
            )) } ?? "带宽未知"
        ].joined(separator: " · ")
    }

    private static func codecIdentifierTitle(for diagnostics: PlayerEngineDiagnostics) -> String {
        if diagnostics.playbackContentMode == .audioOnly {
            return codecIdentifierText(
                diagnostics.audioCodecIdentifier,
                codecid: diagnostics.audioCodecid
            ) ?? "A 未知"
        }
        let video = codecIdentifierText(diagnostics.videoCodecIdentifier, codecid: diagnostics.videoCodecid)
            ?? "未知"
        guard let audio = codecIdentifierText(diagnostics.audioCodecIdentifier, codecid: diagnostics.audioCodecid) else {
            return "V \(video)"
        }
        return "V \(video) · A \(audio)"
    }

    private static func codecIdentifierText(_ codec: String?, codecid: Int?) -> String? {
        let codecText = PlaybackNetworkDiagnosticFormat.nilIfEmpty(codec)
        let codecidText = codecid.map { "codecid=\($0)" }
        return [codecText, codecidText]
            .compactMap { $0 }
            .joined(separator: " ")
            .nilIfEmpty
    }

    private static func hardwareTitle(for diagnostics: PlayerEngineDiagnostics) -> String {
        let requested = diagnostics.hardwareDecodeRequested ? "请求硬解" : "未请求硬解"
        let compatible = PlaybackNetworkPlayerDiagnosticSnapshot.hardwareCompatibilityTitle(
            diagnostics.isHardwareDecodeCompatible
        )
        let async = diagnostics.asynchronousDecompressionEnabled ? "AsyncVT" : "同步"
        return "\(requested) · 兼容 \(compatible) · \(async)"
    }

    private static func hardwareStyle(for diagnostics: PlayerEngineDiagnostics) -> PlayerPerformanceOverlayDiagnosticRow.Style {
        diagnostics.isHardwareDecodeCompatible == false ? .failure : .secondary
    }

    private static func phaseStyle(_ phase: PlayerPlaybackPhase) -> PlayerPerformanceOverlayDiagnosticRow.Style {
        switch phase {
        case .failed:
            return .failure
        case .buffering, .preparing, .recovering, .waitingForFirstFrame:
            return .warning
        default:
            return .normal
        }
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
}

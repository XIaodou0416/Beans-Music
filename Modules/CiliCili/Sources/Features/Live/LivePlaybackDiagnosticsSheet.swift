import Foundation
import SwiftUI
import UIKit

@MainActor
struct LivePlaybackDiagnosticsSheet: View {
    @ObservedObject var viewModel: LiveRoomViewModel
    @ObservedObject private var performanceStore = PlayerPerformanceStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var didCopyDiagnostics = false

    private var metricsID: String {
        "live-\(viewModel.roomID)"
    }

    private var performanceSession: PlayerPerformanceSession? {
        performanceStore.session(for: metricsID)
    }

    private var currentCandidate: LiveStreamURLCandidate? {
        guard viewModel.streamCandidates.indices.contains(viewModel.currentCandidateIndex) else {
            return nil
        }
        return viewModel.streamCandidates[viewModel.currentCandidateIndex]
    }

    var body: some View {
        NavigationStack {
            Form {
                if didCopyDiagnostics {
                    Section {
                        Label("诊断信息已复制", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                Section("当前直播") {
                    diagnosticRow("直播间", value: viewModel.title)
                    diagnosticRow("房间号", value: String(viewModel.roomID), monospaced: true)
                    diagnosticRow("加载状态", value: viewModel.state.liveDiagnosticsTitle)
                    diagnosticRow("当前线路", value: viewModel.currentStreamTitle ?? "未确定")
                    diagnosticRow("候选线路", value: candidatePosition, monospaced: true)
                    diagnosticRow("慢启动换线", value: viewModel.slowStartupRouteSwitchStatus)

                    if let currentCandidate {
                        diagnosticRow("节点", value: currentCandidate.url.host ?? "未确定", monospaced: true)
                        diagnosticRow("协议", value: currentCandidate.protocolName ?? "未确定", monospaced: true)
                        diagnosticRow("封装", value: currentCandidate.formatName ?? "未确定", monospaced: true)
                        diagnosticRow("编码", value: currentCandidate.codecName ?? "未确定", monospaced: true)
                    }

                    if let streamFallbackMessage = viewModel.streamFallbackMessage {
                        diagnosticRow("切换提示", value: streamFallbackMessage)
                    }
                }

                Section("候选线路") {
                    if viewModel.streamCandidates.isEmpty {
                        ContentUnavailableView(
                            "等待线路信息",
                            systemImage: "point.3.connected.trianglepath.dotted",
                            description: Text("取流完成后会显示官方返回的候选节点。")
                        )
                    } else {
                        ForEach(Array(viewModel.streamCandidates.enumerated()), id: \.offset) { entry in
                            LivePlaybackDiagnosticsRow(
                                "线路 \(entry.offset + 1)\(entry.offset == viewModel.currentCandidateIndex ? "（当前）" : "")",
                                value: liveCandidateDiagnosticsSummary(entry.element),
                                monospaced: true
                            )
                        }
                    }
                }

                Section("播放器") {
                    if let playerViewModel = viewModel.playerViewModel {
                        LivePlaybackDiagnosticsPlayerRows(playerViewModel: playerViewModel)
                    } else {
                        ContentUnavailableView(
                            "等待播放器",
                            systemImage: "play.rectangle",
                            description: Text("直播流尚未创建或已停止。")
                        )
                    }
                }

                Section("性能记录") {
                    LivePlaybackDiagnosticsPerformanceRows(session: performanceSession)
                }

                Section("旋转") {
                    LivePlaybackDiagnosticsRotationRows(
                        state: viewModel.liveRotationSurfaceAlignmentState
                    )
                }

                Section("直播优化") {
                    diagnosticRow("并行启动", value: "固定开启")
                    diagnosticRow("CDN 自适应", value: "固定开启")
                    diagnosticRow("慢启动换线", value: "固定开启")
                    diagnosticRow("HLS 快启动", value: "固定开启")
                    diagnosticRow("弹幕合批", value: "固定开启")
                    diagnosticRow("旋转画面稳定", value: "固定开启")
                }

                Section("弹幕") {
                    LivePlaybackDiagnosticsDanmakuRows(store: viewModel.liveDanmakuRenderStore)
                }
            }
            .navigationTitle("直播播放诊断")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        copyDiagnostics()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .accessibilityLabel("复制直播播放诊断")
                }
            }
        }
    }

    private var candidatePosition: String {
        guard currentCandidate != nil else { return "未确定" }
        return "\(viewModel.currentCandidateIndex + 1) / \(viewModel.streamCandidates.count)"
    }

    private func diagnosticRow(
        _ title: String,
        value: String,
        monospaced: Bool = false
    ) -> some View {
        LabeledContent(title) {
            Text(value)
                .font(monospaced ? .body.monospaced() : .body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(3)
        }
    }

    private func enabledText(_ isEnabled: Bool) -> String {
        isEnabled ? "已开启" : "已关闭"
    }

    private func copyDiagnostics() {
        UIPasteboard.general.string = LivePlaybackDiagnosticsTextBuilder(
            viewModel: viewModel,
            performanceSession: performanceSession
        ).text
        didCopyDiagnostics = true
    }
}

private struct LivePlaybackDiagnosticsPlayerRows: View {
    @ObservedObject var playerViewModel: PlayerStateViewModel

    var body: some View {
        let diagnostics = playerViewModel.engineDiagnostics
        LivePlaybackDiagnosticsRow("阶段", value: playerViewModel.playbackPhase.diagnosticTitle)
        LivePlaybackDiagnosticsRow(
            "首帧",
            value: PlayerPerformanceCopyTextFormatter.millisecondsText(
                playerViewModel.firstFrameElapsedMilliseconds
            ),
            monospaced: true
        )
        LivePlaybackDiagnosticsRow(
            "Prepare",
            value: PlayerPerformanceCopyTextFormatter.millisecondsText(
                playerViewModel.prepareElapsedMilliseconds
            ),
            monospaced: true
        )
        LivePlaybackDiagnosticsRow("缓冲", value: "\(playerViewModel.bufferingCount) 次", monospaced: true)
        LivePlaybackDiagnosticsRow(
            "最近缓冲",
            value: PlayerPerformanceCopyTextFormatter.millisecondsText(
                playerViewModel.lastBufferingElapsedMilliseconds
            ),
            monospaced: true
        )
        LivePlaybackDiagnosticsRow("播放器", value: diagnostics.engineName)
        LivePlaybackDiagnosticsRow("播放链路", value: diagnostics.playbackPipeline.title)
        LivePlaybackDiagnosticsRow("解码", value: diagnostics.decodePath.title)
        LivePlaybackDiagnosticsRow("规格", value: streamSpecification(for: diagnostics), monospaced: true)
        LivePlaybackDiagnosticsRow(
            "实际画幅",
            value: presentationSizeText(playerViewModel.videoPresentationSize),
            monospaced: true
        )
        LivePlaybackDiagnosticsRow(
            "视频节点",
            value: diagnostics.sourceVideoHost ?? "未确定",
            monospaced: true
        )
        LivePlaybackDiagnosticsRow(
            "音频节点",
            value: diagnostics.sourceAudioHost ?? "未确定",
            monospaced: true
        )

        if let errorMessage = playerViewModel.errorMessage {
            LivePlaybackDiagnosticsRow("错误", value: errorMessage)
        }
    }

    private func streamSpecification(for diagnostics: PlayerEngineDiagnostics) -> String {
        var values = [String]()
        if let codec = diagnostics.codec, !codec.isEmpty {
            values.append(codec)
        }
        if let resolution = diagnostics.resolution, !resolution.isEmpty {
            values.append(resolution)
        }
        if let frameRate = diagnostics.frameRate, !frameRate.isEmpty {
            values.append("\(frameRate) fps")
        }
        values.append(diagnostics.dynamicRange.rawValue.uppercased())
        return values.joined(separator: " · ")
    }

    private func presentationSizeText(_ size: CGSize) -> String {
        guard size.width > 0, size.height > 0 else { return "-" }
        return "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
    }
}

private struct LivePlaybackDiagnosticsPerformanceRows: View {
    let session: PlayerPerformanceSession?

    var body: some View {
        if let session {
            LivePlaybackDiagnosticsRow(
                "总首帧",
                value: PlayerPerformanceCopyTextFormatter.millisecondsText(
                    session.firstFrameTotalMilliseconds
                ),
                monospaced: true
            )
            LivePlaybackDiagnosticsRow(
                "播放器首帧",
                value: PlayerPerformanceCopyTextFormatter.millisecondsText(
                    session.firstFramePlayerMilliseconds
                ),
                monospaced: true
            )
            LivePlaybackDiagnosticsRow(
                "取流",
                value: PlayerPerformanceCopyTextFormatter.millisecondsText(session.playURLMilliseconds),
                monospaced: true
            )
            LivePlaybackDiagnosticsRow(
                "准备",
                value: PlayerPerformanceCopyTextFormatter.millisecondsText(session.prepareMilliseconds),
                monospaced: true
            )
            LivePlaybackDiagnosticsRow("缓冲", value: "\(session.bufferCount) 次", monospaced: true)

            if let accessLogMessage = session.accessLogMessage {
                LivePlaybackDiagnosticsRow("AccessLog", value: accessLogMessage, monospaced: true)
            }
            if let networkMessage = session.networkMessage {
                LivePlaybackDiagnosticsRow("播放反馈", value: networkMessage, monospaced: true)
            }
            if let failureMessage = session.failureMessage {
                LivePlaybackDiagnosticsRow("失败", value: failureMessage)
            }
        } else {
            ContentUnavailableView(
                "等待性能事件",
                systemImage: "chart.xyaxis.line",
                description: Text("开始加载直播后会自动写入首帧和缓冲数据。")
            )
        }
    }
}

private struct LivePlaybackDiagnosticsDanmakuRows: View {
    @ObservedObject var store: LiveDanmakuRenderStore

    var body: some View {
        LivePlaybackDiagnosticsRow("开关", value: store.isEnabled ? "已开启" : "已关闭")
        LivePlaybackDiagnosticsRow("连接", value: store.connectionPhase.title)
        LivePlaybackDiagnosticsRow("聊天消息", value: "\(store.chatItems.count) 条", monospaced: true)
        LivePlaybackDiagnosticsRow("屏幕弹幕", value: "\(store.items.count) 条", monospaced: true)
        LivePlaybackDiagnosticsRow("历史", value: historyStatus)

        if let connectionError = store.connectionError {
            LivePlaybackDiagnosticsRow("连接错误", value: connectionError)
        }
        if let historyError = store.historyError {
            LivePlaybackDiagnosticsRow("历史错误", value: historyError)
        }
    }

    private var historyStatus: String {
        if store.isLoadingHistory {
            return "加载中"
        }
        if store.historyError != nil {
            return "失败"
        }
        return "已完成"
    }
}

private struct LivePlaybackDiagnosticsRotationRows: View {
    @ObservedObject var state: LiveRotationSurfaceAlignmentState

    var body: some View {
        let snapshot = state.snapshot
        LivePlaybackDiagnosticsRow("旋转保护", value: "固定开启")
        LivePlaybackDiagnosticsRow(
            "状态",
            value: snapshot.isBareSurfaceTransitionActive ? "旋转中，叠层暂存" : "运行中"
        )
        LivePlaybackDiagnosticsRow("真实画幅", value: snapshot.presentationSizeText, monospaced: true)
        LivePlaybackDiagnosticsRow("画幅比", value: aspectRatioText(snapshot.videoAspectRatio), monospaced: true)
        LivePlaybackDiagnosticsRow("旋转次数", value: "\(snapshot.rotationTransitionCount)", monospaced: true)
        LivePlaybackDiagnosticsRow(
            "最近暂存",
            value: PlayerPerformanceCopyTextFormatter.millisecondsText(
                snapshot.lastBareSurfaceDurationMilliseconds > 0
                    ? snapshot.lastBareSurfaceDurationMilliseconds
                    : nil
            ),
            monospaced: true
        )
        LivePlaybackDiagnosticsRow("屏幕弹幕暂存", value: "\(snapshot.overlayDeferredCount)", monospaced: true)
        LivePlaybackDiagnosticsRow("屏幕弹幕合并", value: "\(snapshot.overlayFlushCount)", monospaced: true)
        LivePlaybackDiagnosticsRow("聊天暂存", value: "\(snapshot.chatDeferredCount)", monospaced: true)
        LivePlaybackDiagnosticsRow("聊天合并", value: "\(snapshot.chatFlushCount)", monospaced: true)
        LivePlaybackDiagnosticsRow("最近事件", value: snapshot.lastEvent)
    }

    private func aspectRatioText(_ value: CGFloat?) -> String {
        guard let value else { return "-" }
        return String(format: "%.3f", Double(value))
    }
}

private struct LivePlaybackDiagnosticsRow: View {
    let title: String
    let value: String
    var monospaced = false

    init(_ title: String, value: String, monospaced: Bool = false) {
        self.title = title
        self.value = value
        self.monospaced = monospaced
    }

    var body: some View {
        LabeledContent(title) {
            Text(value)
                .font(monospaced ? .body.monospaced() : .body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(4)
        }
    }
}

@MainActor
struct LivePlaybackDiagnosticsTextBuilder {
    let viewModel: LiveRoomViewModel
    let performanceSession: PlayerPerformanceSession?

    var text: String {
        let metricsID = "live-\(viewModel.roomID)"
        let candidate = currentCandidate
        let playerViewModel = viewModel.playerViewModel
        let danmakuStore = viewModel.liveDanmakuRenderStore
        var lines = [
            "CiliCili 直播播放诊断",
            "generated: \(Self.dateFormatter.string(from: Date()))",
            "metricsID: \(metricsID)",
            "roomID: \(viewModel.roomID)",
            "title: \(sanitized(viewModel.title))",
            "loadState: \(viewModel.state.liveDiagnosticsTitle)",
            "currentStream: \(viewModel.currentStreamTitle ?? "-")",
            "candidate: \(candidatePosition)",
            "sourceHost: \(candidate?.url.host ?? "-")",
            "protocol: \(candidate?.protocolName ?? "-")",
            "format: \(candidate?.formatName ?? "-")",
            "codec: \(candidate?.codecName ?? "-")",
            "quality: \(candidate?.currentQN.map(String.init) ?? "-")",
            "slowStartupRouteSwitch: \(sanitized(viewModel.slowStartupRouteSwitchStatus))"
        ]

        lines.append("candidates:")
        if viewModel.streamCandidates.isEmpty {
            lines.append("  -")
        } else {
            for (index, candidate) in viewModel.streamCandidates.enumerated() {
                let selected = index == viewModel.currentCandidateIndex ? " selected" : ""
                lines.append("  \(index + 1): \(liveCandidateDiagnosticsSummary(candidate))\(selected)")
            }
        }

        if let playerViewModel {
            let diagnostics = playerViewModel.engineDiagnostics
            lines.append("playerState: \(playerViewModel.playbackPhase.diagnosticTitle)")
            lines.append("playerFirstFrame: \(PlayerPerformanceCopyTextFormatter.millisecondsText(playerViewModel.firstFrameElapsedMilliseconds))")
            lines.append("prepare: \(PlayerPerformanceCopyTextFormatter.millisecondsText(playerViewModel.prepareElapsedMilliseconds))")
            lines.append("bufferingCount: \(playerViewModel.bufferingCount)")
            lines.append("lastBuffering: \(PlayerPerformanceCopyTextFormatter.millisecondsText(playerViewModel.lastBufferingElapsedMilliseconds))")
            lines.append("engine: \(diagnostics.engineName)")
            lines.append("decodePath: \(diagnostics.decodePath.title)")
            lines.append("playbackPipeline: \(diagnostics.playbackPipeline.title)")
            lines.append("engineCompact: \(diagnostics.compactDescription)")
            lines.append("sourceDynamicRange: \(diagnostics.dynamicRange.rawValue)")
            lines.append("actualCodec: \(diagnostics.codec ?? "-")")
            lines.append("actualVideoCodecs: \(diagnostics.videoCodecIdentifier ?? "-")")
            lines.append("actualAudioCodecs: \(diagnostics.audioCodecIdentifier ?? "-")")
            lines.append("actualResolution: \(diagnostics.resolution ?? "-")")
            lines.append("actualFrameRate: \(diagnostics.frameRate ?? "-")")
            lines.append("actualBandwidth: \(diagnostics.bandwidth.map(String.init) ?? "-")")
            lines.append("actualPresentationSize: \(presentationSizeText(playerViewModel.videoPresentationSize))")
            lines.append("usesLocalHLSBridge: \(diagnostics.usesLocalHLSBridge ? "true" : "false")")
            lines.append("sourceHosts: video=\(diagnostics.sourceVideoHost ?? "-") audio=\(diagnostics.sourceAudioHost ?? "-")")
        }

        lines.append("直播优化:")
        lines.append("  parallelStartup: fixed")
        lines.append("  adaptiveCDN: fixed")
        lines.append("  slowStartupRouteSwitch: fixed")
        lines.append("  hlsFastStart: fixed")
        lines.append("  danmakuBatching: fixed")
        lines.append("  rotationSurfaceAlignment: fixed")

        let rotationSnapshot = viewModel.liveRotationSurfaceAlignmentState.snapshot
        lines.append("直播旋转:")
        lines.append("  active: \(enabledText(rotationSnapshot.isBareSurfaceTransitionActive))")
        lines.append("  transitions: \(rotationSnapshot.rotationTransitionCount)")
        lines.append("  presentationSize: \(rotationSnapshot.presentationSizeText)")
        lines.append("  aspectRatio: \(rotationSnapshot.videoAspectRatio.map { String(format: "%.3f", Double($0)) } ?? "-")")
        lines.append("  overlayDeferred/flush: \(rotationSnapshot.overlayDeferredCount)/\(rotationSnapshot.overlayFlushCount)")
        lines.append("  chatDeferred/flush: \(rotationSnapshot.chatDeferredCount)/\(rotationSnapshot.chatFlushCount)")
        lines.append("  lastBareSurface: \(PlayerPerformanceCopyTextFormatter.millisecondsText(rotationSnapshot.lastBareSurfaceDurationMilliseconds > 0 ? rotationSnapshot.lastBareSurfaceDurationMilliseconds : nil))")

        lines.append("直播弹幕:")
        lines.append("  enabled: \(enabledText(danmakuStore.isEnabled))")
        lines.append("  connection: \(danmakuStore.connectionPhase.title)")
        lines.append("  chatItems: \(danmakuStore.chatItems.count)")
        lines.append("  overlayItems: \(danmakuStore.items.count)")
        lines.append("  history: \(historyStatus(for: danmakuStore))")
        if let connectionError = danmakuStore.connectionError {
            lines.append("  connectionError: \(sanitized(connectionError))")
        }
        if let historyError = danmakuStore.historyError {
            lines.append("  historyError: \(sanitized(historyError))")
        }
        if let streamFallbackMessage = viewModel.streamFallbackMessage {
            lines.append("streamFallback: \(sanitized(streamFallbackMessage))")
        }

        lines.append("")
        lines.append(
            PlayerPerformanceCopyTextFormatter.performanceCopyText(
                metricsID: metricsID,
                session: performanceSession
            )
        )
        lines.append("")
        lines.append("隐私: 不包含播放 URL、签名参数、Cookie 或账号信息。")
        return lines.joined(separator: "\n")
    }

    private var currentCandidate: LiveStreamURLCandidate? {
        guard viewModel.streamCandidates.indices.contains(viewModel.currentCandidateIndex) else {
            return nil
        }
        return viewModel.streamCandidates[viewModel.currentCandidateIndex]
    }

    private var candidatePosition: String {
        guard currentCandidate != nil else { return "-" }
        return "\(viewModel.currentCandidateIndex + 1)/\(viewModel.streamCandidates.count)"
    }

    private func enabledText(_ isEnabled: Bool) -> String {
        isEnabled ? "on" : "off"
    }

    private func presentationSizeText(_ size: CGSize) -> String {
        guard size.width > 0, size.height > 0 else { return "-" }
        return "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
    }

    private func historyStatus(for store: LiveDanmakuRenderStore) -> String {
        if store.isLoadingHistory {
            return "loading"
        }
        return store.historyError == nil ? "ready" : "failed"
    }

    private func sanitized(_ value: String) -> String {
        value.replacingOccurrences(of: "\n", with: " ")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

@MainActor
private func liveCandidateDiagnosticsSummary(_ candidate: LiveStreamURLCandidate) -> String {
    var values = [String]()
    values.append("host=\(candidate.url.host ?? "-")")
    values.append("protocol=\(candidate.protocolName ?? "-")")
    values.append("format=\(candidate.formatName ?? "-")")
    values.append("codec=\(candidate.codecName ?? "-")")
    values.append(
        "health=\(LiveStreamStartupHealthMemory.shared.snapshot(for: candidate)?.diagnosticsTitle ?? "暂无记录")"
    )
    return values.joined(separator: " · ")
}

private extension LoadingState {
    var liveDiagnosticsTitle: String {
        switch self {
        case .idle:
            return "空闲"
        case .loading:
            return "加载中"
        case .loaded:
            return "已加载"
        case .failed(let message):
            return "失败：\(message)"
        }
    }
}

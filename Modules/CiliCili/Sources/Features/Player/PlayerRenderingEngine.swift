import AVFoundation
import AVKit
import Combine
import Foundation
import OSLog
import SwiftUI
import UIKit

struct PlayerVideoRenditionSource: Equatable, Sendable {
    let quality: Int
    let title: String
    let videoURL: URL
    let videoStream: DASHStream
    let dynamicRange: BiliVideoDynamicRange
}

enum PlayerPlaybackContentMode: String, Equatable, Sendable {
    case video
    case audioOnly

    var diagnosticTitle: String {
        switch self {
        case .video:
            return "视频"
        case .audioOnly:
            return "听视频"
        }
    }
}

struct PlayerStreamSource: Equatable, Sendable {
    let metricsID: String
    let videoURL: URL?
    let audioURL: URL?
    let videoStream: DASHStream?
    let audioStream: DASHStream?
    let alternateVideoRenditions: [PlayerVideoRenditionSource]
    let referer: String
    let httpHeaders: [String: String]
    let title: String
    let durationHint: TimeInterval?
    let isLiveStream: Bool
    let isLiveHLS: Bool
    let liveHLSFormat: String?
    let resumeTime: TimeInterval
    let dynamicRange: BiliVideoDynamicRange
    let cdnPreference: PlaybackCDNPreference
    var playbackContentMode: PlayerPlaybackContentMode = .video

    func withResumeTime(_ resumeTime: TimeInterval) -> PlayerStreamSource {
        PlayerStreamSource(
            metricsID: metricsID,
            videoURL: videoURL,
            audioURL: audioURL,
            videoStream: videoStream,
            audioStream: audioStream,
            alternateVideoRenditions: alternateVideoRenditions,
            referer: referer,
            httpHeaders: httpHeaders,
            title: title,
            durationHint: durationHint,
            isLiveStream: isLiveStream,
            isLiveHLS: isLiveHLS,
            liveHLSFormat: liveHLSFormat,
            resumeTime: max(resumeTime, 0),
            dynamicRange: dynamicRange,
            cdnPreference: cdnPreference,
            playbackContentMode: playbackContentMode
        )
    }
}

struct PlayerBufferedRange: Equatable, Sendable {
    let start: TimeInterval
    let end: TimeInterval

    var duration: TimeInterval {
        max(end - start, 0)
    }

    func intersectionDuration(from lowerBound: TimeInterval, to upperBound: TimeInterval) -> TimeInterval {
        let intersectionStart = max(start, lowerBound)
        let intersectionEnd = min(end, upperBound)
        return max(intersectionEnd - intersectionStart, 0)
    }
}

struct PlayerPlaybackSnapshot: Equatable, Sendable {
    let currentTime: TimeInterval?
    let renderedVideoTime: TimeInterval?
    let requiresRenderedVideoTimeForRecovery: Bool
    let duration: TimeInterval?
    let isPlaying: Bool
    let isSeekable: Bool
    let bufferedRanges: [PlayerBufferedRange]

    init(
        currentTime: TimeInterval?,
        renderedVideoTime: TimeInterval? = nil,
        requiresRenderedVideoTimeForRecovery: Bool = false,
        duration: TimeInterval?,
        isPlaying: Bool,
        isSeekable: Bool,
        bufferedRanges: [PlayerBufferedRange]
    ) {
        self.currentTime = currentTime
        self.renderedVideoTime = renderedVideoTime
        self.requiresRenderedVideoTimeForRecovery = requiresRenderedVideoTimeForRecovery
        self.duration = duration
        self.isPlaying = isPlaying
        self.isSeekable = isSeekable
        self.bufferedRanges = bufferedRanges
    }

    func bufferedCoverageProgress(
        around targetTime: TimeInterval,
        preroll: TimeInterval = 0.45,
        forward: TimeInterval = 2.2
    ) -> Double {
        guard targetTime.isFinite, targetTime >= 0 else { return 0 }
        let lowerBound = max(targetTime - max(preroll, 0), 0)
        let upperBound = max(targetTime + max(forward, 0), lowerBound + 0.1)
        let neededDuration = max(upperBound - lowerBound, 0.1)
        let coveredDuration = bufferedRanges.reduce(0) { partial, range in
            partial + range.intersectionDuration(from: lowerBound, to: upperBound)
        }
        return min(max(coveredDuration / neededDuration, 0), 1)
    }
}

struct PlayerEngineDiagnostics: Equatable, Sendable {
    enum PlaybackPipeline: String, Sendable {
        case unknown
        case dashLocalHLS
        case liveHLSProxy
        case directAVURLAsset

        var title: String {
            switch self {
            case .unknown:
                return "未知"
            case .dashLocalHLS:
                return "DASH/fMP4 -> 本地 HLS -> AVPlayer"
            case .liveHLSProxy:
                return "远端 HLS -> 本地代理 -> AVPlayer"
            case .directAVURLAsset:
                return "直连 AVURLAsset -> AVPlayer"
            }
        }
    }

    enum DecodePath: String, Sendable {
        case unknown
        case avPlayer

        var title: String {
            switch self {
            case .unknown:
                return "未知"
            case .avPlayer:
                return "AVPlayer / 系统解码"
            }
        }
    }

    var engineName: String
    var playbackContentMode: PlayerPlaybackContentMode = .video
    var decodePath: DecodePath
    var playbackPipeline: PlaybackPipeline
    var codec: String?
    var videoCodecIdentifier: String?
    var audioCodecIdentifier: String?
    var videoCodecid: Int?
    var audioCodecid: Int?
    var resolution: String?
    var frameRate: String?
    var bandwidth: Int?
    var dynamicRange: BiliVideoDynamicRange
    var isDASH: Bool
    var usesLocalHLSBridge: Bool
    var localPlaylistURL: String?
    var sourceVideoHost: String?
    var sourceAudioHost: String?
    var cellularBiliTrafficCompatibility: CellularBiliTrafficCompatibilityExperiment.RuntimeState = .inactive
    var hlsVideoVariantCount: Int
    var hlsVideoVariantQualities: [Int]
    var hlsVideoVariantDetails: [String]
    var preferredForwardBufferDuration: TimeInterval?
    var maxBufferDuration: TimeInterval?
    var asynchronousDecompressionEnabled: Bool
    var hardwareDecodeRequested: Bool
    var isHardwareDecodeCompatible: Bool?
    var environmentSummary: String?
    var nativeHDRVideoLayerState: String? = nil
    var nativeHDRVideoLayerSummary: String? = nil

    static let empty = PlayerEngineDiagnostics(
        engineName: "未创建",
        decodePath: .unknown,
        playbackPipeline: .unknown,
        codec: nil,
        videoCodecIdentifier: nil,
        audioCodecIdentifier: nil,
        videoCodecid: nil,
        audioCodecid: nil,
        resolution: nil,
        frameRate: nil,
        bandwidth: nil,
        dynamicRange: .sdr,
        isDASH: false,
        usesLocalHLSBridge: false,
        localPlaylistURL: nil,
        sourceVideoHost: nil,
        sourceAudioHost: nil,
        cellularBiliTrafficCompatibility: .inactive,
        hlsVideoVariantCount: 0,
        hlsVideoVariantQualities: [],
        hlsVideoVariantDetails: [],
        preferredForwardBufferDuration: nil,
        maxBufferDuration: nil,
        asynchronousDecompressionEnabled: false,
        hardwareDecodeRequested: false,
        isHardwareDecodeCompatible: nil,
        environmentSummary: nil
    )

    var compactDescription: String {
        var parts = [engineName, decodePath.title, playbackPipeline.title]
        if playbackContentMode == .audioOnly {
            parts.append(playbackContentMode.diagnosticTitle)
        }
        if let codec, !codec.isEmpty {
            parts.append(codec)
        }
        if let resolution, !resolution.isEmpty {
            parts.append(resolution)
        }
        if let frameRate, !frameRate.isEmpty {
            parts.append(frameRate)
        }
        if asynchronousDecompressionEnabled {
            parts.append("AsyncVT")
        }
        if hardwareDecodeRequested {
            parts.append("硬解")
        }
        if let isHardwareDecodeCompatible {
            parts.append(isHardwareDecodeCompatible ? "硬解兼容" : "硬解不兼容")
        }
        if usesLocalHLSBridge {
            parts.append("HLSBridge")
        }
        if hlsVideoVariantCount > 1 {
            parts.append("\(hlsVideoVariantCount)档")
        }
        if !hlsVideoVariantQualities.isEmpty {
            let qualities =
                hlsVideoVariantQualities
                .map { "q\($0)" }
                .joined(separator: "/")
            parts.append(qualities)
        }
        if !hlsVideoVariantDetails.isEmpty {
            parts.append(hlsVideoVariantDetails.joined(separator: "/"))
        }
        if let nativeHDRVideoLayerSummary, !nativeHDRVideoLayerSummary.isEmpty {
            parts.append("NativeHDR \(nativeHDRVideoLayerSummary)")
        }
        return parts.joined(separator: " · ")
    }

    var sourceDynamicRangeTitle: String {
        Self.dynamicRangeTitle(dynamicRange)
    }

    var renderedDynamicRangeTitle: String {
        if dynamicRange == .dolbyVision,
            nativeHDRVideoLayerState == "ready"
        {
            return "Dolby Vision (原生视频层)"
        }
        guard usesLocalHLSBridge,
            let hlsRange = hlsRenderedDynamicRangeTitle
        else { return sourceDynamicRangeTitle }
        if dynamicRange == .dolbyVision, hlsRange != sourceDynamicRangeTitle {
            if hlsRange.contains("Dolby Vision") {
                return hlsRange
            }
            return "\(hlsRange) (Dolby Vision 基层)"
        }
        return hlsRange
    }

    private var hlsRenderedDynamicRangeTitle: String? {
        let details = hlsVideoVariantDetails.joined(separator: " ")
        let lowercasedDetails = details.lowercased()
        if lowercasedDetails.contains("dvpolicy=protectedhlg") {
            return "HLG (Dolby Vision 元数据关闭)"
        }
        if lowercasedDetails.contains("dvpolicy=compatiblehlg") {
            return "HLG"
        }
        if lowercasedDetails.contains("dvpolicy=applenativep8hls")
            || lowercasedDetails.contains("dvpath=applenativep8hls")
        {
            return "Dolby Vision (Apple 原生 P8)"
        }
        if lowercasedDetails.contains("dvpolicy=fulleffect") {
            return "Dolby Vision (原生主轨)"
        }
        if lowercasedDetails.contains("dvpolicy=supplementalhls") {
            return "Dolby Vision (HLS supplemental)"
        }
        if lowercasedDetails.contains("supp=dvh1")
            || lowercasedDetails.contains("supp=dvhe")
            || lowercasedDetails.contains("supplemental-codecs=\"dvh1")
            || lowercasedDetails.contains("supplemental-codecs=\"dvhe")
        {
            return "Dolby Vision"
        }
        if details.contains("HLG") || details.contains("color=18") {
            return "HLG"
        }
        if details.contains("PQ") || details.contains("color=16") {
            return dynamicRange == .dolbyVision ? "Dolby Vision" : "HDR10"
        }
        return nil
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

enum PlayerEnginePlaybackState: Equatable, Sendable {
    case idle
    case preparing
    case ready
    case buffering
    case playing
    case paused
    case ended
    case failed(String?)
}

enum PlayerPlaybackPhase: Equatable, Sendable {
    case idle
    case preparing
    case ready
    case waitingForFirstFrame
    case buffering
    case seeking
    case playing
    case paused
    case recovering
    case ended
    case failed(String?)

    var diagnosticTitle: String {
        switch self {
        case .idle:
            return "空闲"
        case .preparing:
            return "准备中"
        case .ready:
            return "已就绪"
        case .waitingForFirstFrame:
            return "等待首帧"
        case .buffering:
            return "缓冲中"
        case .seeking:
            return "跳转中"
        case .playing:
            return "播放中"
        case .paused:
            return "已暂停"
        case .recovering:
            return "恢复中"
        case .ended:
            return "已结束"
        case .failed:
            return "失败"
        }
    }
}

enum PlayerEngineError: LocalizedError {
    case missingVideoURL
    case missingAudioURL
    case unsupportedMedia

    var errorDescription: String? {
        switch self {
        case .missingVideoURL:
            return "没有可播放的视频地址"
        case .missingAudioURL:
            return "没有可播放的音频地址"
        case .unsupportedMedia:
            return "当前视频流暂不支持播放"
        }
    }
}

struct PlayerQualityControls {
    let title: String
    let items: [PlayerQualityControlItem]

    var isEmpty: Bool {
        items.isEmpty
    }
}

struct PlayerQualityControlItem: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let isSelected: Bool
    let isDisabled: Bool
    let action: @MainActor () -> Void
}

@MainActor
protocol PlayerRenderingEngine: AnyObject, Sendable {
    var hasMedia: Bool { get }
    var needsMediaRecovery: Bool { get }
    var playbackErrorMessage: String? { get }
    var lastFailureReason: HLSBridgeFailureReason? { get }
    var supportsPictureInPicture: Bool { get }
    var isPictureInPictureActive: Bool { get }
    var usesNativePlaybackControls: Bool { get }
    var diagnostics: PlayerEngineDiagnostics { get }
    var presentationSize: CGSize { get }
    var volume: Float { get }
    var isMuted: Bool { get }
    var onPlaybackStateChange: (@MainActor (PlayerEnginePlaybackState) -> Void)? { get set }
    var onPlaybackIntentChange: (@MainActor (Bool) -> Void)? { get set }
    var onLoadingProgressChange: (@MainActor (Double) -> Void)? { get set }
    var onFirstFrame: (@MainActor (TimeInterval) -> Void)? { get set }
#if DEBUG
    var debugPlayerIdentity: ObjectIdentifier? { get }
    var debugPlayerItemIdentity: ObjectIdentifier? { get }
#endif

    func attachSurface(_ surface: UIView)
    func detachSurface(_ surface: UIView)
    func refreshSurfaceLayout()
    func recoverSurface()
    @discardableResult
    func refreshVideoOutputForPlaybackRecovery() -> Bool
    @discardableResult
    func rebuildPlayerItemForPlaybackRecovery(at time: TimeInterval) -> TimeInterval?
    @discardableResult
    func warmPausedPlaybackForRecovery() -> Bool
    func setViewModel(_ viewModel: PlayerStateViewModel?)
    func setVideoGravity(_ gravity: AVLayerVideoGravity)
    func setContentOverlay(_ overlay: AnyView?)
    func setDanmakuControls(isEnabled: Bool, onToggle: (() -> Void)?, onShowSettings: (() -> Void)?)
    func setQualityControls(_ controls: PlayerQualityControls?)
    func attachNativePlaybackController(_ controller: AVPlayerViewController)
    func detachNativePlaybackController(_ controller: AVPlayerViewController)
    func prepare(source: PlayerStreamSource) async throws
    func play()
    func pause()
    func pauseForUserScrub()
    func pauseForAppBackground()
    func pauseForNavigation()
    func suspendForNavigation()
    func stop()
    func setPlaybackRate(_ rate: Double)
    func setPreferredPeakBitRate(_ bitRate: Double?)
    func setVolume(_ volume: Float)
    func setMuted(_ isMuted: Bool)
    func setTemporaryAudioSuppressed(_ isSuppressed: Bool)
    func setPictureInPictureEnabled(_ isEnabled: Bool)
    func seek(toTime time: TimeInterval) -> TimeInterval?
    func seekToLiveEdge() -> TimeInterval?
    func seek(toProgress progress: Double, duration: TimeInterval?) -> TimeInterval?
    func seek(by interval: TimeInterval, from currentTime: TimeInterval, duration: TimeInterval?) -> TimeInterval?
    func seekAfterUserScrub(toProgress progress: Double, duration: TimeInterval?) async -> TimeInterval?
    func snapshot(durationHint: TimeInterval?) -> PlayerPlaybackSnapshot
    func currentRenderedVideoTime() -> TimeInterval?
    func currentVideoFrameImage() -> UIImage?
    func currentSurfaceSnapshotImage() -> UIImage?
    func pictureInPictureContentSource() -> AVPictureInPictureController.ContentSource?
    func togglePictureInPicture()
    func stopPictureInPictureIfNeeded()
    func invalidatePictureInPicturePlaybackState()
}

extension PlayerRenderingEngine {
#if DEBUG
    var debugPlayerIdentity: ObjectIdentifier? { nil }

    var debugPlayerItemIdentity: ObjectIdentifier? { nil }
#endif

    func pauseForUserScrub() {
        pause()
    }

    func pauseForAppBackground() {
        pause()
    }

    @discardableResult
    func refreshVideoOutputForPlaybackRecovery() -> Bool {
        recoverSurface()
        return false
    }

    @discardableResult
    func rebuildPlayerItemForPlaybackRecovery(at _: TimeInterval) -> TimeInterval? {
        nil
    }

    @discardableResult
    func warmPausedPlaybackForRecovery() -> Bool {
        false
    }

    var presentationSize: CGSize { .zero }

    func setPictureInPictureEnabled(_: Bool) {}

    func stopPictureInPictureIfNeeded() {
        guard isPictureInPictureActive else { return }
        togglePictureInPicture()
    }

    func suspendForNavigation() {
        pauseForNavigation()
        setTemporaryAudioSuppressed(true)
    }

    func setTemporaryAudioSuppressed(_ isSuppressed: Bool) {
        if isSuppressed {
            setMuted(true)
            setVolume(0)
        }
    }

    func currentVideoFrameImage() -> UIImage? {
        nil
    }

    func currentRenderedVideoTime() -> TimeInterval? {
        nil
    }

    func currentSurfaceSnapshotImage() -> UIImage? {
        nil
    }

    func setContentOverlay(_: AnyView?) {}

    func setDanmakuControls(isEnabled _: Bool, onToggle _: (() -> Void)?, onShowSettings _: (() -> Void)?) {}

    func setQualityControls(_: PlayerQualityControls?) {}
}

extension UIImage {
    var biliLooksLikeBlackFrame: Bool {
        guard let cgImage else { return false }
        let width = 8
        let height = 8
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard
            let context = CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )
        else {
            return false
        }

        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var brightPixelCount = 0
        var lumaSum = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let red = Int(pixels[index])
            let green = Int(pixels[index + 1])
            let blue = Int(pixels[index + 2])
            let luma = (red * 299 + green * 587 + blue * 114) / 1000
            lumaSum += luma
            if luma > 18 {
                brightPixelCount += 1
            }
        }

        let averageLuma = Double(lumaSum) / Double(width * height)
        return averageLuma < 10 && brightPixelCount <= 1
    }
}

@MainActor
extension UIView {
    func biliRenderedSnapshotImage() -> UIImage? {
        layoutIfNeeded()
        guard bounds.width > 1, bounds.height > 1 else { return nil }
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = window?.screen.scale ?? traitCollection.displayScale
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)
        return renderer.image { context in
            UIColor.black.setFill()
            context.fill(bounds)
            if !drawHierarchy(in: bounds, afterScreenUpdates: false) {
                layer.render(in: context.cgContext)
            }
        }
    }
}

@MainActor
enum DefaultPlayerRenderingEngine {
    static func make() -> PlayerRenderingEngine {
        AVPlayerHLSBridgeEngine()
    }
}

enum PlayerMetricsLog {
    nonisolated static let logger = Logger(subsystem: "cc.bili", category: "PlayerMetrics")
    nonisolated static let signposter = OSSignposter(logger: logger)
    private static let diagnosticsFileName = "player-diagnostics.log"

    nonisolated static func beginSignpostedInterval(
        _ name: StaticString,
        message: String? = nil
    ) -> OSSignpostIntervalState {
        _ = message
        return signposter.beginInterval(name)
    }

    nonisolated static func endSignpostedInterval(
        _ name: StaticString,
        _ state: OSSignpostIntervalState,
        message: String? = nil
    ) {
        _ = message
        signposter.endInterval(name, state)
    }

    nonisolated static func signpostEvent(
        _ name: StaticString,
        message: String? = nil
    ) {
        _ = message
        signposter.emitEvent(name)
    }

    nonisolated static func withSignpostedInterval<T>(
        _ name: StaticString,
        message: String? = nil,
        _ operation: () throws -> T
    ) rethrows -> T {
        _ = message
        let state = beginSignpostedInterval(name, message: message)
        defer { endSignpostedInterval(name, state) }
        return try operation()
    }

    nonisolated static func withSignpostedInterval<T>(
        _ name: StaticString,
        message: String? = nil,
        _ operation: () async throws -> T
    ) async rethrows -> T {
        _ = message
        let state = beginSignpostedInterval(name, message: message)
        defer { endSignpostedInterval(name, state) }
        return try await operation()
    }

    @MainActor
    static func record(
        _ event: PlayerPerformanceEvent.Kind, metricsID: String, title: String? = nil, message: String? = nil
    ) {
        PlayerPerformanceStore.shared.record(event, metricsID: metricsID, title: title, message: message)
        diagnostic(
            [
                "event=\(event.title)",
                "metricsID=\(metricsID)",
                title.map { "title=\(shortTitle($0))" },
                message.map { "message=\($0)" },
            ].compactMap { $0 }.joined(separator: " ")
        )
    }

    nonisolated static func diagnostic(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(timestamp) \(message)"
        Task.detached(priority: .utility) {
            await PlayerDiagnosticsFileWriter.shared.enqueue(line)
        }
    }

    nonisolated static func elapsedMilliseconds(since start: CFTimeInterval) -> Double {
        (CACurrentMediaTime() - start) * 1000
    }

    nonisolated static func shortTitle(_ title: String) -> String {
        let trimmed = title.replacingOccurrences(of: "\n", with: " ")
        if trimmed.count <= 36 {
            return trimmed
        }
        return "\(trimmed.prefix(36))..."
    }
}

private actor PlayerDiagnosticsFileWriter {
    static let shared = PlayerDiagnosticsFileWriter()

    private let fileName = "player-diagnostics.log"
    private let flushDelayNanoseconds: UInt64 = 400_000_000
    private let maximumPendingLineCount = 32
    private var pendingLines: [String] = []
    private var flushTask: Task<Void, Never>?

    func enqueue(_ line: String) {
        pendingLines.append(line)
        if pendingLines.count >= maximumPendingLineCount {
            flushTask?.cancel()
            flushTask = nil
            flush()
            return
        }

        guard flushTask == nil else { return }
        let flushDelayNanoseconds = flushDelayNanoseconds
        flushTask = Task.detached(priority: .utility) { [weak self] in
            try? await Task.sleep(nanoseconds: flushDelayNanoseconds)
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    private func flush() {
        flushTask = nil
        guard !pendingLines.isEmpty,
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        else { return }

        let lines = pendingLines
        pendingLines.removeAll(keepingCapacity: true)
        let payload = lines.joined(separator: "\n") + "\n"
        guard let data = payload.data(using: .utf8) else { return }

        let consolePayload =
            lines
            .map { "[PlayerDiagnostics] \($0)" }
            .joined(separator: "\n") + "\n"
        print(consolePayload, terminator: "")
        let url = directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            try? data.write(to: url, options: .atomic)
            return
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { handle.closeFile() }
        handle.seekToEndOfFile()
        handle.write(data)
    }
}

struct PlayerPerformanceEvent: Identifiable, Equatable {
    enum Kind: Equatable {
        case routeOpen
        case detailLoadStart
        case detailLoaded
        case playURLStart
        case playURLLoaded
        case playerCreated
        case prepareRequested
        case mediaPrepared
        case prepareReturned
        case playRequested
        case firstFrame
        case startupBreakdown
        case startupScheduler
        case buffering
        case failed
        case network
        case accessLog
        case decodeLog
        case mediaCache
        case manifestStage
        case qualitySupplement
        case resumeDecision
        case resumeRecovery
        case seek
        case seekRecovery
        case speedBoost
        case playbackRecovery

        var title: String {
            switch self {
            case .manifestStage: return "Manifest"
            case .qualitySupplement: return "Supplement"
            case .resumeDecision: return "续播"
            case .resumeRecovery: return "续播验证"
            case .seek: return "Seek"
            case .seekRecovery: return "Seek 恢复"
            case .speedBoost: return "倍速"
            case .playbackRecovery: return "播放恢复"
            case .routeOpen: return "打开视频"
            case .detailLoadStart: return "详情开始"
            case .detailLoaded: return "详情完成"
            case .playURLStart: return "播放地址开始"
            case .playURLLoaded: return "播放地址完成"
            case .playerCreated: return "播放器创建"
            case .prepareRequested: return "Prepare 开始"
            case .mediaPrepared: return "媒体准备完成"
            case .prepareReturned: return "Prepare 返回"
            case .playRequested: return "播放请求"
            case .firstFrame: return "首帧"
            case .startupBreakdown: return "首帧分段"
            case .startupScheduler: return "首帧调度"
            case .buffering: return "缓冲"
            case .failed: return "失败"
            case .network: return "网络"
            case .accessLog: return "AccessLog"
            case .decodeLog: return "Decode"
            case .mediaCache: return "媒体缓存"
            }
        }
    }

    let id = UUID()
    let date = Date()
    let kind: Kind
    let metricsID: String
    let title: String?
    let message: String?
}

struct PlayerPerformanceTimelineEntry: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let elapsedMilliseconds: Int?
    let title: String
    let message: String?

    var compactDescription: String {
        let elapsed = elapsedMilliseconds.map { "\($0)ms" } ?? "-"
        guard let message, !message.isEmpty else {
            return "\(elapsed) \(title)"
        }
        return "\(elapsed) \(title) · \(message)"
    }
}

struct PlayerPerformanceSampleGroup: Identifiable, Equatable {
    static let minimumReliableSampleCount = 5

    let id: String
    let quality: Int?
    let cdnKey: String
    let cdnTitle: String
    let networkKey: String
    let networkTitle: String
    let startupSourceKey: String
    let startupSourceTitle: String
    let codecKey: String
    let codecTitle: String
    let avPlayerStartupPathOptimizationExperimentEnabled: Bool?
    let playerCreationModeKey: String
    let playerCreationModeTitle: String
    let piliPlusStylePlayURLSelectionExperimentEnabled: Bool?
    let relatedEarlyPlayURLPrefetchExperimentEnabled: Bool?
    let relatedStartupPackageWarmupExperimentEnabled: Bool?
    let playURLSelectionStrategyKey: String
    let playURLSelectionStrategyTitle: String
    let sampleCount: Int
    let lastUpdatedAt: Date
    let averageDetailMilliseconds: Int?
    let averagePlayURLMilliseconds: Int?
    let averagePrepareMilliseconds: Int?
    let averageFirstFrameMilliseconds: Int?
    let p50FirstFrameMilliseconds: Int?
    let p90FirstFrameMilliseconds: Int?
    let averagePlayerFirstFrameMilliseconds: Int?
    let averageSeekRecoveryMilliseconds: Int?
    let averageSeekBufferReadyCoveragePercent: Int?
    let averageObservedBitrateKilobitsPerSecond: Int?
    let slowStartupCount: Int
    let failedCount: Int
    let bufferCount: Int
    let seekCount: Int
    let seekRecoverySlowCount: Int
    let accessLogStallCount: Int
    let speedBoostInterruptionCount: Int

    var qualityTitle: String {
        guard let quality else { return "未知画质" }
        switch quality {
        case 127:
            return "8K"
        case 126:
            return "杜比视界"
        case 125:
            return "HDR"
        case 120:
            return "4K"
        case 116:
            return "1080P 高帧率"
        case 112:
            return "1080P 高码率"
        case 80:
            return "1080P"
        case 74:
            return "720P 高帧率"
        case 64:
            return "720P"
        case 32:
            return "480P"
        case 16:
            return "360P"
        case 6:
            return "240P"
        default:
            return "Q\(quality)"
        }
    }

    var title: String {
        "\(qualityTitle) · \(codecTitle)"
    }

    var subtitle: String {
        let sampleText =
            hasSufficientSamples
            ? "\(sampleCount) 次样本"
            : "\(sampleCount) 次样本（样本偏少）"
        return
            "\(cdnTitle) · \(networkTitle) · \(startupSourceTitle) · \(AVPlayerStartupPathOptimizationExperiment.sampleGroupStateTitle(for: avPlayerStartupPathOptimizationExperimentEnabled)) · \(playerCreationModeTitle) · \(PiliPlusStylePlayURLSelectionExperiment.sampleGroupStateTitle(for: piliPlusStylePlayURLSelectionExperimentEnabled)) · \(RelatedPlaybackEarlyPlayURLPrefetchPolicy.diagnosticStateTitle(for: relatedEarlyPlayURLPrefetchExperimentEnabled)) · \(RelatedPlaybackStartupPackageWarmupPolicy.diagnosticStateTitle(for: relatedStartupPackageWarmupExperimentEnabled)) · \(playURLSelectionStrategyTitle) · \(sampleText)"
    }

    var hasSufficientSamples: Bool {
        sampleCount >= Self.minimumReliableSampleCount
    }

    static func median(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        let sortedValues = values.sorted()
        let middleIndex = sortedValues.count / 2
        guard sortedValues.count.isMultiple(of: 2) else {
            return sortedValues[middleIndex]
        }
        return Int((Double(sortedValues[middleIndex - 1]) + Double(sortedValues[middleIndex])) / 2)
    }

    var issueCount: Int {
        slowStartupCount + failedCount + bufferCount + seekRecoverySlowCount + accessLogStallCount
            + speedBoostInterruptionCount
    }

    var recommendationScore: Int {
        let startup = averageFirstFrameMilliseconds ?? averagePlayerFirstFrameMilliseconds ?? 1_600
        let playURL = averagePlayURLMilliseconds ?? 600
        let prepare = averagePrepareMilliseconds ?? 600
        return startup
            + playURL / 2
            + prepare / 3
            + slowStartupCount * 800
            + failedCount * 1_600
            + bufferCount * 450
            + seekRecoverySlowCount * 700
            + accessLogStallCount * 700
            + speedBoostInterruptionCount * 450
    }
}

private struct PlayerPerformanceSampleGroupAccumulator {
    let id: String
    let quality: Int?
    let cdnKey: String
    let cdnTitle: String
    let networkKey: String
    let networkTitle: String
    let startupSourceKey: String
    let startupSourceTitle: String
    let codecKey: String
    let codecTitle: String
    let avPlayerStartupPathOptimizationExperimentEnabled: Bool?
    let playerCreationModeKey: String
    let playerCreationModeTitle: String
    let piliPlusStylePlayURLSelectionExperimentEnabled: Bool?
    let relatedEarlyPlayURLPrefetchExperimentEnabled: Bool?
    let relatedStartupPackageWarmupExperimentEnabled: Bool?
    let playURLSelectionStrategyKey: String
    let playURLSelectionStrategyTitle: String
    var sampleCount = 0
    var lastUpdatedAt = Date.distantPast
    var detailSum = 0
    var detailCount = 0
    var playURLSum = 0
    var playURLCount = 0
    var prepareSum = 0
    var prepareCount = 0
    var firstFrameSum = 0
    var firstFrameCount = 0
    var firstFrameValues: [Int] = []
    var playerFirstFrameSum = 0
    var playerFirstFrameCount = 0
    var seekRecoverySum = 0
    var seekRecoveryCount = 0
    var seekBufferReadyCoverageSum = 0
    var seekBufferReadyCoverageCount = 0
    var observedBitrateSum = 0
    var observedBitrateCount = 0
    var slowStartupCount = 0
    var failedCount = 0
    var bufferCount = 0
    var seekCount = 0
    var seekRecoverySlowCount = 0
    var accessLogStallCount = 0
    var speedBoostInterruptionCount = 0

    mutating func record(_ session: PlayerPerformanceSession) {
        sampleCount += 1
        lastUpdatedAt = max(lastUpdatedAt, session.lastUpdatedAt)
        append(session.detailLoadMilliseconds, sum: &detailSum, count: &detailCount)
        append(session.playURLMilliseconds, sum: &playURLSum, count: &playURLCount)
        append(session.prepareMilliseconds, sum: &prepareSum, count: &prepareCount)
        append(
            session.firstFrameTotalMilliseconds,
            sum: &firstFrameSum,
            count: &firstFrameCount,
            values: &firstFrameValues
        )
        append(session.firstFramePlayerMilliseconds, sum: &playerFirstFrameSum, count: &playerFirstFrameCount)
        append(session.lastSeekRecoveryMilliseconds, sum: &seekRecoverySum, count: &seekRecoveryCount)
        append(
            session.lastSeekBufferReadyCoveragePercent, sum: &seekBufferReadyCoverageSum,
            count: &seekBufferReadyCoverageCount)
        append(session.observedBitrateKilobitsPerSecond, sum: &observedBitrateSum, count: &observedBitrateCount)
        if session.failureMessage != nil {
            failedCount += 1
        }
        if isSlowStartup(session) {
            slowStartupCount += 1
        }
        bufferCount += session.bufferCount
        seekCount += session.seekCount
        seekRecoverySlowCount += session.seekRecoverySlowCount
        accessLogStallCount += session.accessLogStallCount ?? 0
        speedBoostInterruptionCount += session.speedBoostInterruptionCount
    }

    func makeGroup() -> PlayerPerformanceSampleGroup {
        PlayerPerformanceSampleGroup(
            id: id,
            quality: quality,
            cdnKey: cdnKey,
            cdnTitle: cdnTitle,
            networkKey: networkKey,
            networkTitle: networkTitle,
            startupSourceKey: startupSourceKey,
            startupSourceTitle: startupSourceTitle,
            codecKey: codecKey,
            codecTitle: codecTitle,
            avPlayerStartupPathOptimizationExperimentEnabled: avPlayerStartupPathOptimizationExperimentEnabled,
            playerCreationModeKey: playerCreationModeKey,
            playerCreationModeTitle: playerCreationModeTitle,
            piliPlusStylePlayURLSelectionExperimentEnabled: piliPlusStylePlayURLSelectionExperimentEnabled,
            relatedEarlyPlayURLPrefetchExperimentEnabled: relatedEarlyPlayURLPrefetchExperimentEnabled,
            relatedStartupPackageWarmupExperimentEnabled: relatedStartupPackageWarmupExperimentEnabled,
            playURLSelectionStrategyKey: playURLSelectionStrategyKey,
            playURLSelectionStrategyTitle: playURLSelectionStrategyTitle,
            sampleCount: sampleCount,
            lastUpdatedAt: lastUpdatedAt,
            averageDetailMilliseconds: average(detailSum, detailCount),
            averagePlayURLMilliseconds: average(playURLSum, playURLCount),
            averagePrepareMilliseconds: average(prepareSum, prepareCount),
            averageFirstFrameMilliseconds: average(firstFrameSum, firstFrameCount),
            p50FirstFrameMilliseconds: percentile(0.5, in: firstFrameValues),
            p90FirstFrameMilliseconds: percentile(0.9, in: firstFrameValues),
            averagePlayerFirstFrameMilliseconds: average(playerFirstFrameSum, playerFirstFrameCount),
            averageSeekRecoveryMilliseconds: average(seekRecoverySum, seekRecoveryCount),
            averageSeekBufferReadyCoveragePercent: average(seekBufferReadyCoverageSum, seekBufferReadyCoverageCount),
            averageObservedBitrateKilobitsPerSecond: average(observedBitrateSum, observedBitrateCount),
            slowStartupCount: slowStartupCount,
            failedCount: failedCount,
            bufferCount: bufferCount,
            seekCount: seekCount,
            seekRecoverySlowCount: seekRecoverySlowCount,
            accessLogStallCount: accessLogStallCount,
            speedBoostInterruptionCount: speedBoostInterruptionCount
        )
    }

    private func average(_ sum: Int, _ count: Int) -> Int? {
        guard count > 0 else { return nil }
        return Int((Double(sum) / Double(count)).rounded())
    }

    private func isSlowStartup(_ session: PlayerPerformanceSession) -> Bool {
        session.firstFrameTotalMilliseconds.map { $0 >= 2_000 } == true
            || session.firstFramePlayerMilliseconds.map { $0 >= 1_500 } == true
            || session.playURLMilliseconds.map { $0 >= 1_000 } == true
            || session.prepareMilliseconds.map { $0 >= 1_400 } == true
    }

    private func append(
        _ value: Int?,
        sum: inout Int,
        count: inout Int
    ) {
        guard let value else { return }
        sum += value
        count += 1
    }

    private func append(
        _ value: Int?,
        sum: inout Int,
        count: inout Int,
        values: inout [Int]
    ) {
        guard let value else { return }
        sum += value
        count += 1
        values.append(value)
    }

    private func percentile(_ percentile: Double, in values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        if percentile == 0.5 {
            return PlayerPerformanceSampleGroup.median(values)
        }
        let sortedValues = values.sorted()
        let index = min(
            max(Int((Double(sortedValues.count) * percentile).rounded(.up)) - 1, 0),
            sortedValues.count - 1
        )
        return sortedValues[index]
    }
}

private struct PlayerPerformancePersistedSession: Codable, Equatable, Sendable {
    let id: String
    var title: String?
    var lastUpdatedAt: Date
    var detailLoadMilliseconds: Int?
    var playURLMilliseconds: Int?
    var mediaPreparedMilliseconds: Int?
    var prepareMilliseconds: Int?
    var resumeApplyMilliseconds: Int?
    var resumeRecoveryCount: Int
    var resumeRecoverySlowCount: Int
    var lastResumeRecoveryMilliseconds: Int?
    var firstFrameTotalMilliseconds: Int?
    var firstFramePlayerMilliseconds: Int?
    var bufferCount: Int
    var seekCount: Int
    var seekRecoveryCount: Int
    var seekRecoverySlowCount: Int
    var lastSeekRecoveryMilliseconds: Int?
    var speedBoostCount: Int
    var speedBoostInterruptionCount: Int
    var startupGapMessage: String?
    var startupBreakdownMessage: String?
    var hlsStartupMessage: String?
    var startupSchedulerMessage: String?
    var startupQuality: Int?
    var startupTargetQuality: Int?
    var startupCodec: String?
    var startupDecisionMessage: String?
    var startupCDNKey: String?
    var startupCDNTitle: String?
    var startupNetworkKey: String?
    var startupNetworkTitle: String?
    var avPlayerStartupPathOptimizationExperimentEnabled: Bool?
    var startupPlayerCreationMode: String?
    var piliPlusStylePlayURLSelectionExperimentEnabled: Bool?
    var relatedEarlyPlayURLPrefetchExperimentEnabled: Bool?
    var relatedStartupPackageWarmupExperimentEnabled: Bool?
    var startupSource: String?
    var startupPlayURLSource: String?
    var startupPlayURLVariantCount: Int?
    var startupRoutePlanState: String?
    var startupRoutePlanMilliseconds: Int?
    var startupRoutePrebuildState: String?
    var startupRoutePrebuildMilliseconds: Int?
    var startupPackageRoutePlanState: String?
    var startupPackageRangeState: String?
    var startupRangeWarmState: String?
    var startupRangeWarmMilliseconds: Int?
    var startupPackageMessage: String?
    var lastSeekBufferReadyCoveragePercent: Int?
    var accessLogMessage: String?
    var decodeLogMessage: String?
    var observedBitrateKilobitsPerSecond: Int?
    var indicatedBitrateKilobitsPerSecond: Int?
    var accessLogStallCount: Int?
    var accessLogTransferMilliseconds: Int?
    var accessLogBytesTransferred: Int64?
    var accessLogMediaRequestCount: Int?
    var failureMessage: String?
    var recentStartupSamples: [PlayerStartupPerformanceSample]?

    init(session: PlayerPerformanceSession) {
        id = session.id
        title = session.title
        lastUpdatedAt = session.lastUpdatedAt
        detailLoadMilliseconds = session.detailLoadMilliseconds
        playURLMilliseconds = session.playURLMilliseconds
        mediaPreparedMilliseconds = session.mediaPreparedMilliseconds
        prepareMilliseconds = session.prepareMilliseconds
        resumeApplyMilliseconds = session.resumeApplyMilliseconds
        resumeRecoveryCount = session.resumeRecoveryCount
        resumeRecoverySlowCount = session.resumeRecoverySlowCount
        lastResumeRecoveryMilliseconds = session.lastResumeRecoveryMilliseconds
        firstFrameTotalMilliseconds = session.firstFrameTotalMilliseconds
        firstFramePlayerMilliseconds = session.firstFramePlayerMilliseconds
        bufferCount = session.bufferCount
        seekCount = session.seekCount
        seekRecoveryCount = session.seekRecoveryCount
        seekRecoverySlowCount = session.seekRecoverySlowCount
        lastSeekRecoveryMilliseconds = session.lastSeekRecoveryMilliseconds
        speedBoostCount = session.speedBoostCount
        speedBoostInterruptionCount = session.speedBoostInterruptionCount
        startupGapMessage = session.startupGapMessage
        startupBreakdownMessage = session.startupBreakdownMessage
        hlsStartupMessage = session.hlsStartupMessage
        startupSchedulerMessage = session.startupSchedulerMessage
        startupQuality = session.startupQuality
        startupTargetQuality = session.startupTargetQuality
        startupCodec = session.startupCodec
        startupDecisionMessage = session.startupDecisionMessage
        startupCDNKey = session.startupCDNKey
        startupCDNTitle = session.startupCDNTitle
        startupNetworkKey = session.startupNetworkKey
        startupNetworkTitle = session.startupNetworkTitle
        avPlayerStartupPathOptimizationExperimentEnabled = session.avPlayerStartupPathOptimizationExperimentEnabled
        startupPlayerCreationMode = session.startupPlayerCreationMode
        piliPlusStylePlayURLSelectionExperimentEnabled = session.piliPlusStylePlayURLSelectionExperimentEnabled
        relatedEarlyPlayURLPrefetchExperimentEnabled = session.relatedEarlyPlayURLPrefetchExperimentEnabled
        relatedStartupPackageWarmupExperimentEnabled = session.relatedStartupPackageWarmupExperimentEnabled
        startupSource = session.startupSource
        startupPlayURLSource = session.startupPlayURLSource
        startupPlayURLVariantCount = session.startupPlayURLVariantCount
        startupRoutePlanState = session.startupRoutePlanState
        startupRoutePlanMilliseconds = session.startupRoutePlanMilliseconds
        startupRoutePrebuildState = session.startupRoutePrebuildState
        startupRoutePrebuildMilliseconds = session.startupRoutePrebuildMilliseconds
        startupPackageRoutePlanState = session.startupPackageRoutePlanState
        startupPackageRangeState = session.startupPackageRangeState
        startupRangeWarmState = session.startupRangeWarmState
        startupRangeWarmMilliseconds = session.startupRangeWarmMilliseconds
        startupPackageMessage = session.startupPackageMessage
        lastSeekBufferReadyCoveragePercent = session.lastSeekBufferReadyCoveragePercent
        accessLogMessage = session.accessLogMessage
        decodeLogMessage = session.decodeLogMessage
        observedBitrateKilobitsPerSecond = session.observedBitrateKilobitsPerSecond
        indicatedBitrateKilobitsPerSecond = session.indicatedBitrateKilobitsPerSecond
        accessLogStallCount = session.accessLogStallCount
        accessLogTransferMilliseconds = session.accessLogTransferMilliseconds
        accessLogBytesTransferred = session.accessLogBytesTransferred
        accessLogMediaRequestCount = session.accessLogMediaRequestCount
        failureMessage = session.failureMessage
        recentStartupSamples = session.recentStartupSamples
    }

    func makeSession() -> PlayerPerformanceSession {
        var session = PlayerPerformanceSession(id: id)
        session.title = title
        session.lastUpdatedAt = lastUpdatedAt
        session.detailLoadMilliseconds = detailLoadMilliseconds
        session.playURLMilliseconds = playURLMilliseconds
        session.mediaPreparedMilliseconds = mediaPreparedMilliseconds
        session.prepareMilliseconds = prepareMilliseconds
        session.resumeApplyMilliseconds = resumeApplyMilliseconds
        session.resumeRecoveryCount = resumeRecoveryCount
        session.resumeRecoverySlowCount = resumeRecoverySlowCount
        session.lastResumeRecoveryMilliseconds = lastResumeRecoveryMilliseconds
        session.firstFrameTotalMilliseconds = firstFrameTotalMilliseconds
        session.firstFramePlayerMilliseconds = firstFramePlayerMilliseconds
        session.bufferCount = bufferCount
        session.seekCount = seekCount
        session.seekRecoveryCount = seekRecoveryCount
        session.seekRecoverySlowCount = seekRecoverySlowCount
        session.lastSeekRecoveryMilliseconds = lastSeekRecoveryMilliseconds
        session.speedBoostCount = speedBoostCount
        session.speedBoostInterruptionCount = speedBoostInterruptionCount
        session.startupGapMessage = startupGapMessage
        session.startupBreakdownMessage = startupBreakdownMessage
        session.hlsStartupMessage = hlsStartupMessage
        session.startupSchedulerMessage = startupSchedulerMessage
        session.startupQuality = startupQuality
        session.startupTargetQuality = startupTargetQuality
        session.startupCodec = startupCodec
        session.startupDecisionMessage = startupDecisionMessage
        session.startupCDNKey = startupCDNKey
        session.startupCDNTitle = startupCDNTitle
        session.startupNetworkKey = startupNetworkKey
        session.startupNetworkTitle = startupNetworkTitle
        session.avPlayerStartupPathOptimizationExperimentEnabled = avPlayerStartupPathOptimizationExperimentEnabled
        session.startupPlayerCreationMode = startupPlayerCreationMode
        session.piliPlusStylePlayURLSelectionExperimentEnabled = piliPlusStylePlayURLSelectionExperimentEnabled
        session.relatedEarlyPlayURLPrefetchExperimentEnabled = relatedEarlyPlayURLPrefetchExperimentEnabled
        session.relatedStartupPackageWarmupExperimentEnabled = relatedStartupPackageWarmupExperimentEnabled
        session.startupSource = startupSource
        session.startupPlayURLSource = startupPlayURLSource
        session.startupPlayURLVariantCount = startupPlayURLVariantCount
        session.startupRoutePlanState = startupRoutePlanState
        session.startupRoutePlanMilliseconds = startupRoutePlanMilliseconds
        session.startupRoutePrebuildState = startupRoutePrebuildState
        session.startupRoutePrebuildMilliseconds = startupRoutePrebuildMilliseconds
        session.startupPackageRoutePlanState = startupPackageRoutePlanState
        session.startupPackageRangeState = startupPackageRangeState
        session.startupRangeWarmState = startupRangeWarmState
        session.startupRangeWarmMilliseconds = startupRangeWarmMilliseconds
        session.startupPackageMessage = startupPackageMessage
        session.lastSeekBufferReadyCoveragePercent = lastSeekBufferReadyCoveragePercent
        session.accessLogMessage = accessLogMessage
        session.decodeLogMessage = decodeLogMessage
        session.observedBitrateKilobitsPerSecond = observedBitrateKilobitsPerSecond
        session.indicatedBitrateKilobitsPerSecond = indicatedBitrateKilobitsPerSecond
        session.accessLogStallCount = accessLogStallCount
        session.accessLogTransferMilliseconds = accessLogTransferMilliseconds
        session.accessLogBytesTransferred = accessLogBytesTransferred
        session.accessLogMediaRequestCount = accessLogMediaRequestCount
        session.failureMessage = failureMessage
        session.recentStartupSamples = recentStartupSamples ?? []
        return session
    }
}

private actor PlayerPerformanceSessionPersistenceWriter {
    static let shared = PlayerPerformanceSessionPersistenceWriter()

    func persist(_ sessions: [PlayerPerformancePersistedSession], forKey key: String) {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

struct PlayerStartupPerformanceSample: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let date: Date
    let firstFrameTotalMilliseconds: Int?
    let firstFramePlayerMilliseconds: Int?
    let prepareToFrameMilliseconds: Int?
    let playToFrameMilliseconds: Int?
    let endpointMilliseconds: Int?
    let layerMilliseconds: Int?
    let readyMilliseconds: Int?
    let renderMilliseconds: Int?
    let decodedMilliseconds: Int?
    let ksRenderMilliseconds: Int?
    let ffmpegMilliseconds: Int?
    let ffmpegOpenMilliseconds: Int?
    let ffmpegFindMilliseconds: Int?
    let ffmpegReadyMilliseconds: Int?
    let frameDecodedMilliseconds: Int?
    let frameFetchedMilliseconds: Int?
    let displayEnqueueMilliseconds: Int?
    let metalDrawMilliseconds: Int?
    let probe: String?
    let codec: String?
    let frameRate: String?
    let resolution: String?
    let breakdownMessage: String

    init(
        date: Date = Date(),
        firstFrameTotalMilliseconds: Int?,
        firstFramePlayerMilliseconds: Int?,
        prepareToFrameMilliseconds: Int?,
        playToFrameMilliseconds: Int?,
        endpointMilliseconds: Int?,
        layerMilliseconds: Int?,
        readyMilliseconds: Int?,
        renderMilliseconds: Int?,
        decodedMilliseconds: Int?,
        ksRenderMilliseconds: Int?,
        ffmpegMilliseconds: Int?,
        ffmpegOpenMilliseconds: Int? = nil,
        ffmpegFindMilliseconds: Int? = nil,
        ffmpegReadyMilliseconds: Int? = nil,
        frameDecodedMilliseconds: Int?,
        frameFetchedMilliseconds: Int?,
        displayEnqueueMilliseconds: Int?,
        metalDrawMilliseconds: Int?,
        probe: String? = nil,
        codec: String?,
        frameRate: String? = nil,
        resolution: String?,
        breakdownMessage: String
    ) {
        id = UUID()
        self.date = date
        self.firstFrameTotalMilliseconds = firstFrameTotalMilliseconds
        self.firstFramePlayerMilliseconds = firstFramePlayerMilliseconds
        self.prepareToFrameMilliseconds = prepareToFrameMilliseconds
        self.playToFrameMilliseconds = playToFrameMilliseconds
        self.endpointMilliseconds = endpointMilliseconds
        self.layerMilliseconds = layerMilliseconds
        self.readyMilliseconds = readyMilliseconds
        self.renderMilliseconds = renderMilliseconds
        self.decodedMilliseconds = decodedMilliseconds
        self.ksRenderMilliseconds = ksRenderMilliseconds
        self.ffmpegMilliseconds = ffmpegMilliseconds
        self.ffmpegOpenMilliseconds = ffmpegOpenMilliseconds
        self.ffmpegFindMilliseconds = ffmpegFindMilliseconds
        self.ffmpegReadyMilliseconds = ffmpegReadyMilliseconds
        self.frameDecodedMilliseconds = frameDecodedMilliseconds
        self.frameFetchedMilliseconds = frameFetchedMilliseconds
        self.displayEnqueueMilliseconds = displayEnqueueMilliseconds
        self.metalDrawMilliseconds = metalDrawMilliseconds
        self.probe = probe
        self.codec = codec
        self.frameRate = frameRate
        self.resolution = resolution
        self.breakdownMessage = breakdownMessage
    }
}

struct PlayerPerformanceSession: Identifiable, Equatable {
    let id: String
    var metricsID: String { id }
    var title: String?
    var openedAt: Date?
    var detailStartedAt: Date?
    var playURLStartedAt: Date?
    var playURLLoadedAt: Date?
    var playerCreatedAt: Date?
    var prepareStartedAt: Date?
    var prepareReturnedAt: Date?
    var playRequestedAt: Date?
    var firstFrameAt: Date?
    var lastUpdatedAt = Date()
    var eventCount = 0
    var detailLoadMilliseconds: Int?
    var playURLMilliseconds: Int?
    var mediaPreparedMilliseconds: Int?
    var prepareMilliseconds: Int?
    var resumeApplyMilliseconds: Int?
    var resumeRecoveryCount = 0
    var resumeRecoverySlowCount = 0
    var lastResumeRecoveryMilliseconds: Int?
    var firstFrameTotalMilliseconds: Int?
    var firstFramePlayerMilliseconds: Int?
    var bufferCount = 0
    var seekCount = 0
    var seekRecoveryCount = 0
    var seekRecoverySlowCount = 0
    var lastSeekRecoveryMilliseconds: Int?
    var speedBoostCount = 0
    var speedBoostInterruptionCount = 0
    var lastBufferMessage: String?
    var networkMessage: String?
    var hlsStartupMessage: String?
    var startupSchedulerMessage: String?
    var accessLogMessage: String?
    var decodeLogMessage: String?
    var observedBitrateKilobitsPerSecond: Int?
    var indicatedBitrateKilobitsPerSecond: Int?
    var accessLogStallCount: Int?
    var accessLogTransferMilliseconds: Int?
    var accessLogBytesTransferred: Int64?
    var accessLogMediaRequestCount: Int?
    var mediaCacheMessage: String?
    var manifestStageMessage: String?
    var qualitySupplementMessage: String?
    var resumeDecisionMessage: String?
    var resumeRecoveryMessage: String?
    var seekMessage: String?
    var seekRecoveryMessage: String?
    var speedBoostMessage: String?
    var playbackRecoveryCount = 0
    var playbackRecoveryFailureCount = 0
    var playbackRecoveryMessage: String?
    var cdnHostMessage: String?
    var selectedQualityMessage: String?
    var detailSourceMessage: String?
    var prepareStageMessage: String?
    var startupGapMessage: String?
    var startupBreakdownMessage: String?
    var startupQuality: Int?
    var startupTargetQuality: Int?
    var startupCodec: String?
    var startupDecisionMessage: String?
    var startupCDNKey: String?
    var startupCDNTitle: String?
    var startupNetworkKey: String?
    var startupNetworkTitle: String?
    var avPlayerStartupPathOptimizationExperimentEnabled: Bool?
    var startupPlayerCreationMode: String?
    var piliPlusStylePlayURLSelectionExperimentEnabled: Bool?
    var relatedEarlyPlayURLPrefetchExperimentEnabled: Bool?
    var relatedStartupPackageWarmupExperimentEnabled: Bool?
    var startupSource: String?
    var startupPlayURLSource: String?
    var startupPlayURLVariantCount: Int?
    var startupRoutePlanState: String?
    var startupRoutePlanMilliseconds: Int?
    var startupRoutePrebuildState: String?
    var startupRoutePrebuildMilliseconds: Int?
    var startupPackageRoutePlanState: String?
    var startupPackageRangeState: String?
    var startupRangeWarmState: String?
    var startupRangeWarmMilliseconds: Int?
    var startupPackageMessage: String?
    var lastSeekBufferReadyCoveragePercent: Int?
    var failureMessage: String?
    var recentStartupSamples: [PlayerStartupPerformanceSample] = []
    var timeline: [PlayerPerformanceTimelineEntry] = []
}

struct PlayerPerformanceStoreUpdate {
    let metricsID: String?
}

enum PlayerPerformanceCopyTextFormatter {
    static func millisecondsText(_ value: Int?) -> String {
        guard let value else { return "-" }
        if value >= 1000 {
            return String(format: "%.2fs", Double(value) / 1000)
        }
        return "\(value)ms"
    }

    static func performanceLogCopyText(
        sessions: [PlayerPerformanceSession],
        sampleGroups: [PlayerPerformanceSampleGroup]
    ) -> String {
        let reportableSessions = sessions.filter(isReportableSession)
        var sections = [
            "CiliCili 播放性能日志",
            "generated: \(copyDateFormatter.string(from: Date()))",
            "sessions: \(reportableSessions.count)",
        ]

        if !sampleGroups.isEmpty {
            let sampleLines = sampleGroups.map { group in
                [
                    "  \(group.title) · \(group.subtitle)",
                    "    totalFirstFrameAvg=\(millisecondsText(group.averageFirstFrameMilliseconds)) p50=\(millisecondsText(group.p50FirstFrameMilliseconds)) p90=\(millisecondsText(group.p90FirstFrameMilliseconds)) playerFirstFrame=\(millisecondsText(group.averagePlayerFirstFrameMilliseconds)) playURL=\(millisecondsText(group.averagePlayURLMilliseconds)) prepare=\(millisecondsText(group.averagePrepareMilliseconds)) buffers=\(group.bufferCount) slow=\(group.slowStartupCount) failures=\(group.failedCount)",
                ].joined(separator: "\n")
            }
            sections.append((["启动样本"] + sampleLines).joined(separator: "\n"))
        }

        if reportableSessions.isEmpty {
            sections.append("暂无性能样本")
        } else {
            sections.append("最近播放会话")
            sections.append(
                contentsOf: reportableSessions.map {
                    performanceCopyText(metricsID: $0.metricsID, session: $0)
                })
        }

        return redactedDiagnosticText(sections.joined(separator: "\n\n"))
    }

    nonisolated static func isReportableSession(_ session: PlayerPerformanceSession) -> Bool {
        session.playURLMilliseconds != nil
            || session.prepareMilliseconds != nil
            || session.firstFrameTotalMilliseconds != nil
            || session.firstFramePlayerMilliseconds != nil
            || !session.recentStartupSamples.isEmpty
            || session.failureMessage != nil
    }

    static func performanceCopyText(metricsID: String, session: PlayerPerformanceSession?) -> String {
        guard let session else {
            return "播放性能\nmetricsID: \(metricsID)\n暂无性能样本"
        }

        var lines = [
            "播放性能测试结果",
            "metricsID: \(metricsID)",
            "title: \(session.title ?? "-")",
            "updated: \(copyDateFormatter.string(from: session.lastUpdatedAt))",
            "current:",
            "  totalFirstFrame: \(millisecondsText(session.firstFrameTotalMilliseconds))",
            "  playerFirstFrame: \(millisecondsText(session.firstFramePlayerMilliseconds))",
            "  detail: \(millisecondsText(session.detailLoadMilliseconds))",
            "  playURL: \(millisecondsText(session.playURLMilliseconds))",
            "  startupSource: \(session.startupSource ?? "-")",
            "  playURLSource: \(session.startupPlayURLSource ?? "-")",
            "  playURLVariants: \(session.startupPlayURLVariantCount.map(String.init) ?? "-")",
            "  startupPathOptimization: \(AVPlayerStartupPathOptimizationExperiment.diagnosticStateTitle(for: session.avPlayerStartupPathOptimizationExperimentEnabled))",
            "  playerCreationMode: \(AVPlayerStartupPathOptimizationExperiment.playerCreationMode(session.startupPlayerCreationMode).key)",
            "  piliPlusStyleAV1PlayURLSelection: \(PiliPlusStylePlayURLSelectionExperiment.diagnosticStateTitle(for: session.piliPlusStylePlayURLSelectionExperimentEnabled))",
            "  relatedEarlyPlayURLPrefetch: \(RelatedPlaybackEarlyPlayURLPrefetchPolicy.diagnosticStateTitle(for: session.relatedEarlyPlayURLPrefetchExperimentEnabled))",
            "  relatedStartupPackageWarmup: \(RelatedPlaybackStartupPackageWarmupPolicy.diagnosticStateTitle(for: session.relatedStartupPackageWarmupExperimentEnabled))",
            "  prepare: \(millisecondsText(session.prepareMilliseconds))",
            "  quality: \(session.startupQuality.map(String.init) ?? "-")",
            "  codec: \(session.startupCodec ?? latestSampleValue(session.recentStartupSamples, \.codec) ?? "-")",
            "  fps: \(latestSampleValue(session.recentStartupSamples, \.frameRate) ?? "-")",
            "  resolution: \(latestSampleValue(session.recentStartupSamples, \.resolution) ?? "-")",
        ]

        if let startupBreakdownMessage = session.startupBreakdownMessage {
            lines.append("startupBreakdown:")
            lines.append("  \(startupBreakdownMessage)")
        }
        if let startupGapMessage = session.startupGapMessage {
            lines.append("startupGaps:")
            lines.append("  \(startupGapMessage)")
        }
        if let hlsStartupMessage = session.hlsStartupMessage {
            lines.append("hlsStartup:")
            lines.append("  \(hlsStartupMessage)")
        }
        if let startupSchedulerMessage = session.startupSchedulerMessage {
            lines.append("startupScheduler:")
            lines.append("  \(startupSchedulerMessage)")
        }
        if let manifestStageMessage = session.manifestStageMessage {
            lines.append("manifestStage:")
            lines.append("  \(manifestStageMessage)")
        }
        appendDiagnosticSection("cdnHost", session.cdnHostMessage, to: &lines)
        appendDiagnosticSection("playbackFeedback", session.networkMessage, to: &lines)
        appendDiagnosticSection("accessLog", session.accessLogMessage, to: &lines)
        appendDiagnosticSection("mediaCache", session.mediaCacheMessage, to: &lines)
        appendDiagnosticSection("playbackRecovery", session.playbackRecoveryMessage, to: &lines)
        appendDiagnosticSection("failure", session.failureMessage, to: &lines)

        let samples = session.recentStartupSamples
        let comparableSamples = comparableStartupSamples(from: samples)
        let stableSamples = stableStartupSamples(from: samples)
        let ignoredSampleCount = max(samples.count - comparableSamples.count, 0)
        let coldSampleCount = max(comparableSamples.count - stableSamples.count, 0)
        let sampleFilter = startupSampleFilterText(for: samples) ?? "-"
        lines.append(
            "recentSamples(count=\(samples.count), comparable=\(comparableSamples.count), stable=\(stableSamples.count), filter=\(sampleFilter), ignored=\(ignoredSampleCount), cold=\(coldSampleCount)):"
        )
        for summary in startupSampleSummaries(from: stableSamples) {
            lines.append(
                "  \(summary.title): min=\(millisecondsText(summary.minimumMilliseconds)) avg=\(millisecondsText(summary.averageMilliseconds)) max=\(millisecondsText(summary.maximumMilliseconds))"
            )
        }

        if !samples.isEmpty {
            lines.append("sampleDetails:")
            let comparableIDs = Set(comparableSamples.map(\.id))
            let stableIDs = Set(stableSamples.map(\.id))
            for (index, sample) in samples.enumerated() {
                let sampleStatus =
                    stableIDs.contains(sample.id)
                    ? "stable"
                    : (comparableIDs.contains(sample.id) ? "cold" : "other")
                lines.append(
                    [
                        "  #\(index + 1)",
                        copyDateFormatter.string(from: sample.date),
                        "status=\(sampleStatus)",
                        "player=\(millisecondsText(sample.firstFramePlayerMilliseconds))",
                        "total=\(millisecondsText(sample.firstFrameTotalMilliseconds))",
                        "ready=\(millisecondsText(sample.readyMilliseconds))",
                        "ffmpeg=\(millisecondsText(sample.ffmpegMilliseconds))",
                        "open=\(millisecondsText(sample.ffmpegOpenMilliseconds))",
                        "find=\(millisecondsText(sample.ffmpegFindMilliseconds))",
                        "ffReady=\(millisecondsText(sample.ffmpegReadyMilliseconds))",
                        "render=\(millisecondsText(sample.renderMilliseconds))",
                        "layer=\(millisecondsText(sample.layerMilliseconds))",
                        "endpoint=\(millisecondsText(sample.endpointMilliseconds))",
                        "frame=\(millisecondsText(sample.frameDecodedMilliseconds))",
                        "fetch=\(millisecondsText(sample.frameFetchedMilliseconds))",
                        "enq=\(millisecondsText(sample.displayEnqueueMilliseconds))",
                        "metal=\(millisecondsText(sample.metalDrawMilliseconds))",
                        "probe=\(sample.probe ?? "-")",
                        "fps=\(sample.frameRate ?? "-")",
                        "codec=\(sample.codec ?? "-")",
                        "res=\(sample.resolution ?? "-")",
                    ].joined(separator: " ")
                )
            }
        }

        return redactedDiagnosticText(lines.joined(separator: "\n"))
    }

    private struct SampleMetricSummary {
        let id: String
        let title: String
        let minimumMilliseconds: Int
        let averageMilliseconds: Int
        let maximumMilliseconds: Int
    }

    private static func latestSampleValue(
        _ samples: [PlayerStartupPerformanceSample],
        _ keyPath: KeyPath<PlayerStartupPerformanceSample, String?>
    ) -> String? {
        samples.last?[keyPath: keyPath]
    }

    private static func appendDiagnosticSection(
        _ title: String,
        _ message: String?,
        to lines: inout [String]
    ) {
        guard let message,
            !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        lines.append("\(title):")
        for line in message.components(separatedBy: .newlines) {
            lines.append("  \(line)")
        }
    }

    static func redactedDiagnosticText(_ text: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: #"https?://[^\s]+"#) else {
            return text
        }
        let matches = expression.matches(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        )
        return matches.reversed().reduce(text) { result, match in
            guard let range = Range(match.range, in: result) else { return result }
            let rawURL = String(result[range])
            let replacement = URL(string: rawURL)?.host.map { "URL[host=\($0)]" } ?? "URL[redacted]"
            var redacted = result
            redacted.replaceSubrange(range, with: replacement)
            return redacted
        }
    }

    private static func startupSampleSummaries(
        from samples: [PlayerStartupPerformanceSample]
    ) -> [SampleMetricSummary] {
        [
            summary(id: "player", title: "播放器", samples: samples, value: \.firstFramePlayerMilliseconds),
            summary(id: "ready", title: "ready", samples: samples, value: \.readyMilliseconds),
            summary(id: "ffmpeg", title: "ffmpeg", samples: samples, value: \.ffmpegMilliseconds),
            summary(id: "ffOpen", title: "open", samples: samples, value: \.ffmpegOpenMilliseconds),
            summary(id: "ffFind", title: "find", samples: samples, value: \.ffmpegFindMilliseconds),
            summary(id: "ffReady", title: "ffReady", samples: samples, value: \.ffmpegReadyMilliseconds),
            summary(id: "render", title: "render", samples: samples, value: \.renderMilliseconds),
            summary(id: "layer", title: "layer", samples: samples, value: \.layerMilliseconds),
            summary(id: "endpoint", title: "endpoint", samples: samples, value: \.endpointMilliseconds),
            summary(id: "frameDone", title: "frame", samples: samples, value: \.frameDecodedMilliseconds),
            summary(id: "fetch", title: "fetch", samples: samples, value: \.frameFetchedMilliseconds),
            summary(id: "enqueue", title: "enq", samples: samples, value: \.displayEnqueueMilliseconds),
        ].compactMap { $0 }
    }

    private static func comparableStartupSamples(
        from samples: [PlayerStartupPerformanceSample]
    ) -> [PlayerStartupPerformanceSample] {
        guard let latest = samples.last else { return samples }
        return samples.filter { sample in
            sample.codec == latest.codec
                && sample.resolution == latest.resolution
                && sample.frameRate == latest.frameRate
                && sample.probe == latest.probe
        }
    }

    private static func stableStartupSamples(
        from samples: [PlayerStartupPerformanceSample]
    ) -> [PlayerStartupPerformanceSample] {
        let comparableSamples = comparableStartupSamples(from: samples)
        guard comparableSamples.count >= 3 else { return comparableSamples }

        let playerLimit = outlierLimit(
            for: comparableSamples.compactMap(\.firstFramePlayerMilliseconds),
            minimumHeadroom: 180,
            multiplier: 2
        )
        let readyLimit = outlierLimit(
            for: comparableSamples.compactMap(\.readyMilliseconds),
            minimumHeadroom: 180,
            multiplier: 2
        )
        let ffmpegLimit = outlierLimit(
            for: comparableSamples.compactMap(\.ffmpegMilliseconds),
            minimumHeadroom: 180,
            multiplier: 3
        )

        let stableSamples = comparableSamples.filter { sample in
            !isAboveOutlierLimit(sample.firstFramePlayerMilliseconds, limit: playerLimit)
                && !isAboveOutlierLimit(sample.readyMilliseconds, limit: readyLimit)
                && !isAboveOutlierLimit(sample.ffmpegMilliseconds, limit: ffmpegLimit)
        }

        return stableSamples.count >= 2 ? stableSamples : comparableSamples
    }

    private static func startupSampleFilterText(
        for samples: [PlayerStartupPerformanceSample]
    ) -> String? {
        guard let latest = samples.last else { return nil }
        let codec = latest.codec ?? "-"
        let resolution = latest.resolution ?? "-"
        let frameRate = latest.frameRate.map { "\($0)fps" } ?? "-"
        let probe = latest.probe ?? "-"
        return "\(codec) \(resolution) \(frameRate) \(probe)"
    }

    private static var copyDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }

    private static func outlierLimit(
        for values: [Int],
        minimumHeadroom: Int,
        multiplier: Double
    ) -> Int? {
        guard let median = medianValue(for: values) else { return nil }
        let multipliedLimit = Int((Double(median) * multiplier).rounded())
        return max(multipliedLimit, median + minimumHeadroom)
    }

    private static func medianValue(for values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        let sortedValues = values.sorted()
        let middle = sortedValues.count / 2
        if sortedValues.count.isMultiple(of: 2) {
            return Int((Double(sortedValues[middle - 1] + sortedValues[middle]) / 2).rounded())
        }
        return sortedValues[middle]
    }

    private static func isAboveOutlierLimit(_ value: Int?, limit: Int?) -> Bool {
        guard let value, let limit else { return false }
        return value > limit
    }

    private static func summary(
        id: String,
        title: String,
        samples: [PlayerStartupPerformanceSample],
        value: KeyPath<PlayerStartupPerformanceSample, Int?>
    ) -> SampleMetricSummary? {
        let values = samples.compactMap { $0[keyPath: value] }
        guard !values.isEmpty else { return nil }
        let average = Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
        return SampleMetricSummary(
            id: id,
            title: title,
            minimumMilliseconds: values.min() ?? average,
            averageMilliseconds: average,
            maximumMilliseconds: values.max() ?? average
        )
    }
}

struct PlayerPlaybackAdaptationProfile: Equatable, Sendable {
    enum Level: Int, Sendable {
        case normal = 0
        case fallback = 1
        case cautious = 2
        case slow = 3

        nonisolated var startupQualityCeiling: Int? {
            nil
        }

        nonisolated var shouldAllowStartupCacheFallback: Bool {
            self != .normal
        }

        nonisolated var shouldWarmSupplementalVariants: Bool {
            self == .normal
        }

        nonisolated var shouldRefreshPlaybackCDNProbe: Bool {
            self.rawValue >= Level.cautious.rawValue
        }

        nonisolated var danmakuLoadFactor: Double {
            switch self {
            case .normal:
                return 1.0
            case .fallback:
                return 0.86
            case .cautious:
                return 0.68
            case .slow:
                return 0.5
            }
        }
    }

    let level: Level
    let isEnabled: Bool

    nonisolated static let normal = PlayerPlaybackAdaptationProfile(level: .normal)

    nonisolated init(level: Level, isEnabled: Bool = true) {
        self.level = isEnabled ? level : .normal
        self.isEnabled = isEnabled
    }

    nonisolated var startupQualityCeiling: Int? {
        isEnabled ? level.startupQualityCeiling : nil
    }

    nonisolated var shouldAllowStartupCacheFallback: Bool {
        isEnabled && level.shouldAllowStartupCacheFallback
    }

    nonisolated var shouldWarmSupplementalVariants: Bool {
        !isEnabled || level.shouldWarmSupplementalVariants
    }

    nonisolated var diagnosticTitle: String {
        guard isEnabled else { return "关闭" }
        switch level {
        case .normal:
            return "正常"
        case .fallback:
            return "轻度保守"
        case .cautious:
            return "保守"
        case .slow:
            return "慢速保护"
        }
    }

    nonisolated var startupQualityCeilingTitle: String {
        startupQualityCeiling.map(String.init) ?? "不限"
    }

    nonisolated var shouldRefreshPlaybackCDNProbe: Bool {
        isEnabled && level.shouldRefreshPlaybackCDNProbe
    }

    nonisolated var danmakuLoadFactor: Double {
        isEnabled ? level.danmakuLoadFactor : 1.0
    }

    nonisolated var shouldThrottleBackgroundPreload: Bool {
        isEnabled && level.rawValue >= Level.cautious.rawValue
    }

    nonisolated var prefersEnergyEfficientVideo: Bool {
        isEnabled && level.rawValue >= Level.cautious.rawValue
    }

    nonisolated var backgroundPreloadLimit: Int {
        guard isEnabled else { return 3 }
        switch level {
        case .normal:
            return 3
        case .fallback:
            return 2
        case .cautious:
            return 1
        case .slow:
            return 0
        }
    }

    nonisolated var backgroundRoutePlanPreloadLimit: Int {
        guard isEnabled else { return 3 }
        switch level {
        case .normal:
            return 3
        case .fallback:
            return 2
        case .cautious, .slow:
            return 1
        }
    }
}

@MainActor
final class PlayerPerformanceStore: ObservableObject {
    static let shared = PlayerPerformanceStore()
    nonisolated static let startupSchedulerDiagnosticPartLimit = 10

    private static let persistedSessionsKey = "cc.bili.player.performance.sessions.v2"
    private static let persistedSessionMaxAge: TimeInterval = 7 * 24 * 60 * 60
    private static let performanceOverlayEnabledKey = "cc.bili.playback.performanceOverlayEnabled.v1"

    private(set) var events: [PlayerPerformanceEvent] = []
    private(set) var sessions: [PlayerPerformanceSession] = []
    let updates = PassthroughSubject<PlayerPerformanceStoreUpdate, Never>()
    private let maxEventCount = 160
    private let maxSessionCount = 24
    private let maxPersistedSessionCount = 48
    private var sessionsByID: [String: PlayerPerformanceSession] = [:]
    private var persistTask: Task<Void, Never>?
    private var persistGeneration = 0
    private var performanceCopyLogTasks: [String: Task<Void, Never>] = [:]
    private var lastPerformanceCopyLogSignatures: [String: String] = [:]

    private init() {
        loadPersistedSessions()
    }

    func record(
        _ kind: PlayerPerformanceEvent.Kind,
        metricsID: String,
        title: String? = nil,
        message: String? = nil
    ) {
        objectWillChange.send()
        let event = PlayerPerformanceEvent(kind: kind, metricsID: metricsID, title: title, message: message)
        events.append(event)
        if events.count > maxEventCount {
            events.removeFirst(events.count - maxEventCount)
        }
        updateSession(with: event)
        updates.send(PlayerPerformanceStoreUpdate(metricsID: metricsID))
    }

    func session(for metricsID: String) -> PlayerPerformanceSession? {
        sessionsByID[metricsID]
    }

    func mostRecentSession() -> PlayerPerformanceSession? {
        sessions.first
    }

    func performanceLogCopyText() -> String {
        PlayerPerformanceCopyTextFormatter.performanceLogCopyText(
            sessions: sessions,
            sampleGroups: startupSampleGroups(limit: maxSessionCount)
        )
    }

    func startupSampleGroups(limit: Int = 8) -> [PlayerPerformanceSampleGroup] {
        var accumulators: [String: PlayerPerformanceSampleGroupAccumulator] = [:]
        for session in sessions where Self.hasStartupSample(session) {
            let quality = session.startupQuality
            let cdnKey = session.startupCDNKey ?? "unknown"
            let cdnTitle = session.startupCDNTitle ?? "未知 CDN"
            let networkKey = session.startupNetworkKey ?? "unknown"
            let networkTitle = session.startupNetworkTitle ?? "未知网络"
            let startupSource = Self.startupSource(for: session)
            let codec = Self.startupCodec(for: session)
            let experimentState = AVPlayerStartupPathOptimizationExperiment.diagnosticStateTitle(
                for: session.avPlayerStartupPathOptimizationExperimentEnabled
            )
            let id =
                "\(quality.map(String.init) ?? "unknown")|\(cdnKey)|\(networkKey)|\(startupSource.key)|\(codec.key)|\(experimentState)"
            let playerCreationMode = AVPlayerStartupPathOptimizationExperiment.playerCreationMode(
                session.startupPlayerCreationMode
            )
            let piliPlusExperimentState = PiliPlusStylePlayURLSelectionExperiment.diagnosticStateTitle(
                for: session.piliPlusStylePlayURLSelectionExperimentEnabled
            )
            let relatedEarlyPrefetchExperimentState =
                RelatedPlaybackEarlyPlayURLPrefetchPolicy.diagnosticStateTitle(
                    for: session.relatedEarlyPlayURLPrefetchExperimentEnabled
                )
            let relatedStartupPackageWarmupExperimentState =
                RelatedPlaybackStartupPackageWarmupPolicy.diagnosticStateTitle(
                    for: session.relatedStartupPackageWarmupExperimentEnabled
                )
            let playURLSelectionStrategy = PiliPlusStylePlayURLSelectionExperiment.sampleGroupStrategy(
                startupSchedulerMessage: session.startupSchedulerMessage,
                isEnabled: session.piliPlusStylePlayURLSelectionExperimentEnabled
            )
            let scopedID = [
                id,
                playerCreationMode.key,
                piliPlusExperimentState,
                relatedEarlyPrefetchExperimentState,
                relatedStartupPackageWarmupExperimentState,
                playURLSelectionStrategy.key,
            ].joined(separator: "|")
            var accumulator =
                accumulators[scopedID]
                ?? PlayerPerformanceSampleGroupAccumulator(
                    id: scopedID,
                    quality: quality,
                    cdnKey: cdnKey,
                    cdnTitle: cdnTitle,
                    networkKey: networkKey,
                    networkTitle: networkTitle,
                    startupSourceKey: startupSource.key,
                    startupSourceTitle: startupSource.title,
                    codecKey: codec.key,
                    codecTitle: codec.title,
                    avPlayerStartupPathOptimizationExperimentEnabled: session
                        .avPlayerStartupPathOptimizationExperimentEnabled,
                    playerCreationModeKey: playerCreationMode.key,
                    playerCreationModeTitle: playerCreationMode.title,
                    piliPlusStylePlayURLSelectionExperimentEnabled: session
                        .piliPlusStylePlayURLSelectionExperimentEnabled,
                    relatedEarlyPlayURLPrefetchExperimentEnabled: session
                        .relatedEarlyPlayURLPrefetchExperimentEnabled,
                    relatedStartupPackageWarmupExperimentEnabled: session
                        .relatedStartupPackageWarmupExperimentEnabled,
                    playURLSelectionStrategyKey: playURLSelectionStrategy.key,
                    playURLSelectionStrategyTitle: playURLSelectionStrategy.title
                )
            accumulator.record(session)
            accumulators[scopedID] = accumulator
        }

        let groups = accumulators.values
            .map { $0.makeGroup() }
            .sorted { lhs, rhs in
                if lhs.recommendationScore != rhs.recommendationScore {
                    return lhs.recommendationScore < rhs.recommendationScore
                }
                if lhs.sampleCount != rhs.sampleCount {
                    return lhs.sampleCount > rhs.sampleCount
                }
                return lhs.lastUpdatedAt > rhs.lastUpdatedAt
            }
        return Array(groups.prefix(limit))
    }

    private static func startupSource(for session: PlayerPerformanceSession) -> (key: String, title: String) {
        let source = (session.startupSource ?? session.startupPlayURLSource ?? "unknown")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        switch source.lowercased() {
        case "network":
            return ("network", "网络请求")
        case "cache":
            return ("cache", "缓存")
        case "pendingcache":
            return ("pendingcache", "等待缓存")
        default:
            return (source.isEmpty ? "unknown" : source.lowercased(), source.isEmpty ? "未知来源" : source)
        }
    }

    private static func startupCodec(for session: PlayerPerformanceSession) -> (key: String, title: String) {
        let codec =
            (session.startupCodec ?? session.recentStartupSamples.last?.codec)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        if codec.contains("av01") || codec.contains("av1") {
            return ("av1", "AV1")
        }
        if codec.contains("hvc") || codec.contains("hev") {
            return ("hevc", "HEVC")
        }
        if codec.contains("avc") || codec.contains("h264") {
            return ("avc", "AVC")
        }
        return (codec.isEmpty ? "unknown" : codec, codec.isEmpty ? "未知编码" : codec.uppercased())
    }

    func adaptivePreferredQuality(for preferredQuality: Int?, metricsID: String? = nil) -> Int? {
        let ceiling = playbackAdaptationProfile(for: metricsID).startupQualityCeiling
        guard let ceiling else { return preferredQuality }
        guard let preferredQuality else { return ceiling }
        return min(preferredQuality, ceiling)
    }

    func adaptivePreferredQuality(
        for preferredQuality: Int?,
        metricsID: String? = nil,
        isEnabled: Bool
    ) -> Int? {
        guard isEnabled else { return preferredQuality }
        return adaptivePreferredQuality(for: preferredQuality, metricsID: metricsID)
    }

    func playbackAdaptationProfile(for metricsID: String? = nil) -> PlayerPlaybackAdaptationProfile {
        playbackAdaptationProfile(for: metricsID, isEnabled: true)
    }

    func playbackAdaptationProfile(
        for metricsID: String? = nil,
        isEnabled: Bool
    ) -> PlayerPlaybackAdaptationProfile {
        guard isEnabled else {
            return PlayerPlaybackAdaptationProfile(level: .normal, isEnabled: false)
        }
        let relevantSessions = relevantPlaybackSessions(for: metricsID)
        let worstLevel =
            relevantSessions
            .map(Self.adaptationLevel(for:))
            .max { $0.rawValue < $1.rawValue } ?? .normal
        return PlayerPlaybackAdaptationProfile(level: worstLevel, isEnabled: true)
    }

    func shouldRefreshPlaybackCDNProbe(for metricsID: String? = nil) -> Bool {
        playbackAdaptationProfile(for: metricsID).shouldRefreshPlaybackCDNProbe
    }

    func shouldRefreshPlaybackCDNProbe(metricsID: String? = nil, isEnabled: Bool) -> Bool {
        playbackAdaptationProfile(for: metricsID, isEnabled: isEnabled).shouldRefreshPlaybackCDNProbe
    }

    func clear() {
        objectWillChange.send()
        persistTask?.cancel()
        persistTask = nil
        persistGeneration &+= 1
        for task in performanceCopyLogTasks.values {
            task.cancel()
        }
        performanceCopyLogTasks.removeAll()
        lastPerformanceCopyLogSignatures.removeAll()
        events.removeAll()
        sessions.removeAll()
        sessionsByID.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.persistedSessionsKey)
        updates.send(PlayerPerformanceStoreUpdate(metricsID: nil))
    }

    private func relevantPlaybackSessions(for metricsID: String?) -> [PlayerPerformanceSession] {
        var candidates = Array(sessions.prefix(3))
        if let metricsID,
            let session = sessionsByID[metricsID],
            !candidates.contains(session)
        {
            candidates.insert(session, at: 0)
        }
        return candidates
    }

    private nonisolated static func hasStartupSample(_ session: PlayerPerformanceSession) -> Bool {
        session.startupBreakdownMessage != nil
            || session.firstFrameTotalMilliseconds != nil
            || session.firstFramePlayerMilliseconds != nil
            || session.playURLMilliseconds != nil
            || session.prepareMilliseconds != nil
            || session.accessLogMessage != nil
            || session.failureMessage != nil
    }

    private nonisolated static func adaptationLevel(for session: PlayerPerformanceSession)
        -> PlayerPlaybackAdaptationProfile.Level
    {
        let startupMilliseconds =
            session.firstFrameTotalMilliseconds
            ?? session.prepareMilliseconds
            ?? session.playURLMilliseconds
            ?? session.detailLoadMilliseconds
            ?? 0
        let playerMilliseconds = session.firstFramePlayerMilliseconds ?? 0

        if startupMilliseconds >= 2_600
            || playerMilliseconds >= 2_000
            || session.bufferCount >= 2
            || session.resumeRecoverySlowCount >= 2
            || session.lastResumeRecoveryMilliseconds.map({ $0 >= 2_200 }) == true
            || session.seekCount >= 14
            || session.seekRecoverySlowCount >= 2
            || session.lastSeekRecoveryMilliseconds.map({ $0 >= 2_200 }) == true
            || session.accessLogStallCount.map({ $0 >= 2 }) == true
            || session.speedBoostInterruptionCount >= 3
        {
            return .slow
        }
        if startupMilliseconds >= 1_600
            || playerMilliseconds >= 1_400
            || session.bufferCount >= 1
            || session.resumeRecoverySlowCount >= 1
            || session.lastResumeRecoveryMilliseconds.map({ $0 >= 1_250 }) == true
            || session.seekCount >= 8
            || session.seekRecoverySlowCount >= 1
            || session.lastSeekRecoveryMilliseconds.map({ $0 >= 1_250 }) == true
            || session.accessLogStallCount.map({ $0 >= 1 }) == true
            || session.speedBoostInterruptionCount >= 1
            || session.playURLMilliseconds.map({ $0 >= 1_000 }) == true
            || session.prepareMilliseconds.map({ $0 >= 1_400 }) == true
        {
            return .cautious
        }
        if startupMilliseconds >= 1_100
            || session.playURLMilliseconds.map({ $0 >= 700 }) == true
            || session.prepareMilliseconds.map({ $0 >= 1_000 }) == true
            || session.detailLoadMilliseconds.map({ $0 >= 1_200 }) == true
        {
            return .fallback
        }
        return .normal
    }

    private func updateSession(with event: PlayerPerformanceEvent) {
        var session = sessionsByID[event.metricsID] ?? PlayerPerformanceSession(id: event.metricsID)
        if let title = event.title, !title.isEmpty {
            session.title = title
        }

        if shouldResetPlaybackAttempt(for: event.kind, session: session) {
            resetPlaybackAttempt(&session)
        }

        if session.eventCount == 0 {
            session.avPlayerStartupPathOptimizationExperimentEnabled =
                AVPlayerStartupPathOptimizationExperiment.stored()
            session.piliPlusStylePlayURLSelectionExperimentEnabled = PiliPlusStylePlayURLSelectionExperiment.stored()
            session.relatedEarlyPlayURLPrefetchExperimentEnabled = true
            session.relatedStartupPackageWarmupExperimentEnabled = true
        }

        session.lastUpdatedAt = event.date
        session.eventCount += 1

        switch event.kind {
        case .routeOpen:
            session.openedAt = event.date
        case .detailLoadStart:
            session.openedAt = session.openedAt ?? event.date
            session.detailStartedAt = event.date
        case .detailLoaded:
            if let start = session.detailStartedAt {
                session.detailLoadMilliseconds = Self.milliseconds(from: start, to: event.date)
            }
            session.detailSourceMessage = event.message ?? session.detailSourceMessage
        case .playURLStart:
            session.playURLStartedAt = event.date
        case .playURLLoaded:
            session.playURLLoadedAt = event.date
            if let start = session.playURLStartedAt {
                session.playURLMilliseconds = Self.milliseconds(from: start, to: event.date)
            }
            session.selectedQualityMessage = event.message ?? session.selectedQualityMessage
            if let message = event.message {
                Self.updatePlayURLStartupFields(message, in: &session)
            }
        case .playerCreated:
            if session.firstFrameTotalMilliseconds == nil {
                session.playerCreatedAt = session.playerCreatedAt ?? event.date
            }
            if let message = event.message, !message.isEmpty {
                session.selectedQualityMessage = message
            }
        case .prepareRequested:
            guard session.firstFrameTotalMilliseconds == nil else { break }
            session.prepareStartedAt = session.prepareStartedAt ?? event.date
        case .mediaPrepared:
            if session.firstFrameTotalMilliseconds == nil {
                session.mediaPreparedMilliseconds = Self.firstMilliseconds(in: event.message)
                session.prepareStageMessage = event.message ?? session.prepareStageMessage
            }
        case .prepareReturned:
            guard session.firstFrameTotalMilliseconds == nil else { break }
            session.prepareReturnedAt = event.date
            if let start = session.prepareStartedAt {
                session.prepareMilliseconds = Self.milliseconds(from: start, to: event.date)
            } else {
                session.prepareMilliseconds = Self.firstMilliseconds(in: event.message)
            }
        case .playRequested:
            guard session.firstFrameTotalMilliseconds == nil else { break }
            session.playRequestedAt = session.playRequestedAt ?? event.date
        case .firstFrame:
            guard session.firstFrameTotalMilliseconds == nil else { break }
            session.firstFrameAt = event.date
            let openedAt =
                session.openedAt
                ?? session.detailStartedAt
                ?? session.playURLStartedAt
                ?? session.playerCreatedAt
                ?? session.prepareStartedAt
            if let openedAt {
                session.firstFrameTotalMilliseconds = Self.milliseconds(from: openedAt, to: event.date)
            }
            if let playerMilliseconds = Self.firstMilliseconds(in: event.message) {
                session.firstFramePlayerMilliseconds = playerMilliseconds
            }
        case .startupBreakdown:
            session.startupBreakdownMessage = Self.startupBreakdownMessage(
                baseMessage: event.message ?? session.startupBreakdownMessage,
                for: session
            )
            if let message = event.message {
                let tokens = Self.keyValueTokens(in: message)
                session.detailLoadMilliseconds =
                    session.detailLoadMilliseconds
                    ?? Self.millisecondsValue(for: "detail", in: tokens)
                session.playURLMilliseconds =
                    session.playURLMilliseconds
                    ?? Self.millisecondsValue(for: "playurl", in: tokens)
                session.prepareMilliseconds =
                    session.prepareMilliseconds
                    ?? Self.millisecondsValue(for: "prepare", in: tokens)
                session.firstFramePlayerMilliseconds =
                    session.firstFramePlayerMilliseconds
                    ?? Self.millisecondsValue(for: "firstFrame", in: tokens)
                session.startupQuality = Self.integerValue(for: "q", in: tokens) ?? session.startupQuality
                if let targetQuality = Self.integerValue(for: "targetQ", in: tokens),
                    targetQuality > 0
                {
                    session.startupTargetQuality = targetQuality
                }
                if let cdnKey = tokens["cdn"], !cdnKey.isEmpty {
                    session.startupCDNKey = cdnKey
                    session.startupCDNTitle = Self.cdnTitle(for: cdnKey)
                }
                if let networkKey = tokens["network"], !networkKey.isEmpty {
                    session.startupNetworkKey = networkKey
                    session.startupNetworkTitle = Self.networkTitle(for: networkKey)
                }
                if let source = tokens["source"], source != "-" {
                    session.startupSource = source
                }
                Self.updateStartupCodec(tokens["codec"], in: &session)
                Self.appendStartupSampleIfNeeded(
                    event: event,
                    tokens: tokens,
                    message: message,
                    to: &session
                )
            }
        case .startupScheduler:
            session.startupSchedulerMessage = Self.appendDiagnosticMessage(
                session.startupSchedulerMessage,
                event.message,
                maxParts: Self.startupSchedulerDiagnosticPartLimit
            )
        case .buffering:
            session.bufferCount += 1
            session.lastBufferMessage = event.message ?? session.lastBufferMessage
        case .network:
            if let message = event.message, message.hasPrefix("HLS ") {
                session.hlsStartupMessage = message
            } else {
                session.networkMessage = Self.appendDiagnosticMessage(
                    session.networkMessage,
                    event.message,
                    maxParts: 4
                )
            }
            if let message = event.message, let host = Self.host(in: message) {
                session.cdnHostMessage = host
            }
        case .accessLog:
            if let message = event.message {
                let tokens = Self.keyValueTokens(in: message)
                session.observedBitrateKilobitsPerSecond =
                    Self.integerValue(for: "observedKbps", in: tokens)
                    ?? session.observedBitrateKilobitsPerSecond
                session.indicatedBitrateKilobitsPerSecond =
                    Self.integerValue(for: "indicatedKbps", in: tokens)
                    ?? session.indicatedBitrateKilobitsPerSecond
                if let stalls = Self.integerValue(for: "stalls", in: tokens) {
                    session.accessLogStallCount = max(session.accessLogStallCount ?? 0, stalls)
                }
                session.accessLogTransferMilliseconds =
                    Self.millisecondsValue(for: "transfer", in: tokens)
                    ?? session.accessLogTransferMilliseconds
                if let bytes = Self.integer64Value(for: "bytes", in: tokens) {
                    session.accessLogBytesTransferred = bytes
                }
                session.accessLogMediaRequestCount =
                    Self.integerValue(for: "requests", in: tokens)
                    ?? session.accessLogMediaRequestCount
                if let host = tokens["host"], !host.isEmpty, host != "-" {
                    session.cdnHostMessage = host
                }
                session.accessLogMessage = Self.appendDiagnosticMessage(
                    session.accessLogMessage,
                    message,
                    maxParts: 3
                )
            }
        case .decodeLog:
            session.decodeLogMessage = Self.appendDiagnosticMessage(
                session.decodeLogMessage,
                event.message,
                maxParts: 4
            )
        case .mediaCache:
            session.mediaCacheMessage = event.message ?? session.mediaCacheMessage
        case .manifestStage:
            session.manifestStageMessage = Self.appendManifestStageMessage(
                session.manifestStageMessage,
                event.message
            )
            if let message = event.message {
                Self.updateManifestStartupFields(message, in: &session)
            }
        case .qualitySupplement:
            session.qualitySupplementMessage = event.message ?? session.qualitySupplementMessage
            if let message = event.message {
                Self.updateStartupQualityFields(message, in: &session)
            }
        case .resumeDecision:
            if event.message?.contains("player applied") == true,
                let applyMilliseconds = Self.firstMilliseconds(in: event.message)
            {
                session.resumeApplyMilliseconds = applyMilliseconds
            }
            session.resumeDecisionMessage = Self.appendDiagnosticMessage(
                session.resumeDecisionMessage,
                event.message,
                maxParts: 5
            )
        case .resumeRecovery:
            session.resumeRecoveryCount += 1
            if event.message?.contains("recovered=false") == true {
                session.resumeRecoverySlowCount += 1
            } else if let recoveryMilliseconds = Self.firstMilliseconds(in: event.message) {
                session.lastResumeRecoveryMilliseconds = recoveryMilliseconds
                if recoveryMilliseconds >= 1_250 {
                    session.resumeRecoverySlowCount += 1
                }
            }
            session.resumeRecoveryMessage = Self.appendDiagnosticMessage(
                session.resumeRecoveryMessage,
                event.message,
                maxParts: 4
            )
        case .seek:
            let isBufferReady = event.message?.contains("bufferReady") == true
            let isScrubInteraction = event.message?.hasPrefix("scrub ") == true
            if isBufferReady {
                let tokens = Self.keyValueTokens(in: event.message ?? "")
                session.lastSeekBufferReadyCoveragePercent =
                    Self.percentageValue(for: "coverage", in: tokens)
                    ?? session.lastSeekBufferReadyCoveragePercent
            } else if !isScrubInteraction {
                session.seekCount += 1
            }
            session.seekMessage = Self.appendDiagnosticMessage(
                session.seekMessage,
                event.message,
                maxParts: 4
            )
        case .seekRecovery:
            session.seekRecoveryCount += 1
            if event.message?.contains("recovered=false") == true {
                session.seekRecoverySlowCount += 1
            } else if let recoveryMilliseconds = Self.firstMilliseconds(in: event.message) {
                session.lastSeekRecoveryMilliseconds = recoveryMilliseconds
                if recoveryMilliseconds >= 1_250 {
                    session.seekRecoverySlowCount += 1
                }
            }
            session.seekRecoveryMessage = Self.appendDiagnosticMessage(
                session.seekRecoveryMessage,
                event.message,
                maxParts: 4
            )
        case .speedBoost:
            let message = event.message ?? ""
            if message.hasPrefix("event=begin") || message.hasPrefix("begin ") {
                session.speedBoostCount += 1
            }
            if message.contains("interrupted=true") {
                session.speedBoostInterruptionCount += 1
            }
            session.speedBoostMessage = Self.appendDiagnosticMessage(
                session.speedBoostMessage,
                event.message,
                maxParts: 4
            )
        case .playbackRecovery:
            session.playbackRecoveryCount += 1
            if event.message?.contains("status=failed") == true
                || event.message?.contains("status=ignored") == true
                || event.message?.contains("status=exhausted") == true
            {
                session.playbackRecoveryFailureCount += 1
            }
            session.playbackRecoveryMessage = Self.appendDiagnosticMessage(
                session.playbackRecoveryMessage,
                event.message,
                maxParts: 6
            )
        case .failed:
            session.failureMessage = event.message
        }

        session.startupGapMessage = Self.startupGapMessage(for: session)
        if session.startupBreakdownMessage != nil {
            session.startupBreakdownMessage = Self.startupBreakdownMessage(
                baseMessage: session.startupBreakdownMessage,
                for: session
            )
        }
        appendTimelineEvent(event, to: &session)

        sessionsByID[event.metricsID] = session
        sessions = sessionsByID.values
            .sorted { $0.lastUpdatedAt > $1.lastUpdatedAt }
            .prefix(maxSessionCount)
            .map { $0 }
        let keptIDs = Set(sessions.map(\.id))
        sessionsByID = sessionsByID.filter { keptIDs.contains($0.key) }
        schedulePersist()
        schedulePerformanceCopyLogIfNeeded(after: event.kind, for: session)
    }

    private func schedulePerformanceCopyLogIfNeeded(
        after kind: PlayerPerformanceEvent.Kind,
        for session: PlayerPerformanceSession
    ) {
        guard Self.shouldSchedulePerformanceCopyLog(after: kind),
            UserDefaults.standard.bool(forKey: Self.performanceOverlayEnabledKey),
            Self.hasPerformanceCopyPayload(session)
        else { return }

        let metricsID = session.id
        let signature = Self.performanceCopyLogSignature(for: session)
        guard lastPerformanceCopyLogSignatures[metricsID] != signature else { return }

        performanceCopyLogTasks[metricsID]?.cancel()
        performanceCopyLogTasks[metricsID] = Task { @MainActor [weak self, metricsID] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled,
                let self,
                UserDefaults.standard.bool(forKey: Self.performanceOverlayEnabledKey),
                let latestSession = self.sessionsByID[metricsID],
                Self.hasPerformanceCopyPayload(latestSession)
            else { return }

            let latestSignature = Self.performanceCopyLogSignature(for: latestSession)
            guard self.lastPerformanceCopyLogSignatures[metricsID] != latestSignature else {
                self.performanceCopyLogTasks[metricsID] = nil
                return
            }

            self.lastPerformanceCopyLogSignatures[metricsID] = latestSignature
            Self.logPerformanceCopyText(
                metricsID: metricsID,
                text: PlayerPerformanceCopyTextFormatter.performanceCopyText(
                    metricsID: metricsID,
                    session: latestSession
                )
            )
            self.performanceCopyLogTasks[metricsID] = nil
        }
    }

    private static func shouldSchedulePerformanceCopyLog(after kind: PlayerPerformanceEvent.Kind) -> Bool {
        switch kind {
        case .firstFrame, .startupBreakdown, .startupScheduler, .network, .manifestStage, .failed:
            return true
        default:
            return false
        }
    }

    private static func hasPerformanceCopyPayload(_ session: PlayerPerformanceSession) -> Bool {
        session.firstFrameTotalMilliseconds != nil
            || session.firstFramePlayerMilliseconds != nil
            || !session.recentStartupSamples.isEmpty
            || session.failureMessage != nil
    }

    private static func performanceCopyLogSignature(for session: PlayerPerformanceSession) -> String {
        var parts: [String] = []
        parts.append(session.firstFrameAt.map { String($0.timeIntervalSince1970) } ?? "-")
        parts.append(session.recentStartupSamples.last?.id.uuidString ?? "-")
        parts.append(session.firstFrameTotalMilliseconds.map { String($0) } ?? "-")
        parts.append(session.firstFramePlayerMilliseconds.map { String($0) } ?? "-")
        parts.append(session.playURLMilliseconds.map { String($0) } ?? "-")
        parts.append(session.prepareMilliseconds.map { String($0) } ?? "-")
        parts.append(session.startupQuality.map { String($0) } ?? "-")
        parts.append(session.startupPlayerCreationMode ?? "-")
        parts.append(session.piliPlusStylePlayURLSelectionExperimentEnabled.map(String.init) ?? "-")
        parts.append(session.relatedEarlyPlayURLPrefetchExperimentEnabled.map(String.init) ?? "-")
        parts.append(session.relatedStartupPackageWarmupExperimentEnabled.map(String.init) ?? "-")
        parts.append(session.startupGapMessage ?? "-")
        parts.append(session.startupBreakdownMessage ?? "-")
        parts.append(session.hlsStartupMessage ?? "-")
        parts.append(session.startupSchedulerMessage ?? "-")
        parts.append(session.manifestStageMessage ?? "-")
        parts.append(session.failureMessage ?? "-")
        return parts.joined(separator: "\n")
    }

    private static func logPerformanceCopyText(metricsID: String, text: String) {
        let lines =
            text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        PlayerMetricsLog.logger.notice(
            "perfCopyBegin metricsID=\(metricsID, privacy: .public) lines=\(lines.count, privacy: .public)"
        )
        for (lineIndex, line) in lines.enumerated() {
            let chunks = chunks(for: line, maxLength: 700)
            for (chunkIndex, chunk) in chunks.enumerated() {
                PlayerMetricsLog.logger.notice(
                    "perfCopyLine metricsID=\(metricsID, privacy: .public) line=\(lineIndex + 1, privacy: .public) chunk=\(chunkIndex + 1, privacy: .public)/\(chunks.count, privacy: .public) text=\(chunk, privacy: .public)"
                )
            }
        }
        PlayerMetricsLog.logger.notice(
            "perfCopyEnd metricsID=\(metricsID, privacy: .public)"
        )
    }

    private static func chunks(for text: String, maxLength: Int) -> [String] {
        guard text.count > maxLength else { return [text] }
        var chunks: [String] = []
        var start = text.startIndex
        while start < text.endIndex {
            let end = text.index(start, offsetBy: maxLength, limitedBy: text.endIndex) ?? text.endIndex
            chunks.append(String(text[start..<end]))
            start = end
        }
        return chunks
    }

    private func loadPersistedSessions() {
        guard let data = UserDefaults.standard.data(forKey: Self.persistedSessionsKey),
            let persisted = try? JSONDecoder().decode([PlayerPerformancePersistedSession].self, from: data)
        else { return }

        let cutoff = Date().addingTimeInterval(-Self.persistedSessionMaxAge)
        let restoredSessions =
            persisted
            .filter { $0.lastUpdatedAt >= cutoff }
            .sorted { $0.lastUpdatedAt > $1.lastUpdatedAt }
            .prefix(maxSessionCount)
            .map { $0.makeSession() }

        sessions = Array(restoredSessions)
        sessionsByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
    }

    private func schedulePersist() {
        persistTask?.cancel()
        persistGeneration &+= 1
        let generation = persistGeneration
        let cutoff = Date().addingTimeInterval(-Self.persistedSessionMaxAge)
        let persistedSessions =
            sessions
            .filter { Self.hasStartupSample($0) && $0.lastUpdatedAt >= cutoff }
            .prefix(maxPersistedSessionCount)
            .map(PlayerPerformancePersistedSession.init(session:))

        persistTask = Task { @MainActor [weak self, persistedSessions, generation] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled,
                let self,
                self.persistGeneration == generation
            else { return }

            await PlayerPerformanceSessionPersistenceWriter.shared.persist(
                persistedSessions,
                forKey: Self.persistedSessionsKey
            )

            guard !Task.isCancelled,
                self.persistGeneration == generation
            else { return }
            self.persistTask = nil
        }
    }

    private static func milliseconds(from start: Date, to end: Date) -> Int {
        Int((end.timeIntervalSince(start) * 1000).rounded())
    }

    private func appendTimelineEvent(_ event: PlayerPerformanceEvent, to session: inout PlayerPerformanceSession) {
        let startedAt =
            session.openedAt
            ?? session.detailStartedAt
            ?? session.playURLStartedAt
            ?? session.playerCreatedAt
            ?? event.date
        let message = event.message?
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        session.timeline.append(
            PlayerPerformanceTimelineEntry(
                date: event.date,
                elapsedMilliseconds: Self.milliseconds(from: startedAt, to: event.date),
                title: event.kind.title,
                message: message?.isEmpty == true ? nil : message
            )
        )
        if session.timeline.count > 18 {
            session.timeline.removeFirst(session.timeline.count - 18)
        }
    }

    private func shouldResetPlaybackAttempt(
        for kind: PlayerPerformanceEvent.Kind,
        session: PlayerPerformanceSession
    ) -> Bool {
        switch kind {
        case .routeOpen:
            return true
        case .detailLoadStart:
            return session.detailStartedAt != nil
                || session.playURLStartedAt != nil
                || session.playerCreatedAt != nil
                || session.prepareStartedAt != nil
                || session.playRequestedAt != nil
                || session.firstFrameTotalMilliseconds != nil
                || session.failureMessage != nil
        case .playURLStart:
            return session.playURLStartedAt != nil
                || session.playerCreatedAt != nil
                || session.prepareStartedAt != nil
                || session.playRequestedAt != nil
                || session.firstFrameTotalMilliseconds != nil
                || session.failureMessage != nil
        default:
            return false
        }
    }

    private func resetPlaybackAttempt(_ session: inout PlayerPerformanceSession) {
        session.openedAt = nil
        session.detailStartedAt = nil
        session.playURLStartedAt = nil
        session.playURLLoadedAt = nil
        session.playerCreatedAt = nil
        session.prepareStartedAt = nil
        session.prepareReturnedAt = nil
        session.playRequestedAt = nil
        session.firstFrameAt = nil
        session.eventCount = 0
        session.detailLoadMilliseconds = nil
        session.playURLMilliseconds = nil
        session.mediaPreparedMilliseconds = nil
        session.prepareMilliseconds = nil
        session.resumeApplyMilliseconds = nil
        session.resumeRecoveryCount = 0
        session.resumeRecoverySlowCount = 0
        session.lastResumeRecoveryMilliseconds = nil
        session.firstFrameTotalMilliseconds = nil
        session.firstFramePlayerMilliseconds = nil
        session.bufferCount = 0
        session.seekCount = 0
        session.seekRecoveryCount = 0
        session.seekRecoverySlowCount = 0
        session.lastSeekRecoveryMilliseconds = nil
        session.speedBoostCount = 0
        session.speedBoostInterruptionCount = 0
        session.lastBufferMessage = nil
        session.networkMessage = nil
        session.hlsStartupMessage = nil
        session.startupSchedulerMessage = nil
        session.accessLogMessage = nil
        session.decodeLogMessage = nil
        session.observedBitrateKilobitsPerSecond = nil
        session.indicatedBitrateKilobitsPerSecond = nil
        session.accessLogStallCount = nil
        session.accessLogTransferMilliseconds = nil
        session.accessLogBytesTransferred = nil
        session.accessLogMediaRequestCount = nil
        session.mediaCacheMessage = nil
        session.manifestStageMessage = nil
        session.qualitySupplementMessage = nil
        session.resumeDecisionMessage = nil
        session.resumeRecoveryMessage = nil
        session.seekMessage = nil
        session.seekRecoveryMessage = nil
        session.speedBoostMessage = nil
        session.playbackRecoveryCount = 0
        session.playbackRecoveryFailureCount = 0
        session.playbackRecoveryMessage = nil
        session.cdnHostMessage = nil
        session.selectedQualityMessage = nil
        session.detailSourceMessage = nil
        session.prepareStageMessage = nil
        session.startupGapMessage = nil
        session.startupBreakdownMessage = nil
        session.startupQuality = nil
        session.startupTargetQuality = nil
        session.startupCodec = nil
        session.startupDecisionMessage = nil
        session.startupCDNKey = nil
        session.startupCDNTitle = nil
        session.startupNetworkKey = nil
        session.startupNetworkTitle = nil
        session.avPlayerStartupPathOptimizationExperimentEnabled = nil
        session.startupPlayerCreationMode = nil
        session.piliPlusStylePlayURLSelectionExperimentEnabled = nil
        session.relatedEarlyPlayURLPrefetchExperimentEnabled = nil
        session.relatedStartupPackageWarmupExperimentEnabled = nil
        session.startupSource = nil
        session.startupPlayURLSource = nil
        session.startupPlayURLVariantCount = nil
        session.startupRoutePlanState = nil
        session.startupRoutePlanMilliseconds = nil
        session.startupRoutePrebuildState = nil
        session.startupRoutePrebuildMilliseconds = nil
        session.startupPackageRoutePlanState = nil
        session.startupPackageRangeState = nil
        session.startupRangeWarmState = nil
        session.startupRangeWarmMilliseconds = nil
        session.startupPackageMessage = nil
        session.lastSeekBufferReadyCoveragePercent = nil
        session.failureMessage = nil
        session.timeline.removeAll()
    }

    private static func startupGapMessage(for session: PlayerPerformanceSession) -> String? {
        var parts: [String] = []
        appendGap(
            &parts,
            label: "open>detail",
            start: session.openedAt,
            end: session.detailStartedAt
        )
        appendGap(
            &parts,
            label: "detail>url",
            start: session.detailStartedAt,
            end: session.playURLStartedAt
        )
        appendGap(
            &parts,
            label: "url>player",
            start: session.playURLLoadedAt,
            end: session.playerCreatedAt
        )
        appendGap(
            &parts,
            label: "player>prepare",
            start: session.playerCreatedAt,
            end: session.prepareStartedAt
        )
        appendGap(
            &parts,
            label: "prepare>play",
            start: session.prepareReturnedAt,
            end: session.playRequestedAt
        )
        appendGap(
            &parts,
            label: "play>frame",
            start: session.playRequestedAt,
            end: session.firstFrameAt
        )
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " | ")
    }

    private static func appendGap(
        _ parts: inout [String],
        label: String,
        start: Date?,
        end: Date?
    ) {
        guard let start, let end else { return }
        let milliseconds = max(Self.milliseconds(from: start, to: end), 0)
        parts.append("\(label) \(milliseconds)ms")
    }

    private static func appendStartupSampleIfNeeded(
        event: PlayerPerformanceEvent,
        tokens: [String: String],
        message: String,
        to session: inout PlayerPerformanceSession
    ) {
        guard tokenValue(for: "ksStartup", in: tokens) == "firstFrame" else { return }
        let sample = PlayerStartupPerformanceSample(
            date: event.date,
            firstFrameTotalMilliseconds: session.firstFrameTotalMilliseconds,
            firstFramePlayerMilliseconds: millisecondsValue(for: "firstFrame", in: tokens)
                ?? session.firstFramePlayerMilliseconds,
            prepareToFrameMilliseconds: millisecondsValue(for: "prepareToFrame", in: tokens),
            playToFrameMilliseconds: millisecondsValue(for: "playToFrame", in: tokens),
            endpointMilliseconds: millisecondsValue(for: "endpoint", in: tokens),
            layerMilliseconds: millisecondsValue(for: "layer", in: tokens),
            readyMilliseconds: millisecondsValue(for: "ready", in: tokens),
            renderMilliseconds: millisecondsValue(for: "renderAfterReady", in: tokens),
            decodedMilliseconds: millisecondsValue(for: "decodedFrame", in: tokens),
            ksRenderMilliseconds: millisecondsValue(for: "ksRender", in: tokens),
            ffmpegMilliseconds: millisecondsValue(for: "ffmpeg", in: tokens),
            ffmpegOpenMilliseconds: millisecondsValue(for: "ffOpen", in: tokens),
            ffmpegFindMilliseconds: millisecondsValue(for: "ffFind", in: tokens),
            ffmpegReadyMilliseconds: millisecondsValue(for: "ffReady", in: tokens),
            frameDecodedMilliseconds: millisecondsValue(for: "frameDecoded", in: tokens),
            frameFetchedMilliseconds: millisecondsValue(for: "frameFetched", in: tokens),
            displayEnqueueMilliseconds: millisecondsValue(for: "displayEnq", in: tokens),
            metalDrawMilliseconds: millisecondsValue(for: "metalDraw", in: tokens),
            probe: tokenValue(for: "probe", in: tokens),
            codec: tokenValue(for: "codec", in: tokens),
            frameRate: tokenValue(for: "fps", in: tokens),
            resolution: tokenValue(for: "res", in: tokens),
            breakdownMessage: message
        )
        session.recentStartupSamples.append(sample)
        if session.recentStartupSamples.count > 5 {
            session.recentStartupSamples.removeFirst(session.recentStartupSamples.count - 5)
        }
    }

    private static func startupBreakdownMessage(baseMessage: String?, for session: PlayerPerformanceSession) -> String?
    {
        guard let baseMessage, !baseMessage.isEmpty else { return nil }
        var tokens = keyValueTokens(in: baseMessage)
        appendMillisecondsToken(
            "prepareToPlay",
            from: session.prepareReturnedAt,
            to: session.playRequestedAt,
            tokens: &tokens
        )
        appendMillisecondsToken(
            "playToFrame",
            from: session.playRequestedAt,
            to: session.firstFrameAt,
            tokens: &tokens
        )
        appendMillisecondsToken(
            "prepareToFrame",
            from: session.prepareReturnedAt,
            to: session.firstFrameAt,
            tokens: &tokens
        )
        guard !tokens.isEmpty else { return baseMessage }

        let existingKeys = Set(tokens.keys)
        var orderedKeys =
            baseMessage
            .split(separator: " ")
            .compactMap { token -> String? in
                let parts = token.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { return nil }
                return String(parts[0])
            }
        for key in ["prepareToPlay", "playToFrame", "prepareToFrame"] where existingKeys.contains(key) {
            if !orderedKeys.contains(key) {
                orderedKeys.append(key)
            }
        }

        var seenKeys = Set<String>()
        let orderedParts = orderedKeys.compactMap { key -> String? in
            guard seenKeys.insert(key).inserted,
                let value = tokens[key],
                !value.isEmpty
            else { return nil }
            return "\(key)=\(value)"
        }
        return orderedParts.isEmpty ? baseMessage : orderedParts.joined(separator: " ")
    }

    private static func appendMillisecondsToken(
        _ key: String,
        from start: Date?,
        to end: Date?,
        tokens: inout [String: String]
    ) {
        guard tokens[key] == nil, let start, let end else { return }
        let milliseconds = max(Self.milliseconds(from: start, to: end), 0)
        tokens[key] = "\(milliseconds)ms"
    }

    private static func updatePlayURLStartupFields(_ message: String, in session: inout PlayerPerformanceSession) {
        let tokens = keyValueTokens(in: message)
        if let source = tokenValue(for: "source", in: tokens), source != "-" {
            session.startupPlayURLSource = source
            session.startupSource = session.startupSource ?? source
        } else if let source = legacyPlayURLSource(in: message) {
            session.startupPlayURLSource = source
            session.startupSource = session.startupSource ?? source
        }

        if let variantCount = integerValue(for: "variants", in: tokens)
            ?? legacyFirstInteger(in: message)
        {
            session.startupPlayURLVariantCount = variantCount
        }
    }

    private static func updateManifestStartupFields(_ message: String, in session: inout PlayerPerformanceSession) {
        let tokens = keyValueTokens(in: message)
        updateStartupCodec(tokenValue(for: "codec", in: tokens), in: &session)

        if message.hasPrefix("startupWarmWait"),
            let mode = tokenValue(for: "mode", in: tokens)
        {
            session.startupPlayerCreationMode = mode
        }

        if message.hasPrefix("startupPackage") {
            session.startupPackageMessage = message
            if let routePlan = tokenValue(for: "routePlan", in: tokens) {
                session.startupPackageRoutePlanState = routePlan
            }
            if let ranges = tokenValue(for: "ranges", in: tokens) {
                session.startupPackageRangeState = ranges
            }
        }

        if let bridgeState = tokenValue(for: "bridge", in: tokens), bridgeState != "steadyBuffer" {
            session.startupRoutePlanState = bridgeState
            session.startupRoutePlanMilliseconds =
                millisecondsValue(for: "total", in: tokens)
                ?? session.startupRoutePlanMilliseconds
        }

        if let routePrebuildState = tokenValue(for: "routePrebuild", in: tokens) {
            session.startupRoutePrebuildState = routePrebuildState
            session.startupRoutePrebuildMilliseconds =
                firstMilliseconds(in: message)
                ?? session.startupRoutePrebuildMilliseconds
        }

        if let warmValue = tokenValue(for: "startupWarm", in: tokens) {
            session.startupRangeWarmState = warmValue == "skip" ? "skip" : "ready"
            session.startupRangeWarmMilliseconds =
                millisecondsValue(for: "startupWarm", in: tokens)
                ?? session.startupRangeWarmMilliseconds
        }
    }

    private static func updateStartupCodec(_ value: String?, in session: inout PlayerPerformanceSession) {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty,
            value != "-"
        else { return }
        session.startupCodec = session.startupCodec ?? value
    }

    private static func updateStartupQualityFields(_ message: String, in session: inout PlayerPerformanceSession) {
        guard message.hasPrefix("startupQuality") else { return }

        if let transition = qualityTransition(in: message) {
            session.startupQuality = transition.from
            session.startupTargetQuality = transition.to
        }

        session.startupDecisionMessage = appendDiagnosticMessage(
            session.startupDecisionMessage,
            message,
            maxParts: 4
        )
    }

    private static func legacyPlayURLSource(in message: String) -> String? {
        if message.contains("pending cache") {
            return "pendingCache"
        }
        if message.contains("缓存档位") {
            return "playableCache"
        }
        if message.contains("deferred cache") {
            return "cacheFallbackAfterNetworkFailure"
        }
        if message.contains("stale playable cache") {
            return "stalePlayableCacheAfterNetworkFailure"
        }
        if message.contains("memory playable cache") {
            return "memoryPlayableCacheAfterNetworkFailure"
        }
        if message.contains("recovered") {
            return message.split(separator: " ").first.map(String.init)
        }
        if message.contains("可播放档位") {
            return "networkOrCache"
        }
        return nil
    }

    private static func qualityTransition(in message: String) -> (from: Int, to: Int)? {
        let pattern = #"q?(\d+)->q?(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(
                in: message,
                range: NSRange(message.startIndex..., in: message)
            ),
            let fromRange = Range(match.range(at: 1), in: message),
            let toRange = Range(match.range(at: 2), in: message),
            let from = Int(message[fromRange]),
            let to = Int(message[toRange])
        else { return nil }
        return (from, to)
    }

    private static func legacyFirstInteger(in message: String) -> Int? {
        let pattern = #"(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(
                in: message,
                range: NSRange(message.startIndex..., in: message)
            ),
            let range = Range(match.range(at: 1), in: message)
        else { return nil }
        return Int(message[range])
    }

    private static func firstMilliseconds(in message: String?) -> Int? {
        guard let message else { return nil }
        let pattern = #"(\d+(?:\.\d+)?)ms"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(
                in: message,
                range: NSRange(message.startIndex..., in: message)
            ),
            let range = Range(match.range(at: 1), in: message),
            let value = Double(message[range])
        else { return nil }
        return Int(value.rounded())
    }

    private static func host(in message: String) -> String? {
        let pattern = #"host=([^\s]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(
                in: message,
                range: NSRange(message.startIndex..., in: message)
            ),
            let range = Range(match.range(at: 1), in: message)
        else { return nil }
        return String(message[range])
    }

    private static func keyValueTokens(in message: String) -> [String: String] {
        var tokens: [String: String] = [:]
        for rawPart in message.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }) {
            guard let separatorIndex = rawPart.firstIndex(of: "=") else { continue }
            let rawKey = String(rawPart[..<separatorIndex])
            let rawValue = String(rawPart[rawPart.index(after: separatorIndex)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawKey.isEmpty, !rawValue.isEmpty else { continue }
            tokens[rawKey] = rawValue
            tokens[rawKey.lowercased()] = rawValue
        }
        return tokens
    }

    private static func integerValue(for key: String, in tokens: [String: String]) -> Int? {
        guard let value = tokenValue(for: key, in: tokens) else { return nil }
        return Int(value)
    }

    private static func integer64Value(for key: String, in tokens: [String: String]) -> Int64? {
        guard let value = tokenValue(for: key, in: tokens) else { return nil }
        return Int64(value)
    }

    private static func millisecondsValue(for key: String, in tokens: [String: String]) -> Int? {
        guard
            var value = tokenValue(for: key, in: tokens)?
                .lowercased()
                .replacingOccurrences(of: ",", with: ""),
            value != "n/a",
            value != "-"
        else { return nil }

        let multiplier: Double
        if value.hasSuffix("ms") {
            value.removeLast(2)
            multiplier = 1
        } else if value.hasSuffix("s") {
            value.removeLast()
            multiplier = 1_000
        } else {
            multiplier = 1
        }
        guard let number = Double(value) else { return nil }
        return Int((number * multiplier).rounded())
    }

    private static func percentageValue(for key: String, in tokens: [String: String]) -> Int? {
        guard
            var value = tokenValue(for: key, in: tokens)?
                .lowercased()
                .replacingOccurrences(of: ",", with: ""),
            value != "n/a",
            value != "-"
        else { return nil }
        if value.hasSuffix("%") {
            value.removeLast()
        }
        guard let number = Double(value) else { return nil }
        let normalized = number <= 1 ? number * 100 : number
        return Int(normalized.rounded())
    }

    private static func tokenValue(for key: String, in tokens: [String: String]) -> String? {
        tokens[key] ?? tokens[key.lowercased()]
    }

    private static func cdnTitle(for key: String) -> String {
        PlaybackCDNPreference(rawValue: key)?.title ?? key
    }

    private static func networkTitle(for key: String) -> String {
        switch key {
        case "wifi":
            return "Wi-Fi"
        case "cellular":
            return "蜂窝网络"
        case "constrained":
            return "受限网络"
        case "unknown":
            return "未知网络"
        default:
            return key
        }
    }

    private static func appendDiagnosticMessage(_ current: String?, _ next: String?, maxParts: Int) -> String? {
        guard let next, !next.isEmpty else { return current }
        var parts = current?.components(separatedBy: " | ") ?? []
        parts.removeAll { $0 == next }
        parts.append(next)
        if parts.count > maxParts {
            parts.removeFirst(parts.count - maxParts)
        }
        return parts.joined(separator: " | ")
    }

    private static func appendManifestStageMessage(_ current: String?, _ next: String?) -> String? {
        guard let next, !next.isEmpty else { return current }
        let pinnedKeys: Set<String> = [
            "startupWarmWait",
            "startupPrebuild",
            "ffDemuxWarm",
            "startupPackage",
            "prepareWarm",
        ]
        let nextKey = diagnosticKey(in: next)
        var parts = current?.components(separatedBy: " | ") ?? []
        parts.removeAll { part in
            if part == next { return true }
            guard let nextKey, pinnedKeys.contains(nextKey) else { return false }
            return diagnosticKey(in: part) == nextKey
        }
        parts.append(next)
        while parts.count > 12 {
            if let removableIndex = parts.firstIndex(where: { part in
                guard let key = diagnosticKey(in: part) else { return true }
                return !pinnedKeys.contains(key)
            }) {
                parts.remove(at: removableIndex)
            } else {
                parts.removeFirst()
            }
        }
        return parts.joined(separator: " | ")
    }

    private static func diagnosticKey(in message: String) -> String? {
        guard let firstToken = message.split(separator: " ").first,
            let key = firstToken.split(separator: "=", maxSplits: 1).first,
            !key.isEmpty
        else { return nil }
        return String(key)
    }
}

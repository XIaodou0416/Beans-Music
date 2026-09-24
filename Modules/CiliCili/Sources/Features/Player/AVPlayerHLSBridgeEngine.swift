import AVFoundation
import AVKit
import CryptoKit
import CoreImage
import Network
import OSLog
import SwiftUI
import UIKit

@MainActor
final class AVPlayerHLSBridgeEngine: PlayerRenderingEngine {
    private static let interactiveSeekTolerance = CMTime(seconds: 0.35, preferredTimescale: 600)
    private static let seekProtectionReleaseDelayNanoseconds: UInt64 = 900_000_000
    private static let hdrFirstFrameTimeoutNanoseconds: UInt64 = 11_000_000_000
    private static let terminalStallDelayNanoseconds: UInt64 = 14_000_000_000
    private static let itemReadinessTimeoutNanoseconds: UInt64 = 14_000_000_000
    private static let loadedRangeContinuityTolerance: TimeInterval = 0.12

    private enum PrepareReadinessError: LocalizedError {
        case timedOut

        var errorDescription: String? {
            "AVPlayer 等待媒体就绪超时"
        }
    }

    private let player = AVPlayer()
    private weak var viewModel: PlayerStateViewModel?
    nonisolated(unsafe) private var itemEndObserver: Any?
    nonisolated(unsafe) private var itemFailedObserver: Any?
    nonisolated(unsafe) private var itemStalledObserver: Any?
    nonisolated(unsafe) private var itemAccessLogObserver: Any?
    private var itemReadinessTimeoutTask: Task<Void, Never>?
    private var firstFrameWatchdogTask: Task<Void, Never>?
    private var firstFrameWatchdogGeneration = 0
    private var playerObservers: [NSKeyValueObservation] = []
    private var itemObservers: [NSKeyValueObservation] = []
    private var layerReadyForDisplayObserver: NSKeyValueObservation?
    private var controllerReadyForDisplayObserver: NSKeyValueObservation?
    nonisolated(unsafe) private var periodicTimeObserver: Any?
    private let videoFrameContext = CIContext()
    private weak var surfaceView: UIView?
    private var playerLayer: AVPlayerLayer?
    private weak var playerViewController: AVPlayerViewController?
    private let nativeDolbyVideoOverlay = NativeDolbyVideoOverlayRenderer()
    private var nativeDolbyVideoSyncTask: Task<Void, Never>?
    private var lastDisplayDynamicRangePolicySummary: String?
    private var playerItem: AVPlayerItem?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var lastVideoFrameImage: UIImage?
    private var recoveryFrameCacheTask: Task<Void, Never>?
    private var source: PlayerStreamSource?
    private var hlsBridge: LocalHLSBridge?
    private var liveHLSProxy: LocalLiveHLSProxy?
    private var mediaTimeOffset: TimeInterval = 0
    private var retainedAssets: [AVAsset] = []
    private var currentRate: Float = 1
    private var wantsPlayback = false
    private var didReportFirstFrame = false
    private var lastPlaybackState: PlayerEnginePlaybackState = .idle
    private var videoGravity: AVLayerVideoGravity = .resizeAspect
    private var isDirectLiveHLS = false
    private var didSeekDirectLiveHLS = false
    private var isPerformingSeek = false
    private var seekGeneration = 0
    private var isSeekProtectionActive = false
    private var lastSeekFinishedAt: CFTimeInterval?
    private var seekProtectionReleaseTask: Task<Void, Never>?
    private var seekProtectionTargetTime: TimeInterval?
    private var seekProtectionAppliedAt: CFTimeInterval?
    private var seekWarmupTask: Task<Void, Never>?
    private var seekWarmupGeneration = 0
    private var automaticallyWaitsBeforeSeekProtection: Bool?
    private var terminalStallTask: Task<Void, Never>?
    private var terminalStallGeneration = 0
    private var isStartupFastStartActive = false
    private var manualPreferredPeakBitRate: Double?
    private var lastRecordedAccessLogStallCount = 0
    private var lastPlaybackFailureReason: HLSBridgeFailureReason?
    private var playbackGeneration = 0
    private var playbackFailureRecoveryAttempts: [String: Int] = [:]
    private var isPlaybackFailureRecoveryInProgress = false
    private var isStopped = true
    private var targetVolume: Float = 1
    private var targetMuted = false
    private var isTemporaryAudioSuppressed = false
    private var isPictureInPictureEnabled = false
    private var contentOverlay: AnyView?
    private var contentOverlayHostingController: UIHostingController<AnyView>?
    private weak var contentOverlayContainerView: UIView?
    private var pendingSurfaceDetachTask: Task<Void, Never>?
    private var shouldPrerollPausedRecoveryAfterSeek = false

    var hasMedia: Bool {
        !isStopped && player.currentItem != nil
    }

    var needsMediaRecovery: Bool {
        guard let item = player.currentItem else { return false }
        return item.status == .failed
    }

    var playbackErrorMessage: String? {
        player.currentItem?.error?.localizedDescription
    }

    var lastFailureReason: HLSBridgeFailureReason? {
        lastPlaybackFailureReason
    }

    var supportsPictureInPicture: Bool {
        false
    }

    var isPictureInPictureActive: Bool {
        false
    }

    var usesNativePlaybackControls: Bool {
        true
    }

    var diagnostics: PlayerEngineDiagnostics {
        let isAudioOnly = source?.playbackContentMode == .audioOnly
        return PlayerEngineDiagnostics(
            engineName: "AVPlayer",
            playbackContentMode: source?.playbackContentMode ?? .video,
            decodePath: .avPlayer,
            playbackPipeline: diagnosticsPlaybackPipeline,
            codec: isAudioOnly ? source?.audioStream?.codecLabel : source?.videoStream?.codecLabel,
            videoCodecIdentifier: isAudioOnly ? nil : source?.videoStream?.codecs,
            audioCodecIdentifier: source?.audioStream?.codecs,
            videoCodecid: isAudioOnly ? nil : source?.videoStream?.codecid,
            audioCodecid: source?.audioStream?.codecid,
            resolution: isAudioOnly ? nil : source?.videoStream?.resolutionLabel,
            frameRate: isAudioOnly ? nil : source?.videoStream?.displayFrameRate,
            bandwidth: isAudioOnly ? source?.audioStream?.bandwidth : source?.videoStream?.bandwidth,
            dynamicRange: isAudioOnly ? .sdr : (source?.dynamicRange ?? .sdr),
            isDASH: source?.audioURL != nil,
            usesLocalHLSBridge: hlsBridge != nil || liveHLSProxy != nil,
            localPlaylistURL: diagnosticsLocalPlaylistURL,
            sourceVideoHost: isAudioOnly ? nil : source?.videoURL?.host,
            sourceAudioHost: source?.audioURL?.host,
            cellularBiliTrafficCompatibility: CellularBiliTrafficCompatibilityExperiment.currentState,
            hlsVideoVariantCount: hlsBridge?.videoVariantCount ?? 0,
            hlsVideoVariantQualities: hlsBridge?.videoVariantQualities ?? [],
            hlsVideoVariantDetails: diagnosticVideoVariantDetails,
            preferredForwardBufferDuration: player.currentItem?.preferredForwardBufferDuration,
            maxBufferDuration: nil,
            asynchronousDecompressionEnabled: false,
            hardwareDecodeRequested: isAudioOnly
                ? source?.audioStream != nil
                : (source?.videoStream != nil || source?.audioURL != nil),
            isHardwareDecodeCompatible: isAudioOnly
                ? source?.audioStream?.isHardwareDecodingCompatibleAudio
                : source?.videoStream?.isHardwareDecodingCompatibleVideo,
            environmentSummary: PlaybackEnvironment.current.diagnosticSummary,
            nativeHDRVideoLayerState: nativeDolbyVideoOverlay.stateRawValue,
            nativeHDRVideoLayerSummary: nativeDolbyVideoOverlay.diagnosticSummary
        )
    }

    var presentationSize: CGSize {
        let size = player.currentItem?.presentationSize ?? .zero
        guard size.width > 0, size.height > 0 else { return .zero }
        return size
    }

    private var diagnosticVideoVariantDetails: [String] {
        var details = hlsBridge?.videoVariantDetails ?? []
        if let overlaySummary = nativeDolbyVideoOverlay.diagnosticSummary {
            details.append("nativeHDR \(overlaySummary)")
        }
        return details
    }

    private var diagnosticsPlaybackPipeline: PlayerEngineDiagnostics.PlaybackPipeline {
        if hlsBridge != nil {
            return .dashLocalHLS
        }
        if liveHLSProxy != nil {
            return .liveHLSProxy
        }
        return .directAVURLAsset
    }

    private var diagnosticsLocalPlaylistURL: String? {
        hlsBridge?.masterPlaylistURL.absoluteString
            ?? liveHLSProxy?.playlistURL.absoluteString
    }

    var volume: Float {
        targetVolume
    }

    var isMuted: Bool {
        targetMuted
    }

    var onPlaybackStateChange: (@MainActor (PlayerEnginePlaybackState) -> Void)?
    var onPlaybackIntentChange: (@MainActor (Bool) -> Void)?
    var onLoadingProgressChange: (@MainActor (Double) -> Void)?
    var onFirstFrame: (@MainActor (TimeInterval) -> Void)?

#if DEBUG
    var debugPlayerIdentity: ObjectIdentifier? {
        ObjectIdentifier(player)
    }

    var debugPlayerItemIdentity: ObjectIdentifier? {
        player.currentItem.map { ObjectIdentifier($0) }
    }
#endif

    init() {
        nativeDolbyVideoOverlay.onReadyForDisplay = { [weak self] in
            self?.handleNativeDolbyVideoOverlayReady()
        }
        nativeDolbyVideoOverlay.onReadyToPlay = { [weak self] in
            self?.handleNativeDolbyVideoOverlayReadyToPlay()
        }
        observePlayerState()
    }

    deinit {
        pendingSurfaceDetachTask?.cancel()
        itemObservers.removeAll()
        layerReadyForDisplayObserver = nil
        controllerReadyForDisplayObserver = nil
        if let itemEndObserver {
            NotificationCenter.default.removeObserver(itemEndObserver)
        }
        if let itemFailedObserver {
            NotificationCenter.default.removeObserver(itemFailedObserver)
        }
        if let itemStalledObserver {
            NotificationCenter.default.removeObserver(itemStalledObserver)
        }
        if let itemAccessLogObserver {
            NotificationCenter.default.removeObserver(itemAccessLogObserver)
        }
        if let periodicTimeObserver {
            player.removeTimeObserver(periodicTimeObserver)
        }
        nativeDolbyVideoSyncTask?.cancel()
        let nativeDolbyVideoOverlay = nativeDolbyVideoOverlay
        Task { @MainActor in
            nativeDolbyVideoOverlay.stop()
        }
        seekProtectionReleaseTask?.cancel()
        seekWarmupTask?.cancel()
        terminalStallTask?.cancel()
        itemReadinessTimeoutTask?.cancel()
        firstFrameWatchdogTask?.cancel()
        recoveryFrameCacheTask?.cancel()
    }

    func attachSurface(_ surface: UIView) {
        pendingSurfaceDetachTask?.cancel()
        pendingSurfaceDetachTask = nil
        surfaceView = surface
        if let playerViewController {
            configureNativePlaybackController(playerViewController)
            removePlayerLayer()
        } else {
            let layer = ensurePlayerLayer(in: surface)
            layer.player = player
            nativeDolbyVideoOverlay.attach(to: surface, gravity: videoGravity)
        }
        refreshSurfaceLayout()
    }

    func detachSurface(_ surface: UIView) {
        guard surfaceView === surface else { return }
        pendingSurfaceDetachTask?.cancel()
        let detachedSurface = surface
        pendingSurfaceDetachTask = Task { @MainActor [weak self, weak detachedSurface] in
            await Task.yield()
            guard let self,
                  let detachedSurface,
                  !Task.isCancelled,
                  self.surfaceView == nil || self.surfaceView === detachedSurface
            else { return }
            self.removePlayerLayer()
            self.nativeDolbyVideoOverlay.detach(from: detachedSurface)
            self.pendingSurfaceDetachTask = nil
        }
        surfaceView = nil
    }

    func refreshSurfaceLayout() {
        guard !isStopped else { return }
        AVPlayerLayoutCoordinator.shared.apply(
            playerLayer: playerLayer,
            in: surfaceView,
            gravity: videoGravity
        )
        nativeDolbyVideoOverlay.refreshLayout(in: surfaceView, gravity: videoGravity)
    }

    func recoverSurface() {
        guard !isStopped else { return }
        configureAudioSession()
        if let playerViewController {
            // AVPlayerViewController owns the active video layer for normal video
            // playback. Reassigning its player forces a fresh drawable after a
            // long screen lock, where the item can remain ready but its layer is
            // no longer rendering frames.
            playerViewController.player = nil
            playerViewController.player = player
            configureNativePlaybackController(playerViewController)
            playerViewController.view.setNeedsLayout()
            playerViewController.view.setNeedsDisplay()
            playerViewController.view.layer.setNeedsDisplay()
            return
        }
        guard let surfaceView else { return }
        let layer = ensurePlayerLayer(in: surfaceView)
        layer.player = nil
        layer.player = player
        layer.isHidden = false
        layer.opacity = 1
        refreshSurfaceLayout()
        layer.setNeedsLayout()
        layer.setNeedsDisplay()
        nativeDolbyVideoOverlay.attach(to: surfaceView, gravity: videoGravity)
    }

    @discardableResult
    func refreshVideoOutputForPlaybackRecovery() -> Bool {
        guard source?.playbackContentMode != .audioOnly else {
            recoverSurface()
            return false
        }
        guard !isStopped,
              let item = playerItem,
              player.currentItem === item
        else {
            recoverSurface()
            return false
        }

        recoveryFrameCacheTask?.cancel()
        recoveryFrameCacheTask = nil
        if let videoOutput {
            item.remove(videoOutput)
        }
        videoOutput = nil
        attachVideoOutput(to: item)
        recoverSurface()
        ensurePeriodicTimeObserver()
        return true
    }

    @discardableResult
    func rebuildPlayerItemForPlaybackRecovery(at time: TimeInterval) -> TimeInterval? {
        guard !isStopped,
              let source,
              let bridge = hlsBridge,
              liveHLSProxy == nil,
              !isDirectLiveHLS,
              !nativeDolbyVideoOverlay.isActive,
              let oldItem = playerItem,
              player.currentItem === oldItem
        else { return nil }

        let startedAt = CACurrentMediaTime()
        let targetTime = time.isFinite ? max(time, 0) : 0
        let recoveryGeneration = playbackGeneration &+ 1
        var playlistComponents = URLComponents(
            url: bridge.masterPlaylistURL,
            resolvingAgainstBaseURL: false
        )
        var queryItems = playlistComponents?.queryItems ?? []
        queryItems.removeAll { $0.name == "recovery" }
        queryItems.append(URLQueryItem(name: "recovery", value: String(recoveryGeneration)))
        playlistComponents?.queryItems = queryItems
        let recoveryPlaylistURL = playlistComponents?.url ?? bridge.masterPlaylistURL
        let asset = AVURLAsset(url: recoveryPlaylistURL)
        let item = AVPlayerItem(asset: asset)
        Self.applyDolbyVisionMetadataPolicy(to: item, source: source)

        playbackGeneration = recoveryGeneration
        silencePlayerImmediately()
        player.cancelPendingPrerolls()
        oldItem.cancelPendingSeeks()
        if let videoOutput {
            oldItem.remove(videoOutput)
        }
        itemReadinessTimeoutTask?.cancel()
        itemReadinessTimeoutTask = nil
        cancelFirstFrameWatchdog()
        cancelTerminalStallWatchdog()
        recoveryFrameCacheTask?.cancel()
        recoveryFrameCacheTask = nil
        seekProtectionReleaseTask?.cancel()
        seekProtectionReleaseTask = nil
        seekProtectionTargetTime = nil
        seekProtectionAppliedAt = nil
        automaticallyWaitsBeforeSeekProtection = nil
        lastSeekFinishedAt = nil
        isSeekProtectionActive = false
        isPerformingSeek = false
        seekGeneration &+= 1
        videoOutput = nil
        didReportFirstFrame = false
        isStartupFastStartActive = true
        lastRecordedAccessLogStallCount = 0
        lastPlaybackFailureReason = nil
        removeCurrentItemObservers()
        removePeriodicTimeObserver()

        playerItem = item
        retainedAssets = [asset]
        configureStartupBuffering(for: item, source: source)
        attachVideoOutput(to: item)
        player.replaceCurrentItem(with: item)
        oldItem.asset.cancelLoading()
        player.automaticallyWaitsToMinimizeStalling = false
        ensurePeriodicTimeObserver()
        observeCurrentItem(item)
        scheduleItemReadinessTimeout(for: item, generation: recoveryGeneration)
        onLoadingProgressChange?(0.72)
        publishPlaybackState(.buffering)

        let restoredTime = seek(toTime: targetTime) ?? targetTime
        recoverSurface()
        if item.status == .readyToPlay {
            handleCurrentItemReadyToPlay(item)
        }
        recordPrepareStage(
            source: source,
            stage: "recovery-item",
            startedAt: startedAt,
            extra: "bridge=reused target=\(String(format: "%.2fs", restoredTime))"
        )
        return restoredTime
    }

    @discardableResult
    func warmPausedPlaybackForRecovery() -> Bool {
        guard !isStopped,
              !wantsPlayback,
              let item = playerItem,
              player.currentItem === item
        else { return false }

        shouldPrerollPausedRecoveryAfterSeek = true
        if !isPerformingSeek {
            startPausedRecoveryPrerollIfNeeded()
        }
        deactivateAudioSessionIfPossible()
        return true
    }

    func setViewModel(_ viewModel: PlayerStateViewModel?) {
        self.viewModel = viewModel
    }

    func setVideoGravity(_ gravity: AVLayerVideoGravity) {
        guard videoGravity != gravity else { return }
        videoGravity = gravity
        playerViewController?.videoGravity = gravity
        playerLayer?.videoGravity = gravity
        nativeDolbyVideoOverlay.setVideoGravity(gravity, in: surfaceView)
    }

    func setContentOverlay(_ overlay: AnyView?) {
        contentOverlay = overlay
        installContentOverlayIfPossible()
    }

    func attachNativePlaybackController(_ controller: AVPlayerViewController) {
        if let playerViewController, playerViewController !== controller {
            playerViewController.player = nil
            controllerReadyForDisplayObserver = nil
        }
        playerViewController = controller
        configureNativePlaybackController(controller)
        installContentOverlayIfPossible()
        removePlayerLayer()
    }

    func setPictureInPictureEnabled(_ isEnabled: Bool) {
        isPictureInPictureEnabled = isEnabled
        if let playerViewController {
            configureNativePlaybackController(playerViewController)
        }
    }

    func detachNativePlaybackController(_ controller: AVPlayerViewController) {
        guard playerViewController === controller else { return }
        removeContentOverlayHostingController()
        controller.player = nil
        controllerReadyForDisplayObserver = nil
        playerViewController = nil
    }

    func prepare(source: PlayerStreamSource) async throws {
        let prepareStart = CACurrentMediaTime()
        let signpostState = PlayerMetricsLog.beginSignpostedInterval(
            "AVPlayerBridgePrepare",
            message: "id=\(source.metricsID) dash=\(source.audioURL != nil)"
        )
        var signpostMessage = "id=\(source.metricsID) preparing"
        defer {
            PlayerMetricsLog.endSignpostedInterval(
                "AVPlayerBridgePrepare",
                signpostState,
                message: signpostMessage
            )
        }
        playbackGeneration &+= 1
        let generation = playbackGeneration
        isStopped = false
        tearDownCurrentItemForReplacement()
        self.source = source
        let recoveryKey = playbackFailureRecoveryKey(for: source)
        if !isPlaybackFailureRecoveryInProgress {
            playbackFailureRecoveryAttempts[recoveryKey] = 0
        }
        wantsPlayback = false
        didReportFirstFrame = false
        didSeekDirectLiveHLS = false
        isStartupFastStartActive = false
        manualPreferredPeakBitRate = nil
        lastRecordedAccessLogStallCount = 0
        lastPlaybackFailureReason = nil
        isSeekProtectionActive = false
        seekProtectionReleaseTask?.cancel()
        seekProtectionReleaseTask = nil
        seekWarmupTask?.cancel()
        seekWarmupTask = nil
        seekProtectionTargetTime = nil
        seekProtectionAppliedAt = nil
        automaticallyWaitsBeforeSeekProtection = nil
        lastSeekFinishedAt = nil
        cancelFirstFrameWatchdog()
        applyTargetAudioState()
        onLoadingProgressChange?(0.18)
        recordPrepareStage(source: source, stage: "start", startedAt: prepareStart)
        publishPlaybackState(.preparing)
        let prepared: PreparedPlayerItem
        do {
            prepared = try await Self.makePlayerItem(
                source: source,
                onRemoteFailure: { [weak self] reason in
                    self?.handleHLSRemoteFailure(reason, generation: generation)
                }
            )
        } catch {
            lastPlaybackFailureReason = prepareFailureReason(for: error, source: source)
            throw error
        }
        guard !Task.isCancelled, isCurrentPlaybackGeneration(generation) else {
            discardPreparedPlayerItem(prepared)
            signpostMessage = "id=\(source.metricsID) cancelled"
            return
        }
        onLoadingProgressChange?(0.58)
        recordPrepareStage(
            source: source,
            stage: "item",
            startedAt: prepareStart,
            extra: "directLive=\(prepared.isDirectLiveHLS) bridge=\(prepared.bridge != nil) assets=\(prepared.assets.count)"
        )
        removeCurrentItemObservers()
        playerItem = prepared.item
        hlsBridge = prepared.bridge
        liveHLSProxy = prepared.liveProxy
        mediaTimeOffset = prepared.bridge?.mediaTimeOffset ?? 0
        retainedAssets = prepared.assets
        isDirectLiveHLS = prepared.isDirectLiveHLS
        isStartupFastStartActive = !prepared.isDirectLiveHLS
            || LiveHLSFastStartPolicy.activatesForDirectLiveHLS(
                isDirectLiveHLS: prepared.isDirectLiveHLS,
                isLiveStream: source.isLiveStream
            )
        let item = prepared.item
        configureStartupBuffering(for: item, source: source)
        attachVideoOutput(to: item)
        player.replaceCurrentItem(with: item)
        configureNativeDolbyVideoOverlayIfNeeded(for: source, generation: generation)
        recordPrepareStage(
            source: source,
            stage: "installed",
            startedAt: prepareStart,
            extra: "buffer=\(String(format: "%.2f", item.preferredForwardBufferDuration))s peak=\(Int(item.preferredPeakBitRate.rounded())) fastStart=\(isStartupFastStartActive)"
        )
        player.automaticallyWaitsToMinimizeStalling = false
        ensurePeriodicTimeObserver()
        if let playerViewController {
            configureNativePlaybackController(playerViewController)
        } else if let surfaceView {
            ensurePlayerLayer(in: surfaceView).player = player
            refreshSurfaceLayout()
        }
        observeCurrentItem(item)
        scheduleItemReadinessTimeout(for: item, generation: generation)
        onLoadingProgressChange?(0.72)
        guard !Task.isCancelled, isCurrentPlaybackGeneration(generation), isCurrentPlayerItem(item) else {
            signpostMessage = "id=\(source.metricsID) cancelled"
            return
        }
        if item.status == .readyToPlay {
            onLoadingProgressChange?(0.86)
            handleCurrentItemReadyToPlay(item)
        }
        signpostMessage = "id=\(source.metricsID) installed elapsed=\(String(format: "%.1f", PlayerMetricsLog.elapsedMilliseconds(since: prepareStart)))ms"
        recordPrepareStage(source: source, stage: "installed-ready-deferred", startedAt: prepareStart)
    }

    func play() {
        guard !isStopped, let item = player.currentItem else { return }
        shouldPrerollPausedRecoveryAfterSeek = false
        configureAudioSession()
        applyTargetAudioState()
        wantsPlayback = true
        guard item.status == .readyToPlay else {
            if item.status == .unknown {
                beginPlayback()
            }
            onLoadingProgressChange?(0.72)
            publishPlaybackState(.buffering)
            return
        }
        beginPlayback()
        syncNativeDolbyVideoOverlay(reason: "play", force: true)
        scheduleTerminalStallWatchdog(reason: "play")
        let currentTime = displayTime(fromPlayerTime: player.currentTime().seconds)
        if player.rate > 0 || player.timeControlStatus == .playing {
            onLoadingProgressChange?(0.98)
            publishPlaybackState(.playing)
        } else {
            onLoadingProgressChange?(0.86)
            publishPlaybackState(.buffering)
        }
        reportFirstFrameIfPossible(currentTime: currentTime)
    }

    func pause() {
        pause(deactivatesAudioSession: true, notifiesStateChange: true)
    }

    func pauseForUserScrub() {
        pause(deactivatesAudioSession: false, notifiesStateChange: false)
    }

    private func pause(deactivatesAudioSession: Bool, notifiesStateChange: Bool) {
        guard !isStopped else { return }
        shouldPrerollPausedRecoveryAfterSeek = false
        wantsPlayback = false
        cancelTerminalStallWatchdog()
        player.pause()
        nativeDolbyVideoOverlay.pause()
        if deactivatesAudioSession {
            deactivateAudioSessionIfPossible()
        }
        if notifiesStateChange {
            publishPlaybackState(.paused)
        } else {
            lastPlaybackState = .paused
        }
    }

    func pauseForAppBackground() {
        guard !isStopped else { return }
        shouldPrerollPausedRecoveryAfterSeek = false
        wantsPlayback = false
        cancelTerminalStallWatchdog()
        player.rate = 0
        player.pause()
        player.cancelPendingPrerolls()
        nativeDolbyVideoOverlay.pause()
        deactivateAudioSessionIfPossible()
        publishPlaybackState(.paused)
    }

    func pauseForNavigation() {
        guard !isStopped else { return }
        shouldPrerollPausedRecoveryAfterSeek = false
        wantsPlayback = false
        cancelTerminalStallWatchdog()
        player.rate = 0
        player.pause()
        nativeDolbyVideoOverlay.pause()
        player.currentItem?.cancelPendingSeeks()
        player.cancelPendingPrerolls()
        // Keep the session active across foreground player handoffs. Deactivation
        // can synchronously block the main thread before the navigation starts.
        publishPlaybackState(.paused)
    }

    func suspendForNavigation() {
        guard !isStopped else { return }
        shouldPrerollPausedRecoveryAfterSeek = false
        wantsPlayback = false
        cancelTerminalStallWatchdog()
        silencePlayerImmediately()
        nativeDolbyVideoOverlay.pause()
        player.currentItem?.cancelPendingSeeks()
        // The next detail player reuses the same playback session immediately.
        publishPlaybackState(.paused)
    }

    func stop() {
        playbackGeneration &+= 1
        isStopped = true
        shouldPrerollPausedRecoveryAfterSeek = false
        wantsPlayback = false
        cancelTerminalStallWatchdog()
        nativeDolbyVideoSyncTask?.cancel()
        nativeDolbyVideoSyncTask = nil
        nativeDolbyVideoOverlay.stop()
        pendingSurfaceDetachTask?.cancel()
        pendingSurfaceDetachTask = nil
        isPlaybackFailureRecoveryInProgress = false
        tearDownCurrentItemForReplacement()
        source = nil
        removePlayerLayer()
        playerViewController?.player = nil
        setContentOverlay(nil)
        layerReadyForDisplayObserver = nil
        deactivateAudioSessionIfPossible()
        publishPlaybackState(.idle)
    }

    func setPlaybackRate(_ rate: Double) {
        let normalizedRate = max(Float(rate), 0.1)
        guard abs(currentRate - normalizedRate) > 0.001 else { return }
        currentRate = normalizedRate
        player.defaultRate = normalizedRate
        applyRateAwareBuffering()
        applyRateAwareAudioPitchAlgorithm()
        if player.rate > 0 {
            player.rate = currentRate
            nativeDolbyVideoOverlay.play(rate: currentRate)
        }
    }

    func setPreferredPeakBitRate(_ bitRate: Double?) {
        guard !isDirectLiveHLS else { return }
        manualPreferredPeakBitRate = bitRate
        if let bitRate, let item = player.currentItem {
            item.preferredPeakBitRate = bitRate
        } else if let item = player.currentItem, let source {
            configureStartupBuffering(for: item, source: source)
            applyRateAwareBuffering()
        }
    }

    func setVolume(_ volume: Float) {
        targetVolume = min(max(volume, 0), 1)
        applyTargetAudioState()
    }

    func setMuted(_ isMuted: Bool) {
        targetMuted = isMuted
        applyTargetAudioState()
    }

    func setTemporaryAudioSuppressed(_ isSuppressed: Bool) {
        isTemporaryAudioSuppressed = isSuppressed
        if isSuppressed {
            player.isMuted = true
            player.volume = 0
        } else {
            applyTargetAudioState()
        }
    }

    func seek(toTime time: TimeInterval) -> TimeInterval? {
        guard !isStopped, player.currentItem != nil else { return nil }
        let target = playerTime(fromDisplayTime: max(time, 0))
        let displayTarget = displayTime(fromPlayerTime: target)
        let seekPlaybackGeneration = playbackGeneration
        let generation = beginSeekTransaction(targetDisplayTime: displayTarget)
        if wantsPlayback || isPerformingSeek {
            publishPlaybackState(.buffering)
        }
        warmSeekTargetIfNeeded(displayTarget)
        player.currentItem?.cancelPendingSeeks()
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] finished in
            Task { @MainActor [weak self] in
                guard let self,
                      self.isCurrentPlaybackGeneration(seekPlaybackGeneration)
                else { return }
                self.finishSeekTransaction(generation: generation, finished: finished, shouldResume: self.wantsPlayback)
            }
        }
        nativeDolbyVideoOverlay.seek(to: displayTarget, shouldPlay: wantsPlayback)
        return displayTarget
    }

    func seekToLiveEdge() -> TimeInterval? {
        guard !isStopped,
              let item = player.currentItem,
              let range = item.seekableTimeRanges.last?.timeRangeValue
        else { return nil }

        let start = range.start.seconds
        let duration = range.duration.seconds
        guard start.isFinite, duration.isFinite, duration > 0 else { return nil }

        // Stop just short of the reported edge so AVPlayer has a playable HLS segment.
        let playerTarget = max(start + duration - 1.0, start)
        let displayTarget = displayTime(fromPlayerTime: playerTarget)
        let seekPlaybackGeneration = playbackGeneration
        let generation = beginSeekTransaction(targetDisplayTime: displayTarget)
        if wantsPlayback || isPerformingSeek {
            publishPlaybackState(.buffering)
        }

        item.cancelPendingSeeks()
        player.seek(
            to: CMTime(seconds: playerTarget, preferredTimescale: 600),
            toleranceBefore: CMTime(seconds: 0.5, preferredTimescale: 600),
            toleranceAfter: .zero
        ) { [weak self] finished in
            Task { @MainActor [weak self] in
                guard let self,
                      self.isCurrentPlaybackGeneration(seekPlaybackGeneration)
                else { return }
                self.finishSeekTransaction(
                    generation: generation,
                    finished: finished,
                    shouldResume: self.wantsPlayback
                )
            }
        }
        nativeDolbyVideoOverlay.seek(to: displayTarget, shouldPlay: wantsPlayback)
        return displayTarget
    }

    func seek(toProgress progress: Double, duration: TimeInterval?) -> TimeInterval? {
        guard !isStopped, player.currentItem != nil else { return nil }
        let resolvedDuration = resolvedDuration(durationHint: duration)
        guard resolvedDuration > 0 else { return nil }
        let displayTarget = alignedInteractiveSeekTime(
            min(max(progress, 0), 1) * resolvedDuration
        )
        let target = playerTime(fromDisplayTime: displayTarget)
        let seekPlaybackGeneration = playbackGeneration
        let generation = beginSeekTransaction(targetDisplayTime: displayTarget)
        if wantsPlayback || isPerformingSeek {
            publishPlaybackState(.buffering)
        }
        warmSeekTargetIfNeeded(displayTarget)
        let targetTime = CMTime(seconds: target, preferredTimescale: 600)
        player.currentItem?.cancelPendingSeeks()
        player.seek(
            to: targetTime,
            toleranceBefore: Self.interactiveSeekTolerance,
            toleranceAfter: Self.interactiveSeekTolerance
        ) { [weak self] finished in
            Task { @MainActor [weak self] in
                guard let self,
                      self.isCurrentPlaybackGeneration(seekPlaybackGeneration)
                else { return }
                self.finishSeekTransaction(generation: generation, finished: finished, shouldResume: self.wantsPlayback)
            }
        }
        nativeDolbyVideoOverlay.seek(to: displayTarget, shouldPlay: wantsPlayback)
        return displayTarget
    }

    func seek(by interval: TimeInterval, from currentTime: TimeInterval, duration: TimeInterval?) -> TimeInterval? {
        guard !isStopped, player.currentItem != nil else { return nil }
        let resolvedDuration = resolvedDuration(durationHint: duration)
        let target = resolvedDuration > 0
            ? min(max(currentTime + interval, 0), resolvedDuration)
            : max(currentTime + interval, 0)
        let playerTarget = playerTime(fromDisplayTime: target)
        let displayTarget = alignedInteractiveSeekTime(displayTime(fromPlayerTime: playerTarget))
        let alignedPlayerTarget = playerTime(fromDisplayTime: displayTarget)
        let seekPlaybackGeneration = playbackGeneration
        let generation = beginSeekTransaction(targetDisplayTime: displayTarget)
        if wantsPlayback || isPerformingSeek {
            publishPlaybackState(.buffering)
        }
        warmSeekTargetIfNeeded(displayTarget)
        let targetTime = CMTime(seconds: alignedPlayerTarget, preferredTimescale: 600)
        player.currentItem?.cancelPendingSeeks()
        player.seek(
            to: targetTime,
            toleranceBefore: CMTime(seconds: 0.35, preferredTimescale: 600),
            toleranceAfter: CMTime(seconds: 0.35, preferredTimescale: 600)
        ) { [weak self] finished in
            Task { @MainActor [weak self] in
                guard let self,
                      self.isCurrentPlaybackGeneration(seekPlaybackGeneration)
                else { return }
                self.finishSeekTransaction(generation: generation, finished: finished, shouldResume: self.wantsPlayback)
            }
        }
        nativeDolbyVideoOverlay.seek(to: displayTarget, shouldPlay: wantsPlayback)
        return displayTarget
    }

    func seekAfterUserScrub(toProgress progress: Double, duration: TimeInterval?) async -> TimeInterval? {
        guard !isStopped, player.currentItem != nil else { return nil }
        let resolvedDuration = resolvedDuration(durationHint: duration)
        guard resolvedDuration > 0 else { return nil }
        let requestedDisplayTarget = min(max(progress, 0), 1) * resolvedDuration
        let displayTarget = alignedInteractiveSeekTime(requestedDisplayTarget)
        let target = playerTime(fromDisplayTime: displayTarget)
        let targetTime = CMTime(seconds: target, preferredTimescale: 600)
        wantsPlayback = false
        let seekPlaybackGeneration = playbackGeneration
        let generation = beginSeekTransaction(targetDisplayTime: displayTarget)
        publishPlaybackState(.buffering)
        warmSeekTargetIfNeeded(displayTarget)
        player.currentItem?.cancelPendingSeeks()
        let finished = await withCheckedContinuation { continuation in
            player.seek(
                to: targetTime,
                toleranceBefore: Self.interactiveSeekTolerance,
                toleranceAfter: Self.interactiveSeekTolerance
            ) { finished in
                continuation.resume(returning: finished)
            }
        }
        nativeDolbyVideoOverlay.seek(to: displayTarget, shouldPlay: false)
        guard isCurrentPlaybackGeneration(seekPlaybackGeneration) else { return nil }
        finishSeekTransaction(generation: generation, finished: finished, shouldResume: false)
        return finished ? displayTarget : nil
    }

    func snapshot(durationHint: TimeInterval?) -> PlayerPlaybackSnapshot {
        let currentSeconds = displayTime(fromPlayerTime: player.currentTime().seconds)
        let durationSeconds = resolvedDuration(durationHint: durationHint)
        let item = player.currentItem
        let status = item?.status
        return PlayerPlaybackSnapshot(
            currentTime: currentSeconds.isFinite && currentSeconds >= 0 ? currentSeconds : nil,
            renderedVideoTime: shouldReportRenderedVideoTimeForSeekRecovery
                ? sampledRenderedVideoTime(cachesFrameImage: true)
                : nil,
            requiresRenderedVideoTimeForRecovery: shouldReportRenderedVideoTimeForSeekRecovery,
            duration: durationSeconds > 0 ? durationSeconds : durationHint,
            isPlaying: player.rate > 0,
            isSeekable: status == .readyToPlay || (durationHint ?? 0) > 0,
            bufferedRanges: item.map(bufferedRanges(for:)) ?? []
        )
    }

    func currentVideoFrameImage() -> UIImage? {
        guard let videoOutput,
              player.currentItem === playerItem
        else { return lastVideoFrameImage }

        let hostTime = CACurrentMediaTime()
        let hostItemTime = videoOutput.itemTime(forHostTime: hostTime)
        var displayTime = CMTime.invalid
        if let pixelBuffer = videoOutput.copyPixelBuffer(
            forItemTime: hostItemTime,
            itemTimeForDisplay: &displayTime
        ) {
            return cacheVideoFrameImage(from: pixelBuffer)
        }

        let currentItemTime = player.currentTime()
        guard let pixelBuffer = videoOutput.copyPixelBuffer(
            forItemTime: currentItemTime,
            itemTimeForDisplay: nil
        ) else {
            return lastVideoFrameImage
        }
        return cacheVideoFrameImage(from: pixelBuffer)
    }

    func currentRenderedVideoTime() -> TimeInterval? {
        sampledRenderedVideoTime(cachesFrameImage: false)
    }

    private func sampledRenderedVideoTime(cachesFrameImage: Bool) -> TimeInterval? {
        guard let videoOutput,
              player.currentItem === playerItem
        else { return nil }

        let hostItemTime = videoOutput.itemTime(forHostTime: CACurrentMediaTime())
        var itemDisplayTime = CMTime.invalid
        guard let pixelBuffer = videoOutput.copyPixelBuffer(
            forItemTime: hostItemTime,
            itemTimeForDisplay: &itemDisplayTime
        ) else {
            return nil
        }

        if cachesFrameImage {
            _ = cacheVideoFrameImage(from: pixelBuffer)
        }
        let playerTime = itemDisplayTime.isValid && itemDisplayTime.seconds.isFinite
            ? itemDisplayTime.seconds
            : hostItemTime.seconds
        let renderedTime = displayTime(fromPlayerTime: playerTime)
        guard renderedTime.isFinite, renderedTime >= 0 else { return nil }
        return renderedTime
    }

    func currentSurfaceSnapshotImage() -> UIImage? {
        surfaceView?.biliRenderedSnapshotImage()
    }

    func pictureInPictureContentSource() -> AVPictureInPictureController.ContentSource? {
        guard let playerLayer else { return nil }
        return AVPictureInPictureController.ContentSource(playerLayer: playerLayer)
    }

    func togglePictureInPicture() {}

    func invalidatePictureInPicturePlaybackState() {}

    private func beginPlayback() {
        guard !isStopped, player.currentItem != nil else { return }
        startPlaybackImmediately()
    }

    private func startPlaybackImmediately() {
        guard !isStopped, player.currentItem != nil else { return }
        applyTargetAudioState()
        if LiveHLSFastStartPolicy.usesImmediatePlayback(
            isDirectLiveHLS: isDirectLiveHLS,
            isLiveStream: source?.isLiveStream == true,
            isStartupFastStartActive: isStartupFastStartActive
        ) {
            player.playImmediately(atRate: currentRate)
        } else if isDirectLiveHLS {
            player.play()
        } else {
            player.playImmediately(atRate: currentRate)
        }
        nativeDolbyVideoOverlay.play(rate: currentRate)
        syncNativeDolbyVideoOverlay(reason: "begin", force: false)
    }

    private func applyTargetAudioState() {
        guard !isTemporaryAudioSuppressed else {
            player.volume = 0
            player.isMuted = true
            return
        }
        player.volume = targetVolume
        player.isMuted = targetMuted
    }

    private func silencePlayerImmediately() {
        shouldPrerollPausedRecoveryAfterSeek = false
        player.isMuted = true
        player.volume = 0
        player.rate = 0
        player.pause()
        player.cancelPendingPrerolls()
        nativeDolbyVideoOverlay.pause()
    }

    private func configureNativeDolbyVideoOverlayIfNeeded(
        for source: PlayerStreamSource,
        generation: Int
    ) {
        guard shouldUseNativeDolbyVideoOverlay(for: source) else {
            nativeDolbyVideoSyncTask?.cancel()
            nativeDolbyVideoSyncTask = nil
            nativeDolbyVideoOverlay.stop()
            return
        }
        nativeDolbyVideoOverlay.prepare(source: source, surface: surfaceView, gravity: videoGravity)
        startNativeDolbyVideoSyncLoop(generation: generation)
    }

    private func shouldUseNativeDolbyVideoOverlay(for source: PlayerStreamSource) -> Bool {
        guard DolbyVisionRenderingPolicy.stored().playablePolicy == .appleNativeP8HLS,
              source.dynamicRange == .dolbyVision,
              source.audioURL != nil,
              source.videoURL != nil,
              supportsNativeHDRVideoOverlay
        else { return false }
        return true
    }

    private var supportsNativeHDRVideoOverlay: Bool {
        if let surfaceView {
            return surfaceView.traitCollection.displayGamut == .P3
        }
        return UITraitCollection.current.displayGamut == .P3
    }

    private func startNativeDolbyVideoSyncLoop(generation: Int) {
        nativeDolbyVideoSyncTask?.cancel()
        nativeDolbyVideoSyncTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self,
                      !Task.isCancelled,
                      self.isCurrentPlaybackGeneration(generation),
                      self.nativeDolbyVideoOverlay.isActive
                else { return }
                self.syncNativeDolbyVideoOverlay(reason: "timer", force: false)
                try? await Task.sleep(nanoseconds: 450_000_000)
            }
        }
    }

    private func syncNativeDolbyVideoOverlay(reason: String, force: Bool) {
        syncNativeDolbyVideoOverlay(reason: reason, force: force, countsAsResync: true)
    }

    private func syncNativeDolbyVideoOverlay(reason: String, force: Bool, countsAsResync: Bool) {
        guard nativeDolbyVideoOverlay.isActive else { return }
        let masterTime = displayTime(fromPlayerTime: player.currentTime().seconds)
        guard masterTime.isFinite, masterTime >= 0 else { return }
        nativeDolbyVideoOverlay.sync(
            to: masterTime,
            shouldPlay: wantsPlayback && !isPerformingSeek,
            rate: currentRate,
            force: force,
            reason: reason,
            countsAsResync: countsAsResync
        )
    }

    private func handleNativeDolbyVideoOverlayReadyToPlay() {
        guard source?.dynamicRange == .dolbyVision,
              DolbyVisionRenderingPolicy.stored().playablePolicy == .appleNativeP8HLS
        else { return }
        syncNativeDolbyVideoOverlay(reason: "nativeReady", force: true, countsAsResync: false)
    }

    private func handleNativeDolbyVideoOverlayReady() {
        guard source?.dynamicRange == .dolbyVision,
              DolbyVisionRenderingPolicy.stored().playablePolicy == .appleNativeP8HLS
        else { return }
        reportFirstFrameIfPossible(allowsNativeHDRVideoOverlay: true)
        maybeReleaseSeekProtectionIfReady(reason: "nativeHDR")
    }

    private func tearDownCurrentItemForReplacement() {
        let oldItem = player.currentItem
        let oldBridge = hlsBridge
        let oldLiveProxy = liveHLSProxy
        silencePlayerImmediately()
        oldItem?.cancelPendingSeeks()
        oldItem?.asset.cancelLoading()
        if let videoOutput {
            oldItem?.remove(videoOutput)
        }
        itemReadinessTimeoutTask?.cancel()
        itemReadinessTimeoutTask = nil
        cancelFirstFrameWatchdog()
        recoveryFrameCacheTask?.cancel()
        recoveryFrameCacheTask = nil
        videoOutput = nil
        lastVideoFrameImage = nil
        removeCurrentItemObservers()
        removePeriodicTimeObserver()
        nativeDolbyVideoSyncTask?.cancel()
        nativeDolbyVideoSyncTask = nil
        nativeDolbyVideoOverlay.stop()
        if oldItem != nil {
            player.replaceCurrentItem(with: nil)
        }
        oldBridge?.stop()
        oldLiveProxy?.stop()
        playerItem = nil
        hlsBridge = nil
        liveHLSProxy = nil
        mediaTimeOffset = 0
        retainedAssets = []
        isDirectLiveHLS = false
        didSeekDirectLiveHLS = false
        didReportFirstFrame = false
        isPerformingSeek = false
        seekGeneration &+= 1
        isSeekProtectionActive = false
        seekProtectionReleaseTask?.cancel()
        seekProtectionReleaseTask = nil
        seekProtectionTargetTime = nil
        seekProtectionAppliedAt = nil
        automaticallyWaitsBeforeSeekProtection = nil
        lastSeekFinishedAt = nil
        cancelTerminalStallWatchdog()
        cancelFirstFrameWatchdog()
        isStartupFastStartActive = false
        manualPreferredPeakBitRate = nil
        lastRecordedAccessLogStallCount = 0
    }

    private func attachVideoOutput(to item: AVPlayerItem) {
        guard source?.playbackContentMode != .audioOnly else {
            videoOutput = nil
            return
        }
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        output.suppressesPlayerRendering = false
        item.add(output)
        videoOutput = output
    }

    private func makeImage(from pixelBuffer: CVPixelBuffer) -> UIImage? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else { return nil }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        guard let cgImage = videoFrameContext.createCGImage(ciImage, from: rect) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func cacheVideoFrameImage(from pixelBuffer: CVPixelBuffer) -> UIImage? {
        guard let image = makeImage(from: pixelBuffer) else { return lastVideoFrameImage }
        // Do not replace a usable recovery frame with a transient black decoder
        // output. The old image is only used while a locked screen is recovering.
        if !image.biliLooksLikeBlackFrame {
            lastVideoFrameImage = image
        }
        return image
    }

    private func isCurrentPlaybackGeneration(_ generation: Int) -> Bool {
        !isStopped && generation == playbackGeneration
    }

    private func isCurrentPlayerItem(_ item: AVPlayerItem) -> Bool {
        !isStopped && player.currentItem === item && playerItem === item
    }

    private func scheduleItemReadinessTimeout(for item: AVPlayerItem, generation: Int) {
        itemReadinessTimeoutTask?.cancel()
        itemReadinessTimeoutTask = Task { @MainActor [weak self, weak item] in
            try? await Task.sleep(nanoseconds: Self.itemReadinessTimeoutNanoseconds)
            guard let self,
                  let item,
                  !Task.isCancelled,
                  self.isCurrentPlaybackGeneration(generation),
                  self.isCurrentPlayerItem(item),
                  item.status == .unknown
            else { return }
            let message = PrepareReadinessError.timedOut.localizedDescription
            self.lastPlaybackFailureReason = HLSBridgeFailureReason(
                layer: .avPlayerItem,
                category: .timeout,
                statusCode: nil,
                urlHost: nil,
                rangeDescription: nil,
                underlyingDescription: message
            )
            self.publishPlaybackState(.failed(message))
        }
    }

    private func handleHLSRemoteFailure(_ reason: HLSBridgeFailureReason, generation: Int) {
        guard isCurrentPlaybackGeneration(generation),
              !isStopped,
              reason.shouldFailPlaybackImmediately
        else { return }
        lastPlaybackFailureReason = reason
        itemReadinessTimeoutTask?.cancel()
        itemReadinessTimeoutTask = nil
        cancelTerminalStallWatchdog()
        publishPlaybackState(.failed(reason.playbackMessage))
    }

    private func handleCurrentItemReadyToPlay(_ item: AVPlayerItem) {
        guard isCurrentPlayerItem(item) else { return }
        itemReadinessTimeoutTask?.cancel()
        itemReadinessTimeoutTask = nil
        scheduleFirstFrameWatchdogIfNeeded(reason: "item-ready")
        seekDirectLiveHLSToLiveEdgeIfNeeded(item)
        if wantsPlayback || player.rate > 0 || player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
            if player.rate > 0 || player.timeControlStatus == .playing {
                publishPlaybackState(.playing)
                reportFirstFrameIfPossible()
                maybeReleaseSeekProtectionIfReady(for: item, reason: "item-ready")
            } else {
                if wantsPlayback {
                    beginPlayback()
                }
                publishPlaybackState(.buffering)
                scheduleTerminalStallWatchdog(reason: "item-ready-waiting")
            }
        } else {
            publishPlaybackState(.ready)
        }
    }

    private func isCurrentPlayerLayer(_ identity: ObjectIdentifier) -> Bool {
        guard let playerLayer else { return false }
        return ObjectIdentifier(playerLayer) == identity
    }

    private func isCurrentPlayerViewController(_ identity: ObjectIdentifier) -> Bool {
        guard let playerViewController else { return false }
        return ObjectIdentifier(playerViewController) == identity
    }

    private func discardPreparedPlayerItem(_ prepared: PreparedPlayerItem) {
        prepared.bridge?.stop()
        prepared.liveProxy?.stop()
        prepared.item.cancelPendingSeeks()
        prepared.item.asset.cancelLoading()
        prepared.assets.forEach { $0.cancelLoading() }
    }

    private func seekDirectLiveHLSToLiveEdgeIfNeeded(_ item: AVPlayerItem) {
        guard isCurrentPlayerItem(item) else { return }
        guard isDirectLiveHLS, !didSeekDirectLiveHLS else { return }
        if LiveHLSFastStartPolicy.defersInitialLiveEdgeSeek(
            streamFormat: source?.liveHLSFormat
        ) {
            didSeekDirectLiveHLS = true
            if let source {
                PlayerMetricsLog.record(
                    .startupBreakdown,
                    metricsID: source.metricsID,
                    title: source.title,
                    message: "directLiveHLSInitialEdgeSeek=deferred format=\(source.liveHLSFormat ?? "-")"
                )
            }
            return
        }
        guard let range = item.seekableTimeRanges.last?.timeRangeValue else { return }
        let start = range.start.seconds
        let duration = range.duration.seconds
        guard start.isFinite, duration.isFinite, duration > 0 else { return }
        didSeekDirectLiveHLS = true
        let liveEdge = max(start + duration - 1.0, start)
        PlayerMetricsLog.logger.info(
            "directLiveHLSSeekToEdge start=\(start, format: .fixed(precision: 2), privacy: .public) duration=\(duration, format: .fixed(precision: 2), privacy: .public) target=\(liveEdge, format: .fixed(precision: 2), privacy: .public)"
        )
        player.seek(
            to: CMTime(seconds: liveEdge, preferredTimescale: 600),
            toleranceBefore: CMTime(seconds: 0.5, preferredTimescale: 600),
            toleranceAfter: .zero
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.wantsPlayback, self.isCurrentPlayerItem(item) else { return }
                self.beginPlayback()
            }
        }
    }

    private func configureNativePlaybackController(_ controller: AVPlayerViewController) {
        if controller.player !== player {
            controller.player = player
        }
        applyDisplayDynamicRangePolicy(to: controller)
        if controller.videoGravity != videoGravity {
            controller.videoGravity = videoGravity
        }
        let isPictureInPictureAllowed = isPictureInPictureEnabled
            && AVPictureInPictureController.isPictureInPictureSupported()
        controller.allowsPictureInPicturePlayback = isPictureInPictureAllowed
        controller.canStartPictureInPictureAutomaticallyFromInline = isPictureInPictureAllowed
        controller.requiresLinearPlayback = false
        controller.updatesNowPlayingInfoCenter = false
        controller.view.backgroundColor = .black
        observeControllerReadyForDisplay(controller)
    }

    private func installContentOverlayIfPossible() {
        guard let overlay = contentOverlay,
              let playerViewController,
              let containerView = playerViewController.contentOverlayView
        else {
            if contentOverlay == nil {
                removeContentOverlayHostingController()
            }
            return
        }

        if contentOverlayContainerView !== containerView {
            removeContentOverlayHostingController()
        }
        containerView.backgroundColor = .clear
        containerView.isOpaque = false
        containerView.isUserInteractionEnabled = true

        if let contentOverlayHostingController {
            contentOverlayHostingController.rootView = overlay
            contentOverlayHostingController.view.isUserInteractionEnabled = false
        } else {
            let hostingController = UIHostingController(rootView: overlay)
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false
            hostingController.view.backgroundColor = .clear
            hostingController.view.isOpaque = false
            hostingController.view.isUserInteractionEnabled = false
            playerViewController.addChild(hostingController)
            containerView.addSubview(hostingController.view)
            NSLayoutConstraint.activate([
                hostingController.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                hostingController.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                hostingController.view.topAnchor.constraint(equalTo: containerView.topAnchor),
                hostingController.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
            ])
            hostingController.didMove(toParent: playerViewController)
            contentOverlayHostingController = hostingController
            contentOverlayContainerView = containerView
        }
    }

    private func removeContentOverlayHostingController() {
        guard let contentOverlayHostingController else {
            contentOverlayContainerView = nil
            return
        }
        contentOverlayHostingController.willMove(toParent: nil)
        contentOverlayHostingController.view.removeFromSuperview()
        contentOverlayHostingController.removeFromParent()
        self.contentOverlayHostingController = nil
        contentOverlayContainerView = nil
    }

    private func removePlayerLayer() {
        playerLayer?.player = nil
        playerLayer?.removeFromSuperlayer()
        layerReadyForDisplayObserver = nil
        playerLayer = nil
    }

    private func ensurePlayerLayer(in surface: UIView) -> AVPlayerLayer {
        if let playerLayer {
            if playerLayer.superlayer !== surface.layer {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                playerLayer.removeFromSuperlayer()
                surface.layer.insertSublayer(playerLayer, at: 0)
                CATransaction.commit()
            }
            if playerLayer.player == nil {
                playerLayer.player = player
            }
            if layerReadyForDisplayObserver == nil {
                observeLayerReadyForDisplay(playerLayer)
            }
            applyDisplayDynamicRangePolicy(to: playerLayer)
            AVPlayerLayoutCoordinator.shared.apply(playerLayer: playerLayer, in: surface, gravity: videoGravity)
            return playerLayer
        }

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = videoGravity
        layer.backgroundColor = UIColor.black.cgColor
        applyDisplayDynamicRangePolicy(to: layer)
        AVPlayerLayoutCoordinator.shared.apply(playerLayer: layer, in: surface, gravity: videoGravity)
        layer.needsDisplayOnBoundsChange = false
        layer.actions = [
            "bounds": NSNull(),
            "position": NSNull(),
            "frame": NSNull()
        ]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        surface.layer.insertSublayer(layer, at: 0)
        CATransaction.commit()
        playerLayer = layer
        observeLayerReadyForDisplay(layer)
        return layer
    }

    private func applyDisplayDynamicRangePolicy(to controller: AVPlayerViewController) {
        let isHDR = source?.dynamicRange.isHDR == true
        var policyParts = ["target=controller", "hdr=\(isHDR)"]
        controller.preferredDisplayDynamicRange = isHDR ? .automatic : .standard
        controller.view.layer.toneMapMode = .automatic
        policyParts.append("preferred=\(isHDR ? "automatic" : "standard")")
        policyParts.append("toneMap=automatic")
        logDisplayDynamicRangePolicyIfNeeded(policyParts.joined(separator: " "))
    }

    private func applyDisplayDynamicRangePolicy(to layer: AVPlayerLayer) {
        let isHDR = source?.dynamicRange.isHDR == true
        var policyParts = ["target=layer", "hdr=\(isHDR)"]
        if source?.dynamicRange == .dolbyVision {
            policyParts.append("dvPolicy=\(DolbyVisionRenderingPolicy.stored().playablePolicy.rawValue)")
        }
        layer.preferredDynamicRange = isHDR ? .automatic : .standard
        layer.toneMapMode = .automatic
        policyParts.append("preferred=\(isHDR ? "automatic" : "standard")")
        policyParts.append("toneMap=automatic")
        logDisplayDynamicRangePolicyIfNeeded(policyParts.joined(separator: " "))
    }

    private func logDisplayDynamicRangePolicyIfNeeded(_ summary: String) {
        guard lastDisplayDynamicRangePolicySummary != summary else { return }
        lastDisplayDynamicRangePolicySummary = summary
        PlayerMetricsLog.logger.info(
            "avPlayerDisplayDynamicRangePolicy \(summary, privacy: .public)"
        )
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
        } catch {
            // Playback can still proceed if the simulator or system declines the session update.
        }
    }

    private func deactivateAudioSessionIfPossible() {
        guard let viewModel,
              ActivePlaybackCoordinator.shared.isActive(viewModel)
        else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            // The session may already be inactive or owned by a system transition.
        }
    }

    private func configureStartupBuffering(for item: AVPlayerItem, source: PlayerStreamSource) {
        let environment = PlaybackEnvironment.current
        item.preferredForwardBufferDuration = preferredForwardBufferDuration(for: source, environment: environment)
        applyRateAwareAudioPitchAlgorithm(to: item)
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = isDirectLiveHLS
        if let manualPreferredPeakBitRate {
            item.preferredPeakBitRate = manualPreferredPeakBitRate
        } else if let bandwidth = source.videoStream?.bandwidth, bandwidth > 0 {
            let peakBitRateMultiplier = environment.shouldPreferConservativePlayback ? 0.92 : 1.05
            item.preferredPeakBitRate = Double(bandwidth) * peakBitRateMultiplier
        } else if source.audioURL == nil {
            item.preferredPeakBitRate = 0
        }
    }

    private func recordPrepareStage(
        source: PlayerStreamSource,
        stage: String,
        startedAt: CFTimeInterval,
        extra: String? = nil
    ) {
        let elapsedMilliseconds = PlayerMetricsLog.elapsedMilliseconds(since: startedAt)
        PlayerMetricsLog.logger.info(
            "avPlayerBridgePrepareStage id=\(source.metricsID, privacy: .public) stage=\(stage, privacy: .public) elapsedMs=\(elapsedMilliseconds, format: .fixed(precision: 1), privacy: .public)"
        )
        var message = "bridge=\(stage) elapsed=\(String(format: "%.0fms", elapsedMilliseconds))"
        if let videoCodec = source.videoStream?.codecLabel, !videoCodec.isEmpty {
            message += " codec=\(videoCodec)"
        }
        if let resolution = source.videoStream?.resolutionLabel, !resolution.isEmpty {
            message += " res=\(resolution)"
        }
        if let extra, !extra.isEmpty {
            message += " \(extra)"
        }
        PlayerMetricsLog.record(
            .startupBreakdown,
            metricsID: source.metricsID,
            title: source.title,
            message: message
        )
    }

    private func preferredForwardBufferDuration(
        for source: PlayerStreamSource,
        environment: PlaybackEnvironment = .current
    ) -> TimeInterval {
        if isStartupFastStartActive, currentRate < 1.75 {
            return environment.startupForwardBufferDuration
        }
        let baseDuration = source.audioURL == nil
            ? environment.preferredForwardBufferDuration
            : environment.separatedTrackForwardBufferDuration
        guard currentRate >= 1.75, !isDirectLiveHLS else { return baseDuration }
        return max(baseDuration, environment.highRateForwardBufferDuration)
    }

    private func applyRateAwareBuffering() {
        guard let item = player.currentItem, let source else { return }
        if isSeekProtectionActive {
            applySeekProtection(to: item, source: source, shouldRecordMetric: false)
            return
        }
        item.preferredForwardBufferDuration = preferredForwardBufferDuration(for: source)
    }

    private func applyRateAwareAudioPitchAlgorithm() {
        guard let item = player.currentItem else { return }
        applyRateAwareAudioPitchAlgorithm(to: item)
    }

    private func applyRateAwareAudioPitchAlgorithm(to item: AVPlayerItem) {
        item.audioTimePitchAlgorithm = currentRate >= 1.45 ? .timeDomain : .spectral
    }

    private func observePlayerState() {
        playerObservers = [
            player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
                let status = player.timeControlStatus
                Task { @MainActor [weak self] in
                    guard let self,
                          !self.isStopped,
                          player.currentItem === self.playerItem
                    else { return }
                    self.handleTimeControlStatus(status)
                }
            },
            player.observe(\.rate, options: [.new]) { [weak self] player, _ in
                let rate = player.rate
                let itemStatus = player.currentItem?.status
                let timeControlStatus = player.timeControlStatus
                let currentSeconds = player.currentTime().seconds
                Task { @MainActor [weak self] in
                    guard let self, !self.isStopped, player.currentItem === self.playerItem else { return }
                    if rate > 0 {
                        self.cancelTerminalStallWatchdog()
                        self.updatePlaybackIntent(true)
                        self.publishPlaybackState(.playing)
                        self.reportFirstFrameIfPossible(
                            currentTime: self.displayTime(fromPlayerTime: currentSeconds)
                        )
                        self.maybeReleaseSeekProtectionIfReady(reason: "rate")
                    } else if timeControlStatus == .paused,
                              itemStatus == .readyToPlay {
                        if self.isPerformingSeek || self.wantsPlayback {
                            self.publishPlaybackState(.buffering)
                        } else {
                            self.updatePlaybackIntent(false)
                            self.publishPlaybackState(.paused)
                        }
                    } else if self.wantsPlayback,
                              itemStatus == .readyToPlay,
                              timeControlStatus == .waitingToPlayAtSpecifiedRate {
                        self.publishPlaybackState(.buffering)
                        self.scheduleTerminalStallWatchdog(reason: "rate-waiting")
                    }
                }
            }
        ]
    }

    private func observeCurrentItem(_ item: AVPlayerItem) {
        itemObservers = [
            item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                let status = item.status
                let rawErrorMessage = item.error?.localizedDescription
                Task { @MainActor [weak self] in
                    guard let self, self.isCurrentPlayerItem(item) else { return }
                    switch status {
                    case .readyToPlay:
                        self.handleCurrentItemReadyToPlay(item)
                    case .failed:
                        self.itemReadinessTimeoutTask?.cancel()
                        self.itemReadinessTimeoutTask = nil
                        self.cancelTerminalStallWatchdog()
                        self.logPlayerItemFailure(item)
                        self.lastPlaybackFailureReason = self.playbackFailureReason(
                            for: item,
                            fallback: rawErrorMessage
                        )
                        let errorMessage = self.normalizedPlaybackFailureMessage(for: item, fallback: rawErrorMessage)
                        if await self.recoverFromPlaybackFailureIfPossible(
                            item: item,
                            errorMessage: errorMessage,
                            reason: "status"
                        ) {
                            return
                        }
                        self.publishPlaybackState(.failed(errorMessage))
                    case .unknown:
                        break
                    @unknown default:
                        break
                    }
                }
            },
            item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
                let isPlaybackLikelyToKeepUp = item.isPlaybackLikelyToKeepUp
                Task { @MainActor [weak self] in
                    guard let self, self.wantsPlayback, self.isCurrentPlayerItem(item) else { return }
                    if isPlaybackLikelyToKeepUp {
                        self.cancelTerminalStallWatchdog()
                        self.beginPlayback()
                        self.publishPlaybackState(.playing)
                        self.maybeReleaseSeekProtectionIfReady(for: item, reason: "keepup")
                    } else {
                        self.publishPlaybackState(.buffering)
                        self.scheduleTerminalStallWatchdog(reason: "keepup-false")
                    }
                }
            },
            item.observe(\.loadedTimeRanges, options: [.initial, .new]) { [weak self] item, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isCurrentPlayerItem(item) else { return }
                    self.handleLoadedTimeRangesChanged(for: item)
                }
            },
            item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] item, _ in
                let isPlaybackBufferEmpty = item.isPlaybackBufferEmpty
                Task { @MainActor [weak self] in
                    guard let self,
                          self.wantsPlayback,
                          isPlaybackBufferEmpty,
                          self.isCurrentPlayerItem(item)
                    else { return }
                    self.publishPlaybackState(.buffering)
                    self.scheduleTerminalStallWatchdog(reason: "buffer-empty")
                }
            },
            item.observe(\.seekableTimeRanges, options: [.new]) { [weak self] item, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isCurrentPlayerItem(item) else { return }
                    self.seekDirectLiveHLSToLiveEdgeIfNeeded(item)
                }
            }
        ]

        itemEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isCurrentPlayerItem(item) else { return }
                self.cancelTerminalStallWatchdog()
                self.wantsPlayback = false
                self.publishPlaybackState(.ended)
            }
        }

        itemFailedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] notification in
            let rawErrorMessage = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?
                .localizedDescription
            Task { @MainActor [weak self] in
                guard let self, self.isCurrentPlayerItem(item) else { return }
                self.cancelTerminalStallWatchdog()
                self.logPlayerItemFailure(item)
                self.lastPlaybackFailureReason = self.playbackFailureReason(
                    for: item,
                    fallback: rawErrorMessage
                )
                let errorMessage = self.normalizedPlaybackFailureMessage(for: item, fallback: rawErrorMessage)
                if await self.recoverFromPlaybackFailureIfPossible(
                    item: item,
                    errorMessage: errorMessage,
                    reason: "failedToEnd"
                ) {
                    return
                }
                self.publishPlaybackState(.failed(errorMessage))
            }
        }

        itemStalledObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      self.wantsPlayback,
                      self.isCurrentPlayerItem(item)
                else { return }
                self.publishPlaybackState(.buffering)
                self.scheduleTerminalStallWatchdog(reason: "playback-stalled")
            }
        }

        itemAccessLogObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemNewAccessLogEntry,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isCurrentPlayerItem(item) else { return }
                self.recordAccessLogEntry(for: item)
            }
        }
    }

    private func logPlayerItemFailure(_ item: AVPlayerItem) {
        let event = item.errorLog()?.events.last
        PlayerMetricsLog.logger.error(
            "playerItemFailed error=\(item.error?.localizedDescription ?? "-", privacy: .public) status=\(event?.errorStatusCode ?? 0, privacy: .public) domain=\(event?.errorDomain ?? "-", privacy: .public) comment=\(event?.errorComment ?? "-", privacy: .public) uri=\(event?.uri ?? "-", privacy: .private)"
        )
    }

    private func normalizedPlaybackFailureMessage(for item: AVPlayerItem, fallback: String?) -> String? {
        if let reason = hlsBridge?.recentRemoteFailureReason() {
            return reason.playbackMessage
        }
        if let statusCode = item.errorLog()?.events.last?.errorStatusCode,
           let message = HLSBridgeRemoteFailure.playbackMessage(forHTTPStatus: statusCode) {
            return message
        }
        guard let fallback, !fallback.isEmpty else { return nil }
        return fallback
    }

    private func playbackFailureReason(for item: AVPlayerItem, fallback: String?) -> HLSBridgeFailureReason? {
        if let reason = hlsBridge?.recentRemoteFailureReason() {
            return reason
        }
        if let statusCode = item.errorLog()?.events.last?.errorStatusCode {
            return HLSBridgeRemoteFailure.reason(forHTTPStatus: statusCode)
        }
        if let error = item.error {
            return HLSBridgeRemoteFailure.reason(for: error)
        }
        guard let fallback, !fallback.isEmpty else { return nil }
        return HLSBridgeFailureReason(
            layer: .avPlayerItem,
            category: .unknown,
            statusCode: nil,
            urlHost: nil,
            rangeDescription: nil,
            underlyingDescription: fallback
        )
    }

    private func prepareFailureReason(for error: Error, source: PlayerStreamSource) -> HLSBridgeFailureReason {
        if error is CancellationError {
            return HLSBridgeFailureReason(
                layer: .local,
                category: .cancelled,
                statusCode: nil,
                urlHost: sourceFailureHost(source),
                rangeDescription: nil,
                underlyingDescription: error.localizedDescription
            )
        }
        if let failure = error as? HLSBridgeRemoteFailure {
            return failure.reason
        }
        if let streamError = error as? HLSRangeStreamError {
            return HLSBridgeRemoteFailure.reason(for: streamError)
        }
        if let urlError = error as? URLError {
            return HLSBridgeFailureReason(
                layer: .remoteRange,
                category: HLSBridgeRemoteFailure.reason(for: urlError).category,
                statusCode: nil,
                urlHost: sourceFailureHost(source),
                rangeDescription: nil,
                underlyingDescription: urlError.localizedDescription
            )
        }
        let category: HLSBridgeRemoteFailureCategory
        if let engineError = error as? PlayerEngineError {
            switch engineError {
            case .missingVideoURL, .missingAudioURL:
                category = .invalidResponse
            case .unsupportedMedia:
                category = .hardwareDecodeRejected
            }
        } else {
            category = HLSBridgeRemoteFailure.reason(for: error).category
        }
        return HLSBridgeFailureReason(
            layer: .local,
            category: category,
            statusCode: nil,
            urlHost: sourceFailureHost(source),
            rangeDescription: nil,
            underlyingDescription: error.localizedDescription
        )
    }

    private func sourceFailureHost(_ source: PlayerStreamSource) -> String? {
        let sourceURL = source.playbackContentMode == .audioOnly
            ? source.audioURL
            : source.videoURL
        return sourceURL?.host?.lowercased()
    }

    private func shouldAttemptSameSourceRecovery(item: AVPlayerItem, errorMessage: String?) -> Bool {
        if let lastPlaybackFailureReason,
           !lastPlaybackFailureReason.allowsSameSourceRecovery {
            return false
        }
        if let statusCode = item.errorLog()?.events.last?.errorStatusCode,
           !HLSBridgeRemoteFailure.allowsSameSourceRecovery(forHTTPStatus: statusCode) {
            return false
        }
        if let errorMessage,
           !HLSBridgeRemoteFailure.allowsSameSourceRecovery(forPlaybackMessage: errorMessage) {
            return false
        }
        return true
    }

    private func recoverFromPlaybackFailureIfPossible(
        item: AVPlayerItem,
        errorMessage: String?,
        reason: String
    ) async -> Bool {
        guard !isPlaybackFailureRecoveryInProgress else {
            PlayerMetricsLog.record(
                .network,
                metricsID: source?.metricsID ?? "-",
                title: source?.title,
                message: "hlsRecover=alreadyInProgress reason=\(reason)"
            )
            return true
        }
        guard isCurrentPlayerItem(item),
              let source
        else { return false }
        let recoveryGeneration = playbackGeneration
        guard source.audioURL != nil || hlsBridge != nil else { return false }
        guard shouldAttemptSameSourceRecovery(item: item, errorMessage: errorMessage) else {
            await recordPlaybackFailureAvoidance(
                source: source,
                reason: reason,
                errorMessage: errorMessage
            )
            guard isCurrentPlayerItem(item),
                  recoveryGeneration == playbackGeneration
            else { return true }
            PlayerMetricsLog.record(
                .network,
                metricsID: source.metricsID,
                title: source.title,
                message: "hlsRecover=skip reason=\(reason) error=\(errorMessage ?? "-")"
            )
            return false
        }

        let recoveryKey = playbackFailureRecoveryKey(for: source)
        let attempt = playbackFailureRecoveryAttempts[recoveryKey] ?? 0
        guard attempt < 2 else { return false }
        playbackFailureRecoveryAttempts[recoveryKey] = attempt + 1
        isPlaybackFailureRecoveryInProgress = true
        defer { isPlaybackFailureRecoveryInProgress = false }

        let restoreTime = snapshot(durationHint: source.durationHint).currentTime
            ?? displayTime(fromPlayerTime: player.currentTime().seconds)
        let shouldResume = wantsPlayback || player.rate > 0
        let restoreRate = currentRate
        publishPlaybackState(.buffering)
        onLoadingProgressChange?(0.16)
        await recordPlaybackFailureAvoidance(
            source: source,
            reason: reason,
            errorMessage: errorMessage
        )
        guard isCurrentPlayerItem(item),
              recoveryGeneration == playbackGeneration
        else { return true }
        PlayerMetricsLog.record(
            .network,
            metricsID: source.metricsID,
            title: source.title,
            message: "hlsRecover reason=\(reason) attempt=\(attempt + 1) time=\(String(format: "%.2fs", max(restoreTime, 0)))"
        )

        let preparedRecoveryGeneration = recoveryGeneration &+ 1
        do {
            try await prepare(source: source.withResumeTime(max(restoreTime, 0)))
            guard !Task.isCancelled,
                  !isStopped,
                  playbackGeneration == preparedRecoveryGeneration
            else { return true }
            setPlaybackRate(Double(restoreRate))
            if restoreTime > 0.35 {
                _ = seek(toTime: restoreTime)
            }
            if shouldResume {
                play()
            } else {
                pause()
            }
            PlayerMetricsLog.record(
                .network,
                metricsID: source.metricsID,
                title: source.title,
                message: "hlsRecover=ok attempt=\(attempt + 1)"
            )
            return true
        } catch {
            guard !Task.isCancelled,
                  !isStopped,
                  playbackGeneration == preparedRecoveryGeneration
            else { return true }
            PlayerMetricsLog.logger.error(
                "hlsRecoverFailed attempt=\(attempt + 1, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            PlayerMetricsLog.record(
                .network,
                metricsID: source.metricsID,
                title: source.title,
                message: "hlsRecover=failed attempt=\(attempt + 1) \(error.localizedDescription)"
            )
            return false
        }
    }

    private func recordPlaybackFailureAvoidance(
        source: PlayerStreamSource,
        reason: String,
        errorMessage: String?
    ) async {
        var seenHosts = Set<String>()
        var hosts = [String]()
        for url in [source.videoURL, source.audioURL] {
            guard let url,
                  let rawHost = URLComponents(url: url, resolvingAgainstBaseURL: false)?.host
            else { continue }
            let host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !host.isEmpty, seenHosts.insert(host).inserted else { continue }
            hosts.append(host)
        }
        let messageReason = [
            "player-\(reason)",
            errorMessage?.isEmpty == false ? "error" : nil
        ]
        .compactMap { $0 }
        .joined(separator: "-")

        for host in hosts {
            await HLSSourcePreferenceCache.shared.recordSessionAvoidance(
                host: host,
                reason: messageReason,
                metricsID: source.metricsID,
                title: source.title
            )
        }
    }

    private func playbackFailureRecoveryKey(for source: PlayerStreamSource) -> String {
        [
            source.metricsID,
            source.videoURL?.absoluteString ?? "-",
            source.audioURL?.absoluteString ?? "-"
        ].joined(separator: "|")
    }

    private func recordAccessLogEntry(for item: AVPlayerItem) {
        guard let source, let event = item.accessLog()?.events.last else { return }
        let observedKbps = Int((event.observedBitrate / 1_000).rounded())
        let indicatedKbps = Int((event.indicatedBitrate / 1_000).rounded())
        let transferMilliseconds = Int((event.transferDuration * 1_000).rounded())
        let startupMilliseconds = Int((event.startupTime * 1_000).rounded())
        let server = event.serverAddress ?? "-"
        let stallDelta = max(event.numberOfStalls - lastRecordedAccessLogStallCount, 0)
        lastRecordedAccessLogStallCount = max(lastRecordedAccessLogStallCount, event.numberOfStalls)
        let feedbackHost = recordPlaybackURLFeedback(
            source: source,
            observedKilobitsPerSecond: observedKbps,
            transferMilliseconds: transferMilliseconds,
            bytes: event.numberOfBytesTransferred,
            stallDelta: stallDelta
        )
        let message = [
            "observedKbps=\(max(observedKbps, 0))",
            "indicatedKbps=\(max(indicatedKbps, 0))",
            "stalls=\(event.numberOfStalls)",
            "stallDelta=\(stallDelta)",
            "transfer=\(max(transferMilliseconds, 0))ms",
            "startup=\(max(startupMilliseconds, 0))ms",
            "bytes=\(event.numberOfBytesTransferred)",
            "requests=\(event.numberOfMediaRequests)",
            "host=\(feedbackHost ?? "-")",
            "server=\(server)"
        ].joined(separator: " ")
        PlayerMetricsLog.record(
            .accessLog,
            metricsID: source.metricsID,
            title: source.title,
            message: message
        )
    }

    private func recordPlaybackURLFeedback(
        source: PlayerStreamSource,
        observedKilobitsPerSecond: Int,
        transferMilliseconds: Int,
        bytes: Int64,
        stallDelta: Int
    ) -> String? {
        guard observedKilobitsPerSecond > 0 || bytes > 0 || stallDelta > 0 else { return nil }
        guard let videoURL = source.videoURL ?? source.audioURL else { return nil }
        PlaybackURLPreferenceStore.shared.recordPlaybackFeedback(
            url: videoURL,
            observedKilobitsPerSecond: max(observedKilobitsPerSecond, 0),
            transferMilliseconds: max(transferMilliseconds, 0),
            bytes: max(bytes, 0),
            stallCount: stallDelta
        )
        if stallDelta > 0,
           let audioURL = source.audioURL,
           audioURL.host?.lowercased() != videoURL.host?.lowercased() {
            PlaybackURLPreferenceStore.shared.recordPlaybackFeedback(
                url: audioURL,
                observedKilobitsPerSecond: 0,
                transferMilliseconds: max(transferMilliseconds, 0),
                bytes: 0,
                stallCount: stallDelta
            )
        }
        if stallDelta > 0 {
            let videoHost = videoURL.host
            let audioHost = source.audioURL?.host
            Task {
                await HLSSourcePreferenceCache.shared.recordSessionAvoidance(
                    host: videoHost,
                    reason: "accesslog-stall-\(stallDelta)",
                    metricsID: source.metricsID,
                    title: source.title
                )
                if audioHost?.lowercased() != videoHost?.lowercased() {
                    await HLSSourcePreferenceCache.shared.recordSessionAvoidance(
                        host: audioHost,
                        reason: "accesslog-stall-\(stallDelta)",
                        metricsID: source.metricsID,
                        title: source.title
                    )
                }
            }
        }
        return videoURL.host
    }

    private func observeLayerReadyForDisplay(_ layer: AVPlayerLayer) {
        layerReadyForDisplayObserver = layer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] layer, _ in
            guard layer.isReadyForDisplay else { return }
            let layerIdentity = ObjectIdentifier(layer)
            Task { @MainActor [weak self] in
                guard let self,
                      !self.isStopped,
                      self.isCurrentPlayerLayer(layerIdentity),
                      self.player.currentItem === self.playerItem
                else { return }
                self.reportFirstFrameIfPossible()
            }
        }
    }

    private func observeControllerReadyForDisplay(_ controller: AVPlayerViewController) {
        guard controllerReadyForDisplayObserver == nil else { return }
        controllerReadyForDisplayObserver = controller.observe(\.isReadyForDisplay, options: [.new]) { [weak self] controller, _ in
            let controllerIdentity = ObjectIdentifier(controller)
            Task { @MainActor [weak self, weak controller] in
                guard let self,
                      controller?.isReadyForDisplay == true,
                      !self.isStopped,
                      self.isCurrentPlayerViewController(controllerIdentity),
                      self.player.currentItem === self.playerItem
                else { return }
                self.reportFirstFrameIfPossible()
            }
        }
    }

    private func ensurePeriodicTimeObserver() {
        guard periodicTimeObserver == nil else { return }
        periodicTimeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            let seconds = time.seconds
            Task { @MainActor [weak self] in
                guard let self,
                      !self.isStopped,
                      self.player.currentItem === self.playerItem
                else { return }
                self.reportFirstFrameIfPossible(currentTime: self.displayTime(fromPlayerTime: seconds))
            }
        }
    }

    private func removePeriodicTimeObserver() {
        guard let periodicTimeObserver else { return }
        player.removeTimeObserver(periodicTimeObserver)
        self.periodicTimeObserver = nil
    }

    private func removeCurrentItemObservers() {
        itemObservers.removeAll()
        if let itemEndObserver {
            NotificationCenter.default.removeObserver(itemEndObserver)
            self.itemEndObserver = nil
        }
        if let itemFailedObserver {
            NotificationCenter.default.removeObserver(itemFailedObserver)
            self.itemFailedObserver = nil
        }
        if let itemStalledObserver {
            NotificationCenter.default.removeObserver(itemStalledObserver)
            self.itemStalledObserver = nil
        }
        if let itemAccessLogObserver {
            NotificationCenter.default.removeObserver(itemAccessLogObserver)
            self.itemAccessLogObserver = nil
        }
    }

    private func beginSeekTransaction(
        targetDisplayTime: TimeInterval?
    ) -> Int {
        seekGeneration &+= 1
        isPerformingSeek = true
        if let targetDisplayTime, targetDisplayTime.isFinite, targetDisplayTime >= 0 {
            seekProtectionTargetTime = targetDisplayTime
        } else {
            seekProtectionTargetTime = nil
        }
        if let item = player.currentItem, let source {
            applySeekProtection(to: item, source: source, shouldRecordMetric: true)
        }
        onLoadingProgressChange?(0.12)
        return seekGeneration
    }

    private func finishSeekTransaction(generation: Int, finished: Bool, shouldResume: Bool) {
        guard !isStopped else { return }
        guard generation == seekGeneration else { return }
        isPerformingSeek = false
        if finished {
            lastSeekFinishedAt = CACurrentMediaTime()
        }
        if let item = player.currentItem {
            updateLoadingProgress(for: item)
        }
        guard finished else {
            shouldPrerollPausedRecoveryAfterSeek = false
            releaseSeekProtection(reason: "cancelled")
            return
        }
        guard shouldResume else {
            releaseSeekProtection(reason: "paused")
            startPausedRecoveryPrerollIfNeeded()
            return
        }
        shouldPrerollPausedRecoveryAfterSeek = false
        scheduleSeekProtectionRelease(generation: generation)
        beginPlayback()
        if let item = player.currentItem {
            maybeReleaseSeekProtectionIfReady(for: item, reason: "finish")
        }
    }

    private func startPausedRecoveryPrerollIfNeeded() {
        guard shouldPrerollPausedRecoveryAfterSeek else { return }
        shouldPrerollPausedRecoveryAfterSeek = false
        guard !isStopped,
              !wantsPlayback,
              let item = playerItem,
              player.currentItem === item
        else { return }

        let generation = playbackGeneration
        let startedAt = CACurrentMediaTime()
        player.preroll(atRate: max(currentRate, 1)) { [weak self, weak item] finished in
            Task { @MainActor [weak self, weak item] in
                guard let self,
                      let item,
                      finished,
                      !self.wantsPlayback,
                      self.isCurrentPlaybackGeneration(generation),
                      self.isCurrentPlayerItem(item)
                else { return }
                self.onLoadingProgressChange?(0.92)
                self.publishPlaybackState(.ready)
                self.recoverSurface()
                self.deactivateAudioSessionIfPossible()
                guard let source = self.source else { return }
                self.recordPrepareStage(
                    source: source,
                    stage: "paused-recovery-preroll",
                    startedAt: startedAt
                )
            }
        }
    }

    private var shouldReportRenderedVideoTimeForSeekRecovery: Bool {
        guard source?.playbackContentMode != .audioOnly else { return false }
        if isPerformingSeek || isSeekProtectionActive {
            return true
        }
        guard let lastSeekFinishedAt else { return false }
        return CACurrentMediaTime() - lastSeekFinishedAt <= 1.2
    }

    private func applySeekProtection(
        to item: AVPlayerItem,
        source: PlayerStreamSource,
        shouldRecordMetric: Bool
    ) {
        guard !isDirectLiveHLS else { return }
        let wasActive = isSeekProtectionActive
        isSeekProtectionActive = true
        seekProtectionAppliedAt = CACurrentMediaTime()
        seekProtectionReleaseTask?.cancel()
        seekProtectionReleaseTask = nil
        let environment = PlaybackEnvironment.current
        let currentBuffer = preferredForwardBufferDuration(for: source, environment: environment)
        let protectedBuffer = min(max(currentBuffer + 0.8, 1.4), 3.0)
        item.preferredForwardBufferDuration = protectedBuffer
        if !wasActive {
            automaticallyWaitsBeforeSeekProtection = player.automaticallyWaitsToMinimizeStalling
        }
        player.automaticallyWaitsToMinimizeStalling = false
        if let bandwidth = source.videoStream?.bandwidth, bandwidth > 0 {
            let multiplier: Double = currentRate >= 1.75 ? 0.9 : 1.0
            item.preferredPeakBitRate = Double(bandwidth) * multiplier
        }
        guard shouldRecordMetric, !wasActive else { return }
        PlayerMetricsLog.record(
            .network,
            metricsID: source.metricsID,
            title: source.title,
            message: "seekProtect=on buffer=\(String(format: "%.1f", protectedBuffer))s peak=\(Int(item.preferredPeakBitRate.rounded()))"
        )
    }

    private func scheduleSeekProtectionRelease(generation: Int) {
        seekProtectionReleaseTask?.cancel()
        seekProtectionReleaseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.seekProtectionReleaseDelayNanoseconds)
            guard let self,
                  !Task.isCancelled,
                  !self.isStopped,
                  generation == self.seekGeneration
            else { return }
            self.releaseSeekProtection(reason: "timeout")
        }
    }

    private func releaseSeekProtection(reason: String) {
        guard isSeekProtectionActive else { return }
        isSeekProtectionActive = false
        seekProtectionReleaseTask?.cancel()
        seekProtectionReleaseTask = nil
        let elapsedMilliseconds = seekProtectionAppliedAt
            .map { Int(PlayerMetricsLog.elapsedMilliseconds(since: $0).rounded()) }
        seekProtectionTargetTime = nil
        seekProtectionAppliedAt = nil
        if let automaticallyWaitsBeforeSeekProtection {
            player.automaticallyWaitsToMinimizeStalling = automaticallyWaitsBeforeSeekProtection
            self.automaticallyWaitsBeforeSeekProtection = nil
        } else {
            player.automaticallyWaitsToMinimizeStalling = !isStartupFastStartActive && !isDirectLiveHLS
        }
        guard let item = player.currentItem, let source else { return }
        configureStartupBuffering(for: item, source: source)
        applyRateAwareBuffering()
        PlayerMetricsLog.record(
            .network,
            metricsID: source.metricsID,
            title: source.title,
            message: "seekProtect=off reason=\(reason) elapsed=\(elapsedMilliseconds.map { "\($0)ms" } ?? "-") buffer=\(String(format: "%.1f", item.preferredForwardBufferDuration))s peak=\(Int(item.preferredPeakBitRate.rounded()))"
        )
    }

    private func scheduleTerminalStallWatchdog(reason: String) {
        guard terminalStallTask == nil,
              wantsPlayback,
              !isPerformingSeek,
              !isSeekProtectionActive,
              player.rate == 0,
              player.timeControlStatus == .waitingToPlayAtSpecifiedRate,
              let item = player.currentItem,
              isCurrentPlayerItem(item),
              item.status == .readyToPlay,
              !item.isPlaybackLikelyToKeepUp
        else { return }
        terminalStallGeneration &+= 1
        let stallGeneration = terminalStallGeneration
        let generation = playbackGeneration
        let startedAt = CACurrentMediaTime()
        terminalStallTask = Task { @MainActor [weak self, weak item] in
            try? await Task.sleep(nanoseconds: Self.terminalStallDelayNanoseconds)
            guard let self else { return }
            defer {
                if self.terminalStallGeneration == stallGeneration {
                    self.terminalStallTask = nil
                }
            }
            guard let item,
                  !Task.isCancelled,
                  self.terminalStallGeneration == stallGeneration,
                  self.shouldTreatPlaybackAsTerminallyStalled(item: item, generation: generation)
            else { return }
            await self.handleTerminalPlaybackStall(item: item, reason: reason, startedAt: startedAt)
        }
    }

    private func cancelTerminalStallWatchdog() {
        terminalStallGeneration &+= 1
        terminalStallTask?.cancel()
        terminalStallTask = nil
    }

    private func shouldTreatPlaybackAsTerminallyStalled(item: AVPlayerItem, generation: Int) -> Bool {
        guard isCurrentPlaybackGeneration(generation),
              isCurrentPlayerItem(item),
              wantsPlayback,
              !isPerformingSeek,
              !isSeekProtectionActive,
              player.rate == 0,
              player.timeControlStatus == .waitingToPlayAtSpecifiedRate,
              item.status == .readyToPlay,
              !item.isPlaybackLikelyToKeepUp
        else { return false }
        return bufferAhead(for: item) < 0.45
    }

    private func handleTerminalPlaybackStall(
        item: AVPlayerItem,
        reason: String,
        startedAt: CFTimeInterval
    ) async {
        guard isCurrentPlayerItem(item), let source else { return }
        let elapsedMilliseconds = Int(PlayerMetricsLog.elapsedMilliseconds(since: startedAt).rounded())
        let message = "播放长时间无进展"
        lastPlaybackFailureReason = HLSBridgeFailureReason(
            layer: .avPlayerItem,
            category: .terminalStall,
            statusCode: nil,
            urlHost: nil,
            rangeDescription: nil,
            underlyingDescription: message
        )
        PlayerMetricsLog.logger.error(
            "avPlayerTerminalStall reason=\(reason, privacy: .public) elapsedMs=\(elapsedMilliseconds, privacy: .public) id=\(source.metricsID, privacy: .public)"
        )
        PlayerMetricsLog.record(
            .network,
            metricsID: source.metricsID,
            title: source.title,
            message: "terminalStall reason=\(reason) elapsed=\(elapsedMilliseconds)ms buffer=\(String(format: "%.2fs", bufferAhead(for: item)))"
        )
        if await recoverFromPlaybackFailureIfPossible(
            item: item,
            errorMessage: message,
            reason: "terminalStall-\(reason)"
        ) {
            return
        }
        guard isCurrentPlayerItem(item) else { return }
        publishPlaybackState(.failed(message))
    }

    private func handleLoadedTimeRangesChanged(for item: AVPlayerItem) {
        updateLoadingProgress(for: item)
        if wantsPlayback,
           player.timeControlStatus == .waitingToPlayAtSpecifiedRate,
           !item.isPlaybackLikelyToKeepUp {
            scheduleTerminalStallWatchdog(reason: "buffer-waiting")
        } else if player.rate > 0 || item.isPlaybackLikelyToKeepUp {
            cancelTerminalStallWatchdog()
        }
        maybeReleaseSeekProtectionIfReady(for: item, reason: "buffer")
    }

    private func maybeReleaseSeekProtectionIfReady(for item: AVPlayerItem? = nil, reason: String) {
        guard isSeekProtectionActive, !isPerformingSeek else { return }
        let resolvedItem = item ?? player.currentItem
        guard let resolvedItem, player.currentItem === resolvedItem else { return }
        if player.timeControlStatus == .playing {
            releaseSeekProtection(reason: reason)
            return
        }
        if resolvedItem.isPlaybackLikelyToKeepUp {
            releaseSeekProtection(reason: reason)
            return
        }
        guard let targetTime = seekProtectionTargetTime else { return }
        let coverage = seekProtectionBufferCoverage(for: resolvedItem, around: targetTime)
        guard coverage >= 0.62 else { return }
        releaseSeekProtection(reason: "\(reason)-coverage\(Int((coverage * 100).rounded()))")
    }

    private func seekProtectionBufferCoverage(for item: AVPlayerItem, around targetTime: TimeInterval) -> Double {
        PlayerPlaybackSnapshot(
            currentTime: nil,
            duration: nil,
            isPlaying: player.rate > 0,
            isSeekable: true,
            bufferedRanges: bufferedRanges(for: item)
        )
        .bufferedCoverageProgress(around: targetTime, preroll: 0.25, forward: 1.45)
    }

    private func updateLoadingProgress(for item: AVPlayerItem) {
        guard player.currentItem === item else { return }
        let bufferAhead = bufferAhead(for: item)
        let targetBuffer = max(item.preferredForwardBufferDuration, 1)
        let progress = min(max(bufferAhead / targetBuffer, item.isPlaybackBufferEmpty ? 0 : 0.12), 1)
        onLoadingProgressChange?(progress)
    }

    private func bufferAhead(for item: AVPlayerItem) -> TimeInterval {
        guard player.currentItem === item else { return 0 }
        let currentSeconds = player.currentTime().seconds
        guard currentSeconds.isFinite, currentSeconds >= 0 else { return 0 }
        let ranges = item.loadedTimeRanges
            .map(\.timeRangeValue)
            .compactMap { range -> (start: TimeInterval, end: TimeInterval)? in
                let start = range.start.seconds
                let end = range.end.seconds
                guard start.isFinite, end.isFinite, end > start else { return nil }
                return (start, end)
            }
            .sorted { lhs, rhs in
                if lhs.start == rhs.start {
                    return lhs.end < rhs.end
                }
                return lhs.start < rhs.start
            }
        guard !ranges.isEmpty else { return 0 }
        let tolerance = Self.loadedRangeContinuityTolerance
        guard let containingIndex = ranges.firstIndex(where: { range in
            range.start - tolerance <= currentSeconds && currentSeconds <= range.end + tolerance
        }) else { return 0 }

        var bufferedEnd = max(ranges[containingIndex].end, currentSeconds)
        for range in ranges[(containingIndex + 1)...] {
            guard range.start <= bufferedEnd + tolerance else { break }
            bufferedEnd = max(bufferedEnd, range.end)
        }
        return max(bufferedEnd - currentSeconds, 0)
    }

    private func bufferedRanges(for item: AVPlayerItem) -> [PlayerBufferedRange] {
        item.loadedTimeRanges
            .map(\.timeRangeValue)
            .compactMap { range -> PlayerBufferedRange? in
                let start = displayTime(fromPlayerTime: range.start.seconds)
                let end = displayTime(fromPlayerTime: range.end.seconds)
                guard start.isFinite, end.isFinite, end > start else { return nil }
                return PlayerBufferedRange(start: max(start, 0), end: max(end, 0))
            }
    }

    private func handleTimeControlStatus(_ status: AVPlayer.TimeControlStatus) {
        guard !isStopped, player.currentItem != nil else { return }
        switch status {
        case .paused:
            publishPlaybackState((wantsPlayback || isPerformingSeek) ? .buffering : .paused)
            if !(wantsPlayback || isPerformingSeek) {
                cancelTerminalStallWatchdog()
            }
        case .waitingToPlayAtSpecifiedRate:
            if wantsPlayback || isPerformingSeek {
                publishPlaybackState(.buffering)
                scheduleTerminalStallWatchdog(reason: "timeControl-waiting")
            }
        case .playing:
            cancelTerminalStallWatchdog()
            updatePlaybackIntent(true)
            publishPlaybackState(.playing)
            reportFirstFrameIfPossible()
            maybeReleaseSeekProtectionIfReady(reason: "playing")
        @unknown default:
            break
        }
    }

    private func updatePlaybackIntent(_ wantsPlayback: Bool) {
        guard self.wantsPlayback != wantsPlayback else { return }
        self.wantsPlayback = wantsPlayback
        onPlaybackIntentChange?(wantsPlayback)
    }

    private func reportFirstFrameIfPossible(
        currentTime: TimeInterval? = nil,
        allowsNativeHDRVideoOverlay: Bool = false
    ) {
        guard !isStopped, let item = player.currentItem else { return }
        guard !didReportFirstFrame else { return }
        if source?.playbackContentMode == .audioOnly {
            guard item.status == .readyToPlay,
                  player.rate > 0 || player.timeControlStatus == .playing
            else { return }
            didReportFirstFrame = true
            cancelTerminalStallWatchdog()
            cancelFirstFrameWatchdog()
            removePeriodicTimeObserver()
            let resolvedTime = currentTime ?? displayTime(fromPlayerTime: player.currentTime().seconds)
            onFirstFrame?(resolvedTime.isFinite ? max(resolvedTime, 0) : 0)
            restoreSteadyStateBufferingAfterFirstFrame()
            return
        }
        let isBaseLayerReady = playerViewController?.isReadyForDisplay == true
            || playerLayer?.isReadyForDisplay == true
        let isNativeHDRLayerReady = allowsNativeHDRVideoOverlay && nativeDolbyVideoOverlay.isReadyForDisplay
        // A layer can retain `isReadyForDisplay == true` across a long lock or an
        // item replacement even while it has no fresh drawable. Pair it with a
        // new video-output frame so first-frame and recovery state cannot expose
        // a black AVPlayerLayer prematurely.
        let hasFreshBaseVideoFrame = sampledRenderedVideoTime(cachesFrameImage: true) != nil
        guard (isBaseLayerReady && hasFreshBaseVideoFrame) || isNativeHDRLayerReady
        else { return }
        didReportFirstFrame = true
        cancelTerminalStallWatchdog()
        cancelFirstFrameWatchdog()
        removePeriodicTimeObserver()
        scheduleRecoveryFrameCacheSeed()
        let resolvedTime = currentTime ?? displayTime(fromPlayerTime: player.currentTime().seconds)
        onFirstFrame?(resolvedTime.isFinite ? max(resolvedTime, 0) : 0)
        restoreSteadyStateBufferingAfterFirstFrame()
    }

    private func scheduleRecoveryFrameCacheSeed() {
        recoveryFrameCacheTask?.cancel()
        let generation = playbackGeneration
        let item = playerItem
        recoveryFrameCacheTask = Task { @MainActor [weak self, weak item] in
            // The output may not be readable in the same run loop as the layer's
            // first drawable. A few short retries provide a frame for lock-screen
            // recovery without continuously converting video frames to UIImage.
            for delay: UInt64 in [40_000_000, 140_000_000, 420_000_000, 900_000_000] {
                try? await Task.sleep(nanoseconds: delay)
                guard let self,
                      !Task.isCancelled,
                      self.isCurrentPlaybackGeneration(generation),
                      self.playerItem === item,
                      self.player.currentItem === item
                else { return }
                if let image = self.currentVideoFrameImage(), !image.biliLooksLikeBlackFrame {
                    self.lastVideoFrameImage = image
                    self.recoveryFrameCacheTask = nil
                    return
                }
            }
            guard let self, self.isCurrentPlaybackGeneration(generation) else { return }
            self.recoveryFrameCacheTask = nil
        }
    }

    private func scheduleFirstFrameWatchdogIfNeeded(reason: String) {
        guard firstFrameWatchdogTask == nil,
              !didReportFirstFrame,
              wantsPlayback,
              source?.dynamicRange.isHDR == true,
              let item = player.currentItem,
              isCurrentPlayerItem(item)
        else { return }
        firstFrameWatchdogGeneration &+= 1
        let generation = playbackGeneration
        let watchdogGeneration = firstFrameWatchdogGeneration
        let startedAt = CACurrentMediaTime()
        firstFrameWatchdogTask = Task { @MainActor [weak self, weak item] in
            try? await Task.sleep(nanoseconds: Self.hdrFirstFrameTimeoutNanoseconds)
            guard let self else { return }
            defer {
                if self.firstFrameWatchdogGeneration == watchdogGeneration {
                    self.firstFrameWatchdogTask = nil
                }
            }
            guard let item,
                  !Task.isCancelled,
                  !self.didReportFirstFrame,
                  self.wantsPlayback,
                  self.isCurrentPlaybackGeneration(generation),
                  self.isCurrentPlayerItem(item),
                  self.source?.dynamicRange.isHDR == true
            else { return }
            if self.nativeDolbyVideoOverlay.isReadyForDisplay {
                self.reportFirstFrameIfPossible(allowsNativeHDRVideoOverlay: true)
                return
            }
            await self.handleHDRFirstFrameTimeout(item: item, reason: reason, startedAt: startedAt)
        }
    }

    private func cancelFirstFrameWatchdog() {
        firstFrameWatchdogGeneration &+= 1
        firstFrameWatchdogTask?.cancel()
        firstFrameWatchdogTask = nil
    }

    private func handleHDRFirstFrameTimeout(
        item: AVPlayerItem,
        reason: String,
        startedAt: CFTimeInterval
    ) async {
        guard isCurrentPlayerItem(item), let source else { return }
        let elapsedMilliseconds = Int(PlayerMetricsLog.elapsedMilliseconds(since: startedAt).rounded())
        let dynamicRangeTitle = source.dynamicRange == .dolbyVision ? "杜比视界" : "HDR"
        let message = "\(dynamicRangeTitle) 首帧超时"
        lastPlaybackFailureReason = HLSBridgeFailureReason(
            layer: .avPlayerItem,
            category: .decoderFailed,
            statusCode: nil,
            urlHost: source.videoURL?.host?.lowercased(),
            rangeDescription: nil,
            underlyingDescription: message
        )
        PlayerMetricsLog.logger.error(
            "avPlayerHDRFirstFrameTimeout dynamicRange=\(source.dynamicRange.rawValue, privacy: .public) reason=\(reason, privacy: .public) elapsedMs=\(elapsedMilliseconds, privacy: .public) id=\(source.metricsID, privacy: .public)"
        )
        PlayerMetricsLog.record(
            .network,
            metricsID: source.metricsID,
            title: source.title,
            message: "hdrFirstFrameTimeout dynamicRange=\(source.dynamicRange.rawValue) reason=\(reason) elapsed=\(elapsedMilliseconds)ms status=\(item.status.rawValue) keepUp=\(item.isPlaybackLikelyToKeepUp) buffer=\(String(format: "%.2fs", bufferAhead(for: item)))"
        )
        if await recoverFromPlaybackFailureIfPossible(
            item: item,
            errorMessage: message,
            reason: "hdrFirstFrameTimeout"
        ) {
            return
        }
        publishPlaybackState(.failed(message))
    }

    private func restoreSteadyStateBufferingAfterFirstFrame() {
        guard isStartupFastStartActive else { return }
        isStartupFastStartActive = false
        player.automaticallyWaitsToMinimizeStalling = !isDirectLiveHLS
        guard !isSeekProtectionActive,
              let item = player.currentItem,
              let source = self.source
        else { return }
        configureStartupBuffering(for: item, source: source)
        applyRateAwareBuffering()
        PlayerMetricsLog.record(
            .startupBreakdown,
            metricsID: source.metricsID,
            title: source.title,
            message: "bridge=steadyBuffer buffer=\(String(format: "%.2fs", item.preferredForwardBufferDuration)) waits=\(!isDirectLiveHLS)"
        )
    }

    private func publishPlaybackState(_ state: PlayerEnginePlaybackState) {
        switch state {
        case .buffering, .playing:
            scheduleFirstFrameWatchdogIfNeeded(reason: "state")
        default:
            break
        }
        guard state != lastPlaybackState else { return }
        lastPlaybackState = state
        onPlaybackStateChange?(state)
    }

    private func resolvedDuration(durationHint: TimeInterval?) -> TimeInterval {
        let itemDuration = player.currentItem?.duration.seconds ?? 0
        if mediaTimeOffset > 0 {
            if let durationHint, durationHint > 0 {
                return durationHint
            }
            if let sourceDurationHint = source?.durationHint, sourceDurationHint > 0 {
                return sourceDurationHint
            }
            if itemDuration.isFinite, itemDuration > mediaTimeOffset {
                return itemDuration - mediaTimeOffset
            }
        }
        if itemDuration.isFinite, itemDuration > 0 {
            return itemDuration
        }
        return durationHint ?? source?.durationHint ?? 0
    }

    private func alignedInteractiveSeekTime(_ displayTime: TimeInterval) -> TimeInterval {
        guard displayTime.isFinite, displayTime > 0 else { return 0 }
        guard let alignedTime = hlsBridge?.alignedSeekTime(near: displayTime),
              alignedTime.isFinite,
              alignedTime >= 0
        else {
            return displayTime
        }
        return alignedTime
    }

    private func warmSeekTargetIfNeeded(_ displayTime: TimeInterval) {
        guard displayTime.isFinite, displayTime >= 0 else { return }
        guard let hlsBridge else { return }
        seekWarmupGeneration &+= 1
        let generation = seekWarmupGeneration
        let metricsID = source?.metricsID
        seekWarmupTask?.cancel()
        seekWarmupTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await hlsBridge.warmSeekTarget(around: displayTime, metricsID: metricsID)
            guard !Task.isCancelled,
                  self.seekWarmupGeneration == generation
            else { return }
            self.seekWarmupTask = nil
        }
    }

    private func playerTime(fromDisplayTime time: TimeInterval) -> TimeInterval {
        guard mediaTimeOffset > 0 else { return time }
        return max(time, 0) + mediaTimeOffset
    }

    private func displayTime(fromPlayerTime time: TimeInterval) -> TimeInterval {
        guard time.isFinite, time >= 0 else { return time }
        guard mediaTimeOffset > 0 else { return time }
        return max(time - mediaTimeOffset, 0)
    }

    private static func makePlayerItem(
        source: PlayerStreamSource,
        onRemoteFailure: HLSRemoteFailureHandler? = nil
    ) async throws -> PreparedPlayerItem {
        try enforceHardwareDecodingCompatibility(for: source)

        let headers = source.httpHeaders

        if source.playbackContentMode == .audioOnly {
            guard let audioURL = source.audioURL else {
                throw BiliHLSManifestBuilderError.missingAudioURL
            }
            if source.audioStream?.segmentBase?.indexByteRange != nil {
                let manifest = try await BiliHLSManifestBuilder.make(
                    source: source,
                    shouldValidateHardwareDecoding: true,
                    includesAlternateVideoRenditions: false,
                    onRemoteFailure: onRemoteFailure
                )
                let asset = AVURLAsset(url: manifest.masterPlaylistURL)
                let item = AVPlayerItem(asset: asset)
                item.preferredForwardBufferDuration = PlaybackEnvironment.current.startupForwardBufferDuration
                return PreparedPlayerItem(
                    item: item,
                    bridge: manifest.bridge,
                    liveProxy: nil,
                    assets: [asset],
                    isDirectLiveHLS: false
                )
            }

            let asset = AVURLAsset(url: audioURL, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
            let item = AVPlayerItem(asset: asset)
            item.preferredForwardBufferDuration = PlaybackEnvironment.current.startupForwardBufferDuration
            return PreparedPlayerItem(item: item, bridge: nil, liveProxy: nil, assets: [asset], isDirectLiveHLS: false)
        }

        guard let videoURL = source.videoURL else {
            throw PlayerEngineError.missingVideoURL
        }

        if source.audioURL != nil {
            if let videoStream = source.videoStream,
               let audioStream = source.audioStream,
               videoStream.segmentBase?.indexByteRange != nil,
               audioStream.segmentBase?.indexByteRange != nil {
                do {
                    // Keep AVPlayer on a standard HTTP HLS surface for device playback.
                    // The bridge only accepts hardware-compatible video/audio inputs so
                    // the decode path stays fully inside Apple's pipeline.
                    let manifest = try await BiliHLSManifestBuilder.make(
                        source: source,
                        shouldValidateHardwareDecoding: true,
                        onRemoteFailure: onRemoteFailure
                    )
                    guard let bridge = manifest.bridge else {
                        throw PlayerEngineError.unsupportedMedia
                    }
                    let asset = AVURLAsset(url: manifest.masterPlaylistURL)
                    let item = AVPlayerItem(asset: asset)
                    applyDolbyVisionMetadataPolicy(to: item, source: source)
                    item.preferredForwardBufferDuration = PlaybackEnvironment.current.startupForwardBufferDuration
                    return PreparedPlayerItem(item: item, bridge: bridge, liveProxy: nil, assets: [asset], isDirectLiveHLS: false)
                } catch {
                    PlayerMetricsLog.logger.error(
                        "avPlayerLocalHLSBridgeRejected reason=\(error.localizedDescription, privacy: .public)"
                    )
                    throw error
                }
            }

            throw PlayerEngineError.unsupportedMedia
        }

        let isDirectLiveHLS = source.durationHint == nil
            && (videoURL.isLikelyHLSManifest || (source.isLiveStream && source.isLiveHLS))
        let asset = AVURLAsset(url: videoURL, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        applyDolbyVisionMetadataPolicy(to: item, source: source)
        item.preferredForwardBufferDuration = isDirectLiveHLS ? 0.5 : PlaybackEnvironment.current.startupForwardBufferDuration
        return PreparedPlayerItem(item: item, bridge: nil, liveProxy: nil, assets: [asset], isDirectLiveHLS: isDirectLiveHLS)
    }

    private nonisolated static func applyDolbyVisionMetadataPolicy(
        to item: AVPlayerItem,
        source: PlayerStreamSource
    ) {
        guard source.dynamicRange == .dolbyVision,
              DolbyVisionRenderingPolicy.stored().hlsBridgePolicy == .compatibleHLG
        else { return }
        if #available(iOS 14.1, *) {
            item.appliesPerFrameHDRDisplayMetadata = false
        }
    }

    private nonisolated static func enforceHardwareDecodingCompatibility(for source: PlayerStreamSource) throws {
        if source.playbackContentMode == .video {
            if let videoStream = source.videoStream {
                guard videoStream.isHardwareDecodingCompatibleVideo else {
                    PlayerMetricsLog.logger.error(
                        "hardwareDecodeRejected media=video codec=\(videoStream.codecs ?? "-", privacy: .public) codecid=\(videoStream.codecid ?? -1, privacy: .public)"
                    )
                    throw PlayerEngineError.unsupportedMedia
                }
            } else if source.audioURL != nil {
                PlayerMetricsLog.logger.error("hardwareDecodeRejected media=video codec=missing")
                throw PlayerEngineError.unsupportedMedia
            }
        }

        if let audioStream = source.audioStream,
           !audioStream.isHardwareDecodingCompatibleAudio {
            PlayerMetricsLog.logger.error(
                "hardwareDecodeRejected media=audio codec=\(audioStream.codecs ?? "-", privacy: .public) codecid=\(audioStream.codecid ?? -1, privacy: .public)"
            )
            throw PlayerEngineError.unsupportedMedia
        }
    }

    private nonisolated static func hlsBridgeTrack(
        url: URL,
        stream: DASHStream?,
        mediaType: HLSBridgeTrack.MediaType,
        dynamicRange: BiliVideoDynamicRange = .sdr,
        cdnPreference: PlaybackCDNPreference = .automatic
    ) -> HLSBridgeTrack {
        HLSBridgeTrack(
            url: url,
            fallbackURLs: stream?.backupPlayURLs(cdnPreference: cdnPreference) ?? [],
            stream: stream,
            mediaType: mediaType,
            dynamicRange: dynamicRange
        )
    }
}

private struct PreparedPlayerItem {
    let item: AVPlayerItem
    let bridge: LocalHLSBridge?
    let liveProxy: LocalLiveHLSProxy?
    let assets: [AVAsset]
    let isDirectLiveHLS: Bool
}

@MainActor
private final class NativeDolbyVideoOverlayRenderer {
    private enum State: String {
        case disabled
        case loading
        case ready
        case failed
    }

    private static let resyncThreshold: TimeInterval = 0.45

    private let player = AVPlayer()
    private var prepareTask: Task<Void, Never>?
    private var asset: AVURLAsset?
    private var item: AVPlayerItem?
    private var localVideoBridge: LocalHLSVideoOnlyBridge?
    private var layer: AVPlayerLayer?
    private weak var surface: UIView?
    private var itemStatusObserver: NSKeyValueObservation?
    private var layerReadyObserver: NSKeyValueObservation?
    private var state: State = .disabled
    private var host: String?
    private var sourceKind: String?
    private var playlistHost: String?
    private var lastErrorDescription: String?
    private var lastDriftMilliseconds: Int?
    private var displayPolicySummary: String?
    private var hasSyncedReadyItem = false
    private var didNotifyReadyToPlay = false
    private var didNotifyReadyForDisplay = false
    private(set) var resyncCount = 0
    var onReadyForDisplay: (() -> Void)?
    var onReadyToPlay: (() -> Void)?

    var isActive: Bool {
        state == .loading || state == .ready
    }

    var isReadyForDisplay: Bool {
        state == .ready
    }

    var stateRawValue: String? {
        guard state != .disabled else { return nil }
        return state.rawValue
    }

    var diagnosticSummary: String? {
        guard state != .disabled else { return nil }
        var parts = ["state=\(state.rawValue)"]
        if let sourceKind {
            parts.append("source=\(sourceKind)")
        }
        if let item {
            parts.append("item=\(Self.itemStatusDescription(item.status))")
            if item.status == .readyToPlay {
                parts.append("buffer=\(String(format: "%.2fs", Self.bufferAhead(for: item, at: player.currentTime())))")
            }
        }
        parts.append("tc=\(Self.timeControlStatusDescription(player.timeControlStatus))")
        if let waitingReason = player.reasonForWaitingToPlay?.rawValue {
            parts.append("wait=\(Self.shortErrorDescription(waitingReason) ?? waitingReason)")
        }
        if let host {
            parts.append("host=\(Self.redactedHost(host))")
        }
        if let playlistHost {
            parts.append("playlist=\(Self.redactedHost(playlistHost))")
        }
        if let lastDriftMilliseconds {
            parts.append("drift=\(lastDriftMilliseconds)ms")
        }
        if let displayPolicySummary {
            parts.append(displayPolicySummary)
        }
        parts.append("resync=\(resyncCount)")
        if let lastErrorDescription, !lastErrorDescription.isEmpty {
            parts.append("error=\(lastErrorDescription)")
        }
        return parts.joined(separator: " ")
    }

    init() {
        player.isMuted = true
        player.volume = 0
        player.automaticallyWaitsToMinimizeStalling = false
    }

    func prepare(source: PlayerStreamSource, surface: UIView?, gravity: AVLayerVideoGravity) {
        stop()
        guard let videoURL = source.videoURL,
              let videoStream = source.videoStream
        else { return }
        host = videoURL.host
        sourceKind = "localVideoHLS"
        state = .loading
        lastErrorDescription = nil
        lastDriftMilliseconds = nil
        hasSyncedReadyItem = false
        didNotifyReadyToPlay = false
        didNotifyReadyForDisplay = false
        resyncCount = 0
        self.surface = surface

        let headers = source.httpHeaders
        let durationHint = source.durationHint
        let metricsID = source.metricsID
        let dynamicRange = source.dynamicRange
        let fallbackURLs = videoStream.backupPlayURLs(cdnPreference: source.cdnPreference)
        prepareTask = Task { [weak self] in
            do {
                let bridge = try await LocalHLSBridge.makeVideoOnly(
                    videoTrack: HLSBridgeTrack(
                        url: videoURL,
                        fallbackURLs: fallbackURLs,
                        stream: videoStream,
                        mediaType: .video,
                        dynamicRange: dynamicRange
                    ),
                    durationHint: durationHint,
                    headers: headers,
                    metricsID: metricsID,
                    renderingPolicy: .appleNativeP8HLS
                )
                guard !Task.isCancelled else {
                    bridge.stop()
                    return
                }
                await MainActor.run { [weak self] in
                    self?.install(bridge: bridge, gravity: gravity)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.fail(Self.shortErrorDescription(error.localizedDescription))
                }
            }
        }
    }

    private func install(bridge: LocalHLSVideoOnlyBridge, gravity: AVLayerVideoGravity) {
        guard state == .loading else {
            bridge.stop()
            return
        }
        localVideoBridge = bridge
        playlistHost = bridge.masterPlaylistURL.host

        let asset = AVURLAsset(url: bridge.masterPlaylistURL)
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = PlaybackEnvironment.current.startupForwardBufferDuration
        player.replaceCurrentItem(with: item)
        player.isMuted = true
        player.volume = 0

        self.asset = asset
        self.item = item
        observeStatus(for: item)
        attach(to: surface, gravity: gravity)
    }

    func attach(to surface: UIView?, gravity: AVLayerVideoGravity) {
        guard let surface else { return }
        self.surface = surface
        guard item != nil else { return }
        let layer = ensureLayer(in: surface)
        layer.player = player
        layer.videoGravity = gravity
        applyDisplayPolicy(to: layer)
        refreshLayout(in: surface, gravity: gravity)
    }

    func detach(from surface: UIView) {
        guard self.surface === surface else { return }
        layer?.removeFromSuperlayer()
        layerReadyObserver = nil
        layer = nil
        self.surface = nil
    }

    func refreshLayout(in surface: UIView?, gravity: AVLayerVideoGravity) {
        guard let surface, let layer, layer.superlayer === surface.layer else { return }
        AVPlayerLayoutCoordinator.shared.apply(playerLayer: layer, in: surface, gravity: gravity)
    }

    func setVideoGravity(_ gravity: AVLayerVideoGravity, in surface: UIView?) {
        layer?.videoGravity = gravity
        refreshLayout(in: surface, gravity: gravity)
    }

    func play(rate: Float) {
        guard item != nil else { return }
        let playbackRate = max(rate, 0.1)
        player.defaultRate = playbackRate
        player.playImmediately(atRate: playbackRate)
    }

    func pause() {
        player.pause()
    }

    func seek(to time: TimeInterval, shouldPlay: Bool) {
        guard item?.status == .readyToPlay else { return }
        let target = CMTime(seconds: max(time, 0), preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.hasSyncedReadyItem = true
                self.updateReadyState()
                if shouldPlay {
                    self.play(rate: self.player.defaultRate)
                }
            }
        }
    }

    func sync(
        to masterTime: TimeInterval,
        shouldPlay: Bool,
        rate: Float,
        force: Bool,
        reason _: String,
        countsAsResync: Bool = true
    ) {
        guard item?.status == .readyToPlay else { return }
        let currentTime = player.currentTime().seconds
        let drift = currentTime.isFinite ? currentTime - masterTime : .infinity
        lastDriftMilliseconds = drift.isFinite ? Int((drift * 1000).rounded()) : nil
        let shouldResync = force || !drift.isFinite || abs(drift) > Self.resyncThreshold
        if shouldResync {
            if countsAsResync {
                resyncCount += 1
            }
            seek(to: masterTime, shouldPlay: shouldPlay)
            return
        }
        hasSyncedReadyItem = true
        updateReadyState()
        if shouldPlay {
            if abs(player.rate - rate) > 0.01 {
                play(rate: rate)
            } else if player.rate <= 0 {
                play(rate: rate)
            }
        } else if player.rate != 0 {
            pause()
        }
    }

    func stop() {
        prepareTask?.cancel()
        prepareTask = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        layer?.player = nil
        layer?.removeFromSuperlayer()
        layerReadyObserver = nil
        itemStatusObserver = nil
        asset?.cancelLoading()
        localVideoBridge?.stop()
        asset = nil
        item = nil
        localVideoBridge = nil
        layer = nil
        surface = nil
        host = nil
        sourceKind = nil
        playlistHost = nil
        lastErrorDescription = nil
        lastDriftMilliseconds = nil
        displayPolicySummary = nil
        hasSyncedReadyItem = false
        didNotifyReadyToPlay = false
        didNotifyReadyForDisplay = false
        resyncCount = 0
        state = .disabled
    }

    private func ensureLayer(in surface: UIView) -> AVPlayerLayer {
        if let layer {
            if layer.superlayer !== surface.layer {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                layer.removeFromSuperlayer()
                surface.layer.addSublayer(layer)
                CATransaction.commit()
            }
            if layerReadyObserver == nil {
                observeReadyForDisplay(layer)
            }
            return layer
        }

        let layer = AVPlayerLayer(player: player)
        layer.backgroundColor = UIColor.black.cgColor
        layer.isHidden = true
        layer.needsDisplayOnBoundsChange = false
        layer.actions = [
            "bounds": NSNull(),
            "position": NSNull(),
            "frame": NSNull()
        ]
        applyDisplayPolicy(to: layer)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        surface.layer.addSublayer(layer)
        CATransaction.commit()
        self.layer = layer
        observeReadyForDisplay(layer)
        return layer
    }

    private func applyDisplayPolicy(to layer: AVPlayerLayer) {
        layer.preferredDynamicRange = .high
        layer.toneMapMode = .never
        displayPolicySummary = "display=high/noToneMap"
    }

    private func observeStatus(for item: AVPlayerItem) {
        let itemIdentity = ObjectIdentifier(item)
        itemStatusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self,
                      let currentItem = self.item,
                      ObjectIdentifier(currentItem) == itemIdentity
                else { return }
                switch currentItem.status {
                case .readyToPlay:
                    self.notifyReadyToPlayIfNeeded()
                    self.updateReadyState()
                case .failed:
                    self.fail(Self.itemFailureDescription(currentItem))
                case .unknown:
                    self.state = .loading
                @unknown default:
                    self.state = .loading
                }
            }
        }
    }

    private func observeReadyForDisplay(_ layer: AVPlayerLayer) {
        let layerIdentity = ObjectIdentifier(layer)
        layerReadyObserver = layer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self,
                      let currentLayer = self.layer,
                      ObjectIdentifier(currentLayer) == layerIdentity
                else { return }
                if currentLayer.isReadyForDisplay {
                    self.updateReadyState()
                }
            }
        }
    }

    private func updateReadyState() {
        guard item?.status == .readyToPlay else { return }
        if layer?.isReadyForDisplay == true, hasSyncedReadyItem {
            layer?.isHidden = false
            state = .ready
            notifyReadyForDisplayIfNeeded()
        } else if state != .failed {
            state = .loading
        }
    }

    private func notifyReadyForDisplayIfNeeded() {
        guard !didNotifyReadyForDisplay else { return }
        didNotifyReadyForDisplay = true
        onReadyForDisplay?()
    }

    private func notifyReadyToPlayIfNeeded() {
        guard !didNotifyReadyToPlay else { return }
        didNotifyReadyToPlay = true
        onReadyToPlay?()
    }

    private static func redactedHost(_ host: String) -> String {
        let components = host
            .lowercased()
            .split(separator: ".")
            .map(String.init)
        guard components.count >= 2 else { return "<redacted>" }
        return "*." + components.suffix(2).joined(separator: ".")
    }

    private static func itemStatusDescription(_ status: AVPlayerItem.Status) -> String {
        switch status {
        case .unknown:
            return "unknown"
        case .readyToPlay:
            return "ready"
        case .failed:
            return "failed"
        @unknown default:
            return "unknown"
        }
    }

    private static func timeControlStatusDescription(_ status: AVPlayer.TimeControlStatus) -> String {
        switch status {
        case .paused:
            return "paused"
        case .waitingToPlayAtSpecifiedRate:
            return "waiting"
        case .playing:
            return "playing"
        @unknown default:
            return "unknown"
        }
    }

    private static func bufferAhead(for item: AVPlayerItem, at currentTime: CMTime) -> TimeInterval {
        let currentSeconds = currentTime.seconds
        guard currentSeconds.isFinite else { return 0 }
        return item.loadedTimeRanges
            .map(\.timeRangeValue)
            .map { range -> TimeInterval in
                let start = range.start.seconds
                let end = range.end.seconds
                guard start.isFinite, end.isFinite, end >= currentSeconds else { return 0 }
                return max(0, end - max(start, currentSeconds))
            }
            .max() ?? 0
    }

    private func fail(_ description: String?) {
        state = .failed
        lastErrorDescription = description
        layer?.isHidden = true
    }

    private static func itemFailureDescription(_ item: AVPlayerItem) -> String? {
        let base = shortErrorDescription(item.error?.localizedDescription)
        let log = item.errorLog()?.events.reversed().compactMap { event -> String? in
            var parts = [String]()
            if event.errorStatusCode != 0 {
                parts.append("status=\(event.errorStatusCode)")
            }
            if let comment = shortErrorDescription(event.errorComment), !comment.isEmpty {
                parts.append("comment=\(comment)")
            }
            if let uri = shortErrorDescription(event.uri), !uri.isEmpty {
                parts.append("uri=\(uri)")
            }
            return parts.isEmpty ? nil : parts.joined(separator: ",")
        }.first
        return [base, log]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func shortErrorDescription(_ value: String?) -> String? {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        let normalized = value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > 80 else { return normalized }
        return String(normalized.prefix(77)) + "..."
    }
}

private extension URL {
    var isLikelyHLSManifest: Bool {
        pathExtension.localizedCaseInsensitiveCompare("m3u8") == .orderedSame
            || absoluteString.range(of: ".m3u8", options: .caseInsensitive) != nil
    }
}

nonisolated struct LocalHLSVideoOnlyBridge: Sendable {
    let masterPlaylistURL: URL
    let videoVariantDetails: [String]
    private let server: LocalHLSProxyServer

    fileprivate init(
        masterPlaylistURL: URL,
        videoVariantDetails: [String],
        server: LocalHLSProxyServer
    ) {
        self.masterPlaylistURL = masterPlaylistURL
        self.videoVariantDetails = videoVariantDetails
        self.server = server
    }

    nonisolated func stop() {
        server.stop()
    }
}

struct LocalHLSBridge: Sendable {
    let masterPlaylistURL: URL
    let mediaTimeOffset: TimeInterval
    let videoClockDelay: TimeInterval
    let videoVariantCount: Int
    let videoVariantQualities: [Int]
    let videoVariantDetails: [String]
    let routePlanCacheState: String
    let serverCacheState: String
    private let seekPlanner: HLSBridgeSeekPlanner?
    private let server: LocalHLSProxyServer

    nonisolated func updateMetricsID(_ metricsID: String?) {
        server.updateMetricsID(metricsID)
    }

    nonisolated func updateRemoteFailureHandler(_ handler: HLSRemoteFailureHandler?) {
        server.updateRemoteFailureHandler(handler)
    }

    nonisolated func updateHeaders(_ headers: [String: String]) {
        server.updateHeaders(headers)
    }

    nonisolated func recentRemoteFailureReason() -> HLSBridgeFailureReason? {
        server.recentRemoteFailureReason()
    }

    nonisolated func withCacheDiagnostics(routePlanState: String, serverState: String) -> LocalHLSBridge {
        LocalHLSBridge(
            masterPlaylistURL: masterPlaylistURL,
            mediaTimeOffset: mediaTimeOffset,
            videoClockDelay: videoClockDelay,
            videoVariantCount: videoVariantCount,
            videoVariantQualities: videoVariantQualities,
            videoVariantDetails: videoVariantDetails,
            routePlanCacheState: routePlanState,
            serverCacheState: serverState,
            seekPlanner: seekPlanner,
            server: server
        )
    }

    nonisolated func stop() {
        server.stop()
    }

    nonisolated func alignedSeekTime(near playbackTime: TimeInterval) -> TimeInterval? {
        seekPlanner?.alignedSeekTime(near: playbackTime)
    }

    nonisolated func warmSeekTarget(around playbackTime: TimeInterval, metricsID: String?) async {
        guard let seekPlanner else { return }
        await seekPlanner.warm(around: playbackTime, metricsID: metricsID)
    }

    nonisolated static func make(
        videoTrack: HLSBridgeTrack,
        audioTrack: HLSBridgeTrack,
        durationHint: TimeInterval?,
        headers: [String: String],
        metricsID: String? = nil,
        onRemoteFailure: HLSRemoteFailureHandler? = nil,
        storesBridgeForReuse: Bool = false
    ) async throws -> LocalHLSBridge {
        try await make(
            videoTracks: [videoTrack],
            audioTrack: audioTrack,
            durationHint: durationHint,
            headers: headers,
            metricsID: metricsID,
            onRemoteFailure: onRemoteFailure,
            storesBridgeForReuse: storesBridgeForReuse
        )
    }

    nonisolated static func make(
        videoTracks: [HLSBridgeTrack],
        audioTrack: HLSBridgeTrack,
        durationHint: TimeInterval?,
        headers: [String: String],
        metricsID: String? = nil,
        onRemoteFailure: HLSRemoteFailureHandler? = nil,
        storesBridgeForReuse: Bool = false
    ) async throws -> LocalHLSBridge {
        guard let primaryVideoTrack = videoTracks.first else {
            throw PlayerEngineError.missingVideoURL
        }
        let start = CACurrentMediaTime()
        PlayerMetricsLog.logger.info(
            "hlsBridgeMakeStart videoQ=\(primaryVideoTrack.stream?.id ?? -1, privacy: .public) videoVariants=\(videoTracks.count, privacy: .public) audioBandwidth=\(audioTrack.stream?.bandwidth ?? 0, privacy: .public)"
        )
        await recordManifestStage(
            metricsID: metricsID,
            "plannedVideo=\(qualitySummary(for: videoTracks))"
        )
        let (plan, planState) = try await routePlan(
            videoTracks: videoTracks,
            audioTrack: audioTrack,
            durationHint: durationHint,
            headers: headers,
            metricsID: metricsID
        )
        let cacheKey = bridgeCacheKey(
            videoTracks: videoTracks,
            audioTrack: audioTrack,
            headers: headers
        )
        let bridgeResult: (bridge: LocalHLSBridge, state: LocalHLSBridgeInstanceCache.State)
        if let cacheKey {
            bridgeResult = try await LocalHLSBridgeInstanceCache.shared.cachedOrBuild(
                for: cacheKey,
                storesForReuse: storesBridgeForReuse
            ) {
                try await build(
                    from: plan,
                    headers: headers,
                    metricsID: metricsID,
                    onRemoteFailure: onRemoteFailure
                )
            }
        } else {
            bridgeResult = (
                try await build(
                    from: plan,
                    headers: headers,
                    metricsID: metricsID,
                    onRemoteFailure: onRemoteFailure
                ),
                .miss
            )
        }
        let bridge = bridgeResult.bridge.withCacheDiagnostics(
            routePlanState: planState,
            serverState: bridgeResult.state.rawValue
        )
        bridge.updateMetricsID(metricsID)
        bridge.updateHeaders(headers)
        bridge.updateRemoteFailureHandler(onRemoteFailure)
        let elapsedMilliseconds = PlayerMetricsLog.elapsedMilliseconds(since: start)
        PlayerMetricsLog.logger.info(
            "hlsBridgeMakeReady routePlan=\(planState, privacy: .public) server=\(bridgeResult.state.rawValue, privacy: .public) elapsedMs=\(elapsedMilliseconds, format: .fixed(precision: 1), privacy: .public)"
        )
        await recordManifestStage(
            metricsID: metricsID,
            "bridge=\(planState) server=\(bridgeResult.state.rawValue) total=\(formatMilliseconds(elapsedMilliseconds))"
        )
        return bridge
    }

    @discardableResult
    nonisolated static func prebuildBridge(
        videoTracks: [HLSBridgeTrack],
        audioTrack: HLSBridgeTrack,
        durationHint: TimeInterval?,
        headers: [String: String],
        metricsID: String? = nil,
        waitsForDemuxWarmup _: Bool = true
    ) async -> Bool {
        do {
            _ = try await make(
                videoTracks: videoTracks,
                audioTrack: audioTrack,
                durationHint: durationHint,
                headers: headers,
                metricsID: metricsID,
                storesBridgeForReuse: true
            )
            return true
        } catch {
            PlayerMetricsLog.logger.info(
                "hlsBridgePrebuildFailed error=\(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    nonisolated static func makeVideoOnly(
        videoTrack: HLSBridgeTrack,
        durationHint: TimeInterval?,
        headers: [String: String],
        metricsID: String? = nil,
        renderingPolicy: DolbyVisionRenderingPolicy
    ) async throws -> LocalHLSVideoOnlyBridge {
        let start = CACurrentMediaTime()
        let rendition = try await makeRendition(
            for: videoTrack,
            durationHint: durationHint,
            headers: headers,
            metricsID: metricsID,
            renderingPolicy: renderingPolicy
        )
        let server = try LocalHLSProxyServer.make(
            headers: headers,
            metricsID: metricsID,
            onRemoteFailure: nil
        )
        let renderedPlaylists = try await server.start { baseURL in
            renderVideoOnlyPlaylists(
                rendition: rendition,
                masterPlaylistVersion: masterPlaylistVersion(for: [rendition]),
                baseURL: baseURL
            )
        }
        let elapsedMilliseconds = PlayerMetricsLog.elapsedMilliseconds(since: start)
        PlayerMetricsLog.logger.info(
            "nativeHDRVideoOnlyHLSReady elapsedMs=\(elapsedMilliseconds, format: .fixed(precision: 1), privacy: .public) routes=\(renderedPlaylists.routes.count, privacy: .public) codec=\(rendition.hlsAdvertisedCodec, privacy: .public) range=\(rendition.hlsVideoRangeValue ?? "-", privacy: .public) supplemental=\(rendition.hlsAdvertisedSupplementalCodec ?? "-", privacy: .public)"
        )
        await recordManifestStage(
            metricsID: metricsID,
            "nativeHDR=localVideoHLS \(formatMilliseconds(elapsedMilliseconds)) codec=\(rendition.hlsAdvertisedCodec)"
        )
        return LocalHLSVideoOnlyBridge(
            masterPlaylistURL: renderedPlaylists.masterPlaylistURL,
            videoVariantDetails: [rendition.diagnosticSummary],
            server: server
        )
    }

    nonisolated static func makeAudioOnly(
        audioTrack: HLSBridgeTrack,
        durationHint: TimeInterval?,
        headers: [String: String],
        metricsID: String? = nil,
        onRemoteFailure: HLSRemoteFailureHandler? = nil
    ) async throws -> LocalHLSBridge {
        let start = CACurrentMediaTime()
        let rendition = try await makeRendition(
            for: audioTrack,
            durationHint: durationHint,
            headers: headers,
            metricsID: metricsID
        )
        let server = try LocalHLSProxyServer.make(
            headers: headers,
            metricsID: metricsID,
            onRemoteFailure: onRemoteFailure
        )
        let renderedPlaylists = try await server.start { baseURL in
            renderAudioOnlyPlaylists(
                rendition: rendition,
                baseURL: baseURL
            )
        }
        let elapsedMilliseconds = PlayerMetricsLog.elapsedMilliseconds(since: start)
        PlayerMetricsLog.logger.info(
            "audioOnlyHLSReady elapsedMs=\(elapsedMilliseconds, format: .fixed(precision: 1), privacy: .public) routes=\(renderedPlaylists.routes.count, privacy: .public) codec=\(rendition.codec, privacy: .public)"
        )
        await recordManifestStage(
            metricsID: metricsID,
            "audioOnly=ready \(formatMilliseconds(elapsedMilliseconds)) refs=\(rendition.references.count)"
        )
        return LocalHLSBridge(
            masterPlaylistURL: renderedPlaylists.masterPlaylistURL,
            mediaTimeOffset: 0,
            videoClockDelay: 0,
            videoVariantCount: 0,
            videoVariantQualities: [],
            videoVariantDetails: [],
            routePlanCacheState: "audioOnly",
            serverCacheState: "miss",
            seekPlanner: HLSBridgeSeekPlanner(
                video: nil,
                audio: rendition.seekMap(includeExtraSegment: false),
                headers: headers
            ),
            server: server
        )
    }

    @discardableResult
    nonisolated static func prebuildRoutePlan(
        videoTrack: HLSBridgeTrack,
        audioTrack: HLSBridgeTrack,
        durationHint: TimeInterval?,
        headers: [String: String],
        metricsID: String? = nil
    ) async -> Bool {
        await prebuildRoutePlan(
            videoTracks: [videoTrack],
            audioTrack: audioTrack,
            durationHint: durationHint,
            headers: headers,
            metricsID: metricsID
        )
    }

    @discardableResult
    nonisolated static func prebuildRoutePlan(
        videoTracks: [HLSBridgeTrack],
        audioTrack: HLSBridgeTrack,
        durationHint: TimeInterval?,
        headers: [String: String],
        metricsID: String? = nil
    ) async -> Bool {
        guard let primaryVideoTrack = videoTracks.first else { return false }
        guard let cacheKey = bridgeCacheKey(
            videoTracks: videoTracks,
            audioTrack: audioTrack,
            headers: headers
        ) else { return false }

        let start = CACurrentMediaTime()
        do {
            let state = try await HLSBridgeRoutePlanCache.shared.prebuild(for: cacheKey) {
                try await makeRoutePlan(
                    videoTracks: videoTracks,
                    audioTrack: audioTrack,
                    durationHint: durationHint,
                    headers: headers,
                    metricsID: metricsID
                )
            }
            let elapsedMilliseconds = PlayerMetricsLog.elapsedMilliseconds(since: start)
            PlayerMetricsLog.logger.info(
                "hlsBridgeRoutePlanPrebuild state=\(state.rawValue, privacy: .public) videoQ=\(primaryVideoTrack.stream?.id ?? -1, privacy: .public) elapsedMs=\(elapsedMilliseconds, format: .fixed(precision: 1), privacy: .public)"
            )
            await recordManifestStage(
                metricsID: metricsID,
                "routePrebuild=\(state.rawValue) \(formatMilliseconds(elapsedMilliseconds))"
            )
            return state != .skippedPending
        } catch {
            PlayerMetricsLog.logger.info(
                "hlsBridgeRoutePlanPrebuildFailed videoQ=\(primaryVideoTrack.stream?.id ?? -1, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    private nonisolated static func routePlan(
        videoTracks: [HLSBridgeTrack],
        audioTrack: HLSBridgeTrack,
        durationHint: TimeInterval?,
        headers: [String: String],
        metricsID: String?
    ) async throws -> (HLSBridgeRoutePlan, String) {
        guard let cacheKey = bridgeCacheKey(
            videoTracks: videoTracks,
            audioTrack: audioTrack,
            headers: headers
        ) else {
            let plan = try await makeRoutePlan(
                videoTracks: videoTracks,
                audioTrack: audioTrack,
                durationHint: durationHint,
                headers: headers,
                metricsID: metricsID
            )
            return (plan, "uncached")
        }

        let result = try await HLSBridgeRoutePlanCache.shared.cachedOrBuild(for: cacheKey) {
            try await makeRoutePlan(
                videoTracks: videoTracks,
                audioTrack: audioTrack,
                durationHint: durationHint,
                headers: headers,
                metricsID: metricsID
            )
        }
        return (result.plan, result.state.rawValue)
    }

    private nonisolated static func makeRoutePlan(
        videoTracks: [HLSBridgeTrack],
        audioTrack: HLSBridgeTrack,
        durationHint: TimeInterval?,
        headers: [String: String],
        metricsID: String?
    ) async throws -> HLSBridgeRoutePlan {
        guard !videoTracks.isEmpty else {
            throw PlayerEngineError.missingVideoURL
        }
        let start = CACurrentMediaTime()
        PlayerMetricsLog.logger.info(
            "hlsBridgeRoutePlanBuildStart videoVariants=\(videoTracks.count, privacy: .public)"
        )
        async let audioRenditionTask = makeRendition(for: audioTrack, durationHint: durationHint, headers: headers, metricsID: metricsID)
        let videoRenditions = try await makeVideoRenditions(
            for: videoTracks,
            durationHint: durationHint,
            headers: headers,
            metricsID: metricsID
        )
        let audioRendition = try await audioRenditionTask
        let renditionMilliseconds = PlayerMetricsLog.elapsedMilliseconds(since: start)
        PlayerMetricsLog.logger.info(
            "hlsBridgeRenditionsReady elapsedMs=\(renditionMilliseconds, format: .fixed(precision: 1), privacy: .public) videoVariants=\(videoRenditions.count, privacy: .public) videoRefs=\(videoRenditions.first?.references.count ?? 0, privacy: .public) audioRefs=\(audioRendition.references.count, privacy: .public)"
        )
        await recordManifestStage(
            metricsID: metricsID,
            "renditions=\(formatMilliseconds(renditionMilliseconds)) video=\(qualitySummary(for: videoRenditions)) videoRefs=\(videoRenditions.first?.references.count ?? 0) audioRefs=\(audioRendition.references.count)"
        )

        return HLSBridgeRoutePlan(
            videoRenditions: videoRenditions,
            audioRendition: audioRendition,
            masterPlaylistVersion: masterPlaylistVersion(for: videoRenditions)
        )
    }

    private nonisolated static func makeVideoRenditions(
        for tracks: [HLSBridgeTrack],
        durationHint: TimeInterval?,
        headers: [String: String],
        metricsID: String?
    ) async throws -> [HLSRendition] {
        guard let primaryTrack = tracks.first else { return [] }
        let primaryRendition = try await makeRendition(
            for: primaryTrack,
            durationHint: durationHint,
            headers: headers,
            metricsID: metricsID
        )
        let alternateTracks = Array(tracks.dropFirst())
        guard !alternateTracks.isEmpty else { return [primaryRendition] }
        let waitBudget = optionalVideoRenditionPostPrimaryWaitNanoseconds
        guard waitBudget > 0 else {
            await recordManifestStage(
                metricsID: metricsID,
                "alternateVideo=deferred"
            )
            return [primaryRendition]
        }
        let alternateTask = Task(priority: .utility) {
            await makeOptionalVideoRenditions(
                for: alternateTracks,
                durationHint: durationHint,
                headers: headers,
                metricsID: metricsID
            )
        }
        defer { alternateTask.cancel() }
        let alternateRenditions = await optionalVideoRenditions(
            from: alternateTask,
            waitBudget: waitBudget
        )
        return [primaryRendition] + alternateRenditions
    }

    private nonisolated static func optionalVideoRenditions(
        from task: Task<[HLSRendition], Never>,
        waitBudget: UInt64
    ) async -> [HLSRendition] {
        guard waitBudget > 0 else { return [] }
        let timeoutTask = Task(priority: .utility) { () -> [HLSRendition] in
            try? await Task.sleep(nanoseconds: waitBudget)
            return []
        }
        defer {
            timeoutTask.cancel()
        }
        return await withTaskGroup(of: [HLSRendition].self, returning: [HLSRendition].self) { group in
            group.addTask { await task.value }
            group.addTask { await timeoutTask.value }
            let renditions = await group.next() ?? []
            group.cancelAll()
            return renditions
        }
    }

    private nonisolated static func build(
        from plan: HLSBridgeRoutePlan,
        headers: [String: String],
        metricsID: String?,
        onRemoteFailure: HLSRemoteFailureHandler?
    ) async throws -> LocalHLSBridge {
        guard let videoRendition = plan.videoRenditions.first else {
            throw PlayerEngineError.missingVideoURL
        }
        let start = CACurrentMediaTime()
        let videoRenditions = plan.videoRenditions
        let audioRendition = plan.audioRendition
        let server = try LocalHLSProxyServer.make(
            headers: headers,
            metricsID: metricsID,
            onRemoteFailure: onRemoteFailure
        )
        let renderedPlaylists = try await server.start { baseURL in
            renderPlaylists(from: plan, baseURL: baseURL)
        }
        let masterPlaylistURL = renderedPlaylists.masterPlaylistURL
        let routes = renderedPlaylists.routes
        let serverMilliseconds = PlayerMetricsLog.elapsedMilliseconds(since: start)
        PlayerMetricsLog.logger.info(
            "hlsBridgeServerReady elapsedMs=\(serverMilliseconds, format: .fixed(precision: 1), privacy: .public) dynamicRange=\(videoRendition.dynamicRange.rawValue, privacy: .public) codec=\(videoRendition.codec, privacy: .public) version=\(plan.masterPlaylistVersion, privacy: .public) variants=\(videoRenditions.count, privacy: .public) routes=\(routes.count, privacy: .public)"
        )
        let dolbyVisionManifestSummary = videoRenditions
            .filter { $0.dynamicRange == .dolbyVision }
            .map { rendition in
                "q\(rendition.quality ?? -1) policy=\(rendition.dolbyVisionRenderingPolicy.rawValue) path=\(rendition.dolbyVisionRenderingPath) source=\(rendition.codec) hls=\(rendition.hlsAdvertisedCodec) range=\(rendition.hlsVideoRangeValue ?? "-") supplemental=\(rendition.hlsAdvertisedSupplementalCodec ?? "-")"
            }
            .joined(separator: ";")
        if !dolbyVisionManifestSummary.isEmpty {
            PlayerMetricsLog.logger.info(
                "hlsBridgeDolbyVisionManifest \(dolbyVisionManifestSummary, privacy: .public)"
            )
        }
        await recordManifestStage(
            metricsID: metricsID,
            "server=\(formatMilliseconds(serverMilliseconds)) routes=\(routes.count) variants=\(videoRenditions.count) codec=\(videoRendition.codec)"
        )

        let originalMediaTimeOffset = [videoRendition.mediaTimeOffset, audioRendition.mediaTimeOffset]
            .filter { $0.isFinite && $0 > 0 }
            .min() ?? 0
        let originalVideoClockDelay = normalizedVideoClockDelay(
            audioStart: audioRendition.mediaTimeOffset,
            videoStart: videoRendition.mediaTimeOffset
        )
        if abs(originalVideoClockDelay) > 0.001 || originalMediaTimeOffset > 0.001 {
            PlayerMetricsLog.logger.info(
                "hlsBridgeTimelineNormalize audioStart=\(audioRendition.mediaTimeOffset, format: .fixed(precision: 3), privacy: .public) videoStart=\(videoRendition.mediaTimeOffset, format: .fixed(precision: 3), privacy: .public) originalVideoDelay=\(originalVideoClockDelay, format: .fixed(precision: 3), privacy: .public)"
            )
        }

        return LocalHLSBridge(
            masterPlaylistURL: masterPlaylistURL,
            mediaTimeOffset: 0,
            videoClockDelay: 0,
            videoVariantCount: videoRenditions.count,
            videoVariantQualities: videoRenditions.compactMap(\.quality),
            videoVariantDetails: videoRenditions.map(\.diagnosticSummary),
            routePlanCacheState: "-",
            serverCacheState: "-",
            seekPlanner: HLSBridgeSeekPlanner(
                video: videoRendition.seekMap(includeExtraSegment: true),
                audio: audioRendition.seekMap(includeExtraSegment: false),
                headers: headers
            ),
            server: server
        )
    }

#if DEBUG
    nonisolated static func makeForTesting(
        from plan: HLSBridgeRoutePlan,
        headers: [String: String] = [:],
        metricsID: String? = nil,
        onRemoteFailure: HLSRemoteFailureHandler? = nil
    ) async throws -> LocalHLSBridge {
        try await build(
            from: plan,
            headers: headers,
            metricsID: metricsID,
            onRemoteFailure: onRemoteFailure
        )
    }
#endif

    nonisolated static func renderPlaylists(from plan: HLSBridgeRoutePlan, baseURL: URL) -> HLSBridgeRenderedPlaylists {
        let audioRendition = plan.audioRendition
        let audioPlaylistURL = baseURL.appendingPathComponent("audio.m3u8")
        let masterPlaylistURL = baseURL.appendingPathComponent("master.m3u8")
        let audioPlaylist = audioRendition.playlist(baseURL: baseURL, routePrefix: "audio")
        let videoPlaylistEntries = plan.videoRenditions.enumerated().map { index, rendition in
            let routePrefix = videoRoutePrefix(for: index)
            let playlistURL = baseURL.appendingPathComponent("\(routePrefix).m3u8")
            return """
            #EXT-X-STREAM-INF:BANDWIDTH=\(rendition.bandwidth),CODECS="\(rendition.hlsAdvertisedCodec),\(audioRendition.codec)",AUDIO="audio"\(rendition.hlsResolutionAttribute)\(rendition.hlsFrameRateAttribute)\(rendition.hlsVideoRangeAttribute)\(rendition.hlsAdvertisedSupplementalCodecAttribute)
            \(playlistURL.absoluteString)
            """
        }.joined(separator: "\n")
        let masterPlaylist = """
        #EXTM3U
        #EXT-X-VERSION:\(plan.masterPlaylistVersion)
        #EXT-X-INDEPENDENT-SEGMENTS
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="audio",DEFAULT=YES,AUTOSELECT=YES,URI="\(audioPlaylistURL.absoluteString)"
        \(videoPlaylistEntries)
        """

        var routes: [String: HLSProxyRoute] = [
            "/master.m3u8": .data(Data(masterPlaylist.utf8), contentType: "application/vnd.apple.mpegurl"),
            "/audio.m3u8": .data(Data(audioPlaylist.utf8), contentType: "application/vnd.apple.mpegurl")
        ]
        for (index, rendition) in plan.videoRenditions.enumerated() {
            let routePrefix = videoRoutePrefix(for: index)
            let playlist = rendition.playlist(baseURL: baseURL, routePrefix: routePrefix)
            routes["/\(routePrefix).m3u8"] = .data(Data(playlist.utf8), contentType: "application/vnd.apple.mpegurl")
            rendition.registerRoutes(routePrefix: routePrefix, into: &routes)
        }
        audioRendition.registerRoutes(routePrefix: "audio", into: &routes)
        return HLSBridgeRenderedPlaylists(
            masterPlaylistURL: masterPlaylistURL,
            routes: routes
        )
    }

    nonisolated static func renderVideoOnlyPlaylists(
        rendition: HLSRendition,
        masterPlaylistVersion: Int,
        baseURL: URL
    ) -> HLSBridgeRenderedPlaylists {
        let playlistURL = baseURL.appendingPathComponent("video.m3u8")
        let masterPlaylistURL = baseURL.appendingPathComponent("master.m3u8")
        let masterPlaylist = """
        #EXTM3U
        #EXT-X-VERSION:\(masterPlaylistVersion)
        #EXT-X-INDEPENDENT-SEGMENTS
        #EXT-X-STREAM-INF:BANDWIDTH=\(rendition.bandwidth),CODECS="\(rendition.hlsAdvertisedCodec)"\(rendition.hlsResolutionAttribute)\(rendition.hlsFrameRateAttribute)\(rendition.hlsVideoRangeAttribute)\(rendition.hlsAdvertisedSupplementalCodecAttribute)
        \(playlistURL.absoluteString)
        """

        var routes: [String: HLSProxyRoute] = [
            "/master.m3u8": .data(Data(masterPlaylist.utf8), contentType: "application/vnd.apple.mpegurl"),
            "/video.m3u8": .data(
                Data(rendition.playlist(baseURL: baseURL, routePrefix: "video").utf8),
                contentType: "application/vnd.apple.mpegurl"
            )
        ]
        rendition.registerRoutes(routePrefix: "video", into: &routes)
        return HLSBridgeRenderedPlaylists(
            masterPlaylistURL: masterPlaylistURL,
            routes: routes
        )
    }

    nonisolated static func renderAudioOnlyPlaylists(
        rendition: HLSRendition,
        baseURL: URL
    ) -> HLSBridgeRenderedPlaylists {
        let audioPlaylistURL = baseURL.appendingPathComponent("audio.m3u8")
        let masterPlaylistURL = baseURL.appendingPathComponent("master.m3u8")
        let masterPlaylist = """
        #EXTM3U
        #EXT-X-VERSION:7
        #EXT-X-INDEPENDENT-SEGMENTS
        #EXT-X-STREAM-INF:BANDWIDTH=\(rendition.bandwidth),CODECS="\(rendition.codec)"
        \(audioPlaylistURL.absoluteString)
        """

        var routes: [String: HLSProxyRoute] = [
            "/master.m3u8": .data(Data(masterPlaylist.utf8), contentType: "application/vnd.apple.mpegurl"),
            "/audio.m3u8": .data(
                Data(rendition.playlist(baseURL: baseURL, routePrefix: "audio").utf8),
                contentType: "application/vnd.apple.mpegurl"
            )
        ]
        rendition.registerRoutes(routePrefix: "audio", into: &routes)
        return HLSBridgeRenderedPlaylists(
            masterPlaylistURL: masterPlaylistURL,
            routes: routes
        )
    }

    private nonisolated static func normalizedVideoClockDelay(audioStart: TimeInterval, videoStart: TimeInterval) -> TimeInterval {
        guard audioStart.isFinite, videoStart.isFinite else { return 0 }
        let delay = audioStart - videoStart
        guard delay.isFinite, abs(delay) <= 60 else { return 0 }
        return abs(delay) < 0.001 ? 0 : delay
    }

    private nonisolated static func videoRoutePrefix(for index: Int) -> String {
        index == 0 ? "video" : "video-\(index)"
    }

    private nonisolated static func qualitySummary(for tracks: [HLSBridgeTrack]) -> String {
        let qualities = tracks.compactMap { $0.stream?.id }
        guard !qualities.isEmpty else { return "-" }
        return qualities
            .map { "q\($0)" }
            .joined(separator: "/")
    }

    private nonisolated static func qualitySummary(for renditions: [HLSRendition]) -> String {
        let qualities = renditions.compactMap(\.quality)
        guard !qualities.isEmpty else { return "-" }
        return qualities
            .map { "q\($0)" }
            .joined(separator: "/")
    }

    private nonisolated static func masterPlaylistVersion(for videoRenditions: [HLSRendition]) -> Int {
        if videoRenditions.contains(where: { !$0.hlsAdvertisedSupplementalCodecAttribute.isEmpty }) {
            return 10
        }
        if videoRenditions.contains(where: { !$0.hlsVideoRangeAttribute.isEmpty }) {
            return 8
        }
        return 7
    }

    private nonisolated static func recordManifestStage(metricsID: String?, _ message: String) async {
        guard let metricsID, !metricsID.isEmpty else { return }
        await PlayerMetricsLog.record(.manifestStage, metricsID: metricsID, message: message)
    }

    private nonisolated static func makeOptionalVideoRenditions(
        for tracks: [HLSBridgeTrack],
        durationHint: TimeInterval?,
        headers: [String: String],
        metricsID: String?
    ) async -> [HLSRendition] {
        guard !tracks.isEmpty else { return [] }
        let budget = optionalVideoRenditionBudgetNanoseconds
        let results = await withTaskGroup(of: (Int, HLSRendition)?.self, returning: [(Int, HLSRendition)].self) { group in
            for (index, track) in tracks.enumerated() {
                group.addTask {
                    await makeOptionalVideoRendition(
                        for: track,
                        index: index,
                        durationHint: durationHint,
                        headers: headers,
                        metricsID: metricsID,
                        budget: budget
                    )
                }
            }
            var renditions = [(Int, HLSRendition)]()
            for await result in group {
                if let result {
                    renditions.append(result)
                }
            }
            return renditions
        }
        let renditions = results
            .sorted { $0.0 < $1.0 }
            .map(\.1)
        if renditions.count < tracks.count {
            await recordManifestStage(
                metricsID: metricsID,
                "alternateVideo=\(renditions.count)/\(tracks.count)"
            )
        }
        return renditions
    }

    private nonisolated static func makeOptionalVideoRendition(
        for track: HLSBridgeTrack,
        index: Int,
        durationHint: TimeInterval?,
        headers: [String: String],
        metricsID: String?,
        budget: UInt64
    ) async -> (Int, HLSRendition)? {
        let buildTask = Task(priority: .utility) { () -> HLSRendition? in
            guard !Task.isCancelled else { return nil }
            do {
                return try await makeRendition(
                    for: track,
                    durationHint: durationHint,
                    headers: headers,
                    metricsID: metricsID
                )
            } catch {
                PlayerMetricsLog.logger.info(
                    "hlsBridgeAlternateVideoSkipped q=\(track.stream?.id ?? -1, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
                return nil
            }
        }
        let timeoutTask = Task(priority: .utility) { () -> HLSRendition? in
            try? await Task.sleep(nanoseconds: budget)
            return nil
        }
        let rendition = await withTaskGroup(of: HLSRendition?.self, returning: HLSRendition?.self) { group in
            group.addTask { await buildTask.value }
            group.addTask { await timeoutTask.value }
            let firstResult = await group.next() ?? nil
            group.cancelAll()
            buildTask.cancel()
            timeoutTask.cancel()
            return firstResult
        }
        guard let rendition else {
            PlayerMetricsLog.logger.info(
                "hlsBridgeAlternateVideoTimedOut q=\(track.stream?.id ?? -1, privacy: .public)"
            )
            return nil
        }
        return (index, rendition)
    }

    private nonisolated static var optionalVideoRenditionBudgetNanoseconds: UInt64 {
        switch PlaybackEnvironment.current.networkClass {
        case .wifi:
            return 260_000_000
        case .unknown:
            return 180_000_000
        case .cellular, .constrained:
            return 120_000_000
        }
    }

    private nonisolated static var optionalVideoRenditionPostPrimaryWaitNanoseconds: UInt64 {
        guard !AVPlayerStartupPathOptimizationExperiment.stored() else { return 0 }
        switch PlaybackEnvironment.current.networkClass {
        case .wifi:
            return 220_000_000
        case .unknown:
            return 160_000_000
        case .cellular, .constrained:
            return 100_000_000
        }
    }

    private nonisolated static func formatMilliseconds(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        if rounded >= 1000 {
            return String(format: "%.2fs", Double(rounded) / 1000)
        }
        return "\(rounded)ms"
    }

    private nonisolated static func startupWarmRanges(
        initialization: HTTPByteRange,
        references: [SIDXParser.Reference]
    ) -> [HTTPByteRange] {
        var ranges = [initialization]
        ranges += references.prefix(1).map(\.range)
        return ranges
    }

    private nonisolated static func warmRanges(
        _ ranges: [HTTPByteRange],
        from urls: [URL],
        headers: [String: String],
        strategy: HLSByteRangeFetchStrategy,
        delayStepNanoseconds: UInt64 = 180_000_000
    ) async {
        await withTaskGroup(of: Void.self) { group in
            for (index, range) in ranges.enumerated() {
                group.addTask {
                    if index > 0 {
                        try? await Task.sleep(nanoseconds: UInt64(index) * delayStepNanoseconds)
                    }
                    await warmRange(range, from: urls, headers: headers, strategy: strategy)
                }
            }
        }
    }

    private nonisolated static func warmRange(
        _ range: HTTPByteRange?,
        from urls: [URL],
        headers: [String: String],
        strategy: HLSByteRangeFetchStrategy
    ) async {
        guard let range else { return }
        _ = try? await fetchByteRange(range, from: urls, headers: headers, strategy: strategy)
    }

    private nonisolated static func makeRendition(
        for track: HLSBridgeTrack,
        durationHint: TimeInterval?,
        headers: [String: String],
        metricsID: String?,
        renderingPolicy: DolbyVisionRenderingPolicy? = nil
    ) async throws -> HLSRendition {
        guard let segmentBase = track.stream?.segmentBase,
              let initialization = segmentBase.initializationByteRange,
              let indexRange = segmentBase.indexByteRange
        else {
            throw PlayerEngineError.unsupportedMedia
        }

        let start = CACurrentMediaTime()
        let mediaType = track.mediaType.logLabel
        PlayerMetricsLog.logger.info(
            "hlsBridgeRenditionStart media=\(mediaType, privacy: .public) quality=\(track.stream?.id ?? -1, privacy: .public) index=\(indexRange.start, privacy: .public)-\(indexRange.endInclusive, privacy: .public)"
        )
        let renditionResult = try await HLSRenditionCache.shared.cachedOrBuild(
            for: renditionCacheKey(
                for: track,
                initialization: initialization,
                indexRange: indexRange,
                renderingPolicy: renderingPolicy
            )
        ) {
            let fetchStart = CACurrentMediaTime()
            let sourceURLs = [track.url] + track.fallbackURLs
            let bootstrapPayload = try await fetchRenditionBootstrapPayload(
                initialization: initialization,
                indexRange: indexRange,
                from: sourceURLs,
                headers: headers
            )
            let initializationData = try await resolvedInitializationData(
                bootstrapPayload.initializationData,
                for: track,
                initialization: initialization,
                from: sourceURLs,
                headers: headers
            )
            await recordManifestStage(
                metricsID: metricsID,
                "\(mediaType)Boot=\(bootstrapPayload.mode) \(formatMilliseconds(PlayerMetricsLog.elapsedMilliseconds(since: fetchStart)))"
            )
            PlayerMetricsLog.logger.info(
                "hlsBridgeIndexFetched media=\(mediaType, privacy: .public) mode=\(bootstrapPayload.mode, privacy: .public) bytes=\(bootstrapPayload.indexData.count, privacy: .public) initBytes=\(initializationData?.count ?? 0, privacy: .public) elapsedMs=\(PlayerMetricsLog.elapsedMilliseconds(since: fetchStart), format: .fixed(precision: 1), privacy: .public)"
            )
            let parseStart = CACurrentMediaTime()
            let references = try SIDXParser.parseReferences(from: bootstrapPayload.indexData, sidxStartOffset: indexRange.start)
            guard !references.isEmpty else {
                throw PlayerEngineError.unsupportedMedia
            }
            let resolvedTimelineOffset = await startupTimelineOffset(
                for: track,
                references: references,
                headers: headers,
                metricsID: metricsID
            )
            PlayerMetricsLog.logger.info(
                "hlsBridgeIndexParsed media=\(mediaType, privacy: .public) refs=\(references.count, privacy: .public) elapsedMs=\(PlayerMetricsLog.elapsedMilliseconds(since: parseStart), format: .fixed(precision: 1), privacy: .public)"
            )
            return try makeRendition(
                for: track,
                initialization: initialization,
                initializationData: initializationData,
                references: references,
                durationHint: durationHint,
                timelineOffsetOverride: resolvedTimelineOffset,
                renderingPolicy: renderingPolicy
            )
        }
        let rendition = renditionResult.rendition
        let elapsedMilliseconds = PlayerMetricsLog.elapsedMilliseconds(since: start)
        PlayerMetricsLog.logger.info(
            "hlsBridgeRenditionReady media=\(mediaType, privacy: .public) state=\(renditionResult.state.rawValue, privacy: .public) elapsedMs=\(elapsedMilliseconds, format: .fixed(precision: 1), privacy: .public)"
        )
        await recordManifestStage(
            metricsID: metricsID,
            "\(mediaType)=\(renditionResult.state.rawValue) \(formatMilliseconds(elapsedMilliseconds)) refs=\(rendition.references.count)"
        )
        return rendition
    }

    private struct HLSRenditionBootstrapPayload: Sendable {
        let initializationData: Data?
        let indexData: Data
        let mode: String
    }

    private nonisolated static func fetchRenditionBootstrapPayload(
        initialization: HTTPByteRange,
        indexRange: HTTPByteRange,
        from urls: [URL],
        headers: [String: String]
    ) async throws -> HLSRenditionBootstrapPayload {
        let strategy = bootstrapFetchStrategy(urlCount: urls.count)
        if let combinedRange = combinedBootstrapRange(initialization: initialization, indexRange: indexRange) {
            do {
                let combinedData = try await fetchByteRange(
                    combinedRange,
                    from: urls,
                    headers: headers,
                    policy: strategy
                )
                if let initializationData = dataSlice(for: initialization, in: combinedData, baseRange: combinedRange),
                   let indexData = dataSlice(for: indexRange, in: combinedData, baseRange: combinedRange) {
                    return HLSRenditionBootstrapPayload(
                        initializationData: initializationData,
                        indexData: indexData,
                        mode: "\(strategy.fetchStrategy.logLabel)+init"
                    )
                }
            } catch {
                PlayerMetricsLog.logger.info(
                    "hlsBridgeBootstrapCombinedFallback range=\(combinedRange.start, privacy: .public)-\(combinedRange.endInclusive, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
            }
        }

        let indexData = try await fetchByteRange(
            indexRange,
            from: urls,
            headers: headers,
            policy: strategy
        )
        return HLSRenditionBootstrapPayload(
            initializationData: nil,
            indexData: indexData,
            mode: strategy.fetchStrategy.logLabel
        )
    }

    private nonisolated static func combinedBootstrapRange(
        initialization: HTTPByteRange,
        indexRange: HTTPByteRange
    ) -> HTTPByteRange? {
        guard initialization.length > 0, indexRange.length > 0 else { return nil }
        let lowerBound = min(initialization.start, indexRange.start)
        let upperBound = max(initialization.endInclusive, indexRange.endInclusive)
        guard upperBound >= lowerBound else { return nil }

        let gap: Int64
        if initialization.endInclusive < indexRange.start {
            gap = indexRange.start - initialization.endInclusive - 1
        } else if indexRange.endInclusive < initialization.start {
            gap = initialization.start - indexRange.endInclusive - 1
        } else {
            gap = 0
        }

        let combinedLength = upperBound - lowerBound + 1
        guard gap <= maxBootstrapCombinedGapBytes,
              combinedLength <= maxBootstrapCombinedRangeBytes
        else { return nil }
        return HTTPByteRange(start: lowerBound, endInclusive: upperBound)
    }

    private nonisolated static func dataSlice(
        for range: HTTPByteRange,
        in data: Data,
        baseRange: HTTPByteRange
    ) -> Data? {
        guard range.start >= baseRange.start,
              range.endInclusive <= baseRange.endInclusive,
              let lowerBound = Int(exactly: range.start - baseRange.start),
              let length = Int(exactly: range.length),
              length > 0,
              lowerBound >= 0,
              lowerBound + length <= data.count
        else { return nil }
        return data.subdata(in: lowerBound..<(lowerBound + length))
    }

    private nonisolated static func fetchIndexRange(
        indexRange: HTTPByteRange,
        from urls: [URL],
        headers: [String: String]
    ) async throws -> (indexData: Data, mode: String) {
        let strategy = bootstrapFetchStrategy(urlCount: urls.count)
        let indexData = try await fetchByteRange(
            indexRange,
            from: urls,
            headers: headers,
            policy: strategy
        )
        return (indexData, strategy.fetchStrategy.logLabel)
    }

    private nonisolated static func bootstrapFetchStrategy(urlCount: Int) -> HLSBootstrapFetchPolicy {
        let strategy: HLSByteRangeFetchStrategy = PlaybackEnvironment.current.shouldPreferConservativePlayback
            ? .sequential
            : .fastFallback
        return HLSBootstrapFetchPolicy(
            fetchStrategy: strategy,
            remoteRequestPolicy: .startupIndex(urlCount: urlCount)
        )
    }

    private nonisolated static let maxBootstrapCombinedRangeBytes: Int64 = 256 * 1024
    private nonisolated static let maxBootstrapCombinedGapBytes: Int64 = 32 * 1024

    fileprivate nonisolated static func fetchByteRange(
        _ range: HTTPByteRange,
        from url: URL,
        headers: [String: String]
    ) async throws -> Data {
        try await VideoRangeCache.shared.cachedOrFetch(url: url, range: range) {
            try await fetchRemoteByteRangeWithRetry(
                range,
                from: url,
                headers: headers,
                policy: .default(for: range)
            )
        }
    }

    fileprivate nonisolated static func fetchByteRange(
        _ range: HTTPByteRange,
        from urls: [URL],
        headers: [String: String],
        strategy: HLSByteRangeFetchStrategy = .sequential
    ) async throws -> Data {
        try await fetchByteRange(
            range,
            from: urls,
            headers: headers,
            policy: HLSBootstrapFetchPolicy(
                fetchStrategy: strategy,
                remoteRequestPolicy: .default(for: range)
            )
        )
    }

    fileprivate nonisolated static func fetchByteRange(
        _ range: HTTPByteRange,
        from urls: [URL],
        headers: [String: String],
        policy: HLSBootstrapFetchPolicy
    ) async throws -> Data {
        let canonicalSourceURLs = urls.removingDuplicates()
        guard let primaryURL = canonicalSourceURLs.first else {
            throw PlayerEngineError.unsupportedMedia
        }
        let sourceURLs = await HLSSourcePreferenceCache.shared.preferredURLs(for: canonicalSourceURLs)
        guard policy.fetchStrategy.isFastFallback, sourceURLs.count > 1 else {
            return try await fetchByteRangeSequential(
                range,
                from: sourceURLs,
                primaryURL: primaryURL,
                headers: headers,
                remoteRequestPolicy: policy.remoteRequestPolicy
            )
        }

        return try await fetchByteRangeFastFallback(
            range,
            from: sourceURLs,
            primaryURL: primaryURL,
            headers: headers,
            remoteRequestPolicy: policy.remoteRequestPolicy
        )
    }

    private nonisolated static func fetchByteRangeSequential(
        _ range: HTTPByteRange,
        from sourceURLs: [URL],
        primaryURL: URL,
        headers: [String: String],
        remoteRequestPolicy: HLSRemoteByteRangeRequestPolicy
    ) async throws -> Data {
        guard !sourceURLs.isEmpty else {
            throw PlayerEngineError.unsupportedMedia
        }
        var lastError: Error?
        for (index, url) in sourceURLs.enumerated() {
            let fetchStart = CACurrentMediaTime()
            do {
                let cacheResult = try await VideoRangeCache.shared.cachedOrFetchWithSource(url: url, range: range) {
                    try await fetchRemoteByteRangeWithRetry(
                        range,
                        from: url,
                        headers: headers,
                        policy: remoteRequestPolicy
                    )
                }
                let data = cacheResult.data
                if cacheResult.source == .remote {
                    await HLSSourcePreferenceCache.shared.recordResult(
                        url: url,
                        for: sourceURLs,
                        elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: fetchStart),
                        bytes: Int64(data.count),
                        succeeded: true
                    )
                }
                if index > 0 {
                    if cacheResult.source == .remote {
                        await HLSSourcePreferenceCache.shared.recordPreferredURL(url, for: sourceURLs)
                    }
                    await VideoRangeCache.shared.store(data, url: primaryURL, range: range)
                    PlayerMetricsLog.logger.info(
                        "hlsBridgeByteRangeFallbackSuccess fallbackIndex=\(index, privacy: .public) range=\(range.start, privacy: .public)-\(range.endInclusive, privacy: .public)"
                    )
                }
                return data
            } catch {
                await HLSSourcePreferenceCache.shared.recordFailure(
                    url: url,
                    for: sourceURLs,
                    elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: fetchStart),
                    error: error
                )
                lastError = error
                guard index < sourceURLs.count - 1, !Task.isCancelled else { break }
                PlayerMetricsLog.logger.info(
                    "hlsBridgeByteRangeFallbackSwitch fallbackIndex=\(index + 1, privacy: .public) range=\(range.start, privacy: .public)-\(range.endInclusive, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
            }
        }
        throw lastError ?? PlayerEngineError.unsupportedMedia
    }

    private nonisolated static func fetchByteRangeFastFallback(
        _ range: HTTPByteRange,
        from sourceURLs: [URL],
        primaryURL: URL,
        headers: [String: String],
        remoteRequestPolicy: HLSRemoteByteRangeRequestPolicy
    ) async throws -> Data {
        let result: Result<(index: Int, data: Data, source: VideoRangeCacheFetchSource), Error> = await withTaskGroup(of: Result<(index: Int, data: Data, source: VideoRangeCacheFetchSource), Error>.self) { group in
            for (index, url) in sourceURLs.enumerated() {
                group.addTask(priority: .userInitiated) {
                    let fetchStart = CACurrentMediaTime()
                    do {
                        if index > 0 {
                            let delay = remoteRequestPolicy.fastFallbackDelayNanoseconds(forSourceIndex: index)
                            try await Task.sleep(nanoseconds: delay)
                        }
                        let cacheResult = try await VideoRangeCache.shared.cachedOrFetchWithSource(url: url, range: range) {
                            try await fetchRemoteByteRangeWithRetry(
                                range,
                                from: url,
                                headers: headers,
                                policy: remoteRequestPolicy
                            )
                        }
                        let data = cacheResult.data
                        if cacheResult.source == .remote {
                            await HLSSourcePreferenceCache.shared.recordResult(
                                url: url,
                                for: sourceURLs,
                                elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: fetchStart),
                                bytes: Int64(data.count),
                                succeeded: true
                            )
                        }
                        return .success((index, data, cacheResult.source))
                    } catch {
                        await HLSSourcePreferenceCache.shared.recordFailure(
                            url: url,
                            for: sourceURLs,
                            elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: fetchStart),
                            error: error
                        )
                        return .failure(error)
                    }
                }
            }

            var lastError: Error?
            for await result in group {
                switch result {
                case let .success(payload):
                    group.cancelAll()
                    return Result<(index: Int, data: Data, source: VideoRangeCacheFetchSource), Error>.success(payload)
                case let .failure(error):
                    lastError = error
                }
            }
            return .failure(lastError ?? PlayerEngineError.unsupportedMedia)
        }

        switch result {
        case let .success(payload):
            if payload.source == .remote, let preferredURL = sourceURLs[safe: payload.index] {
                await HLSSourcePreferenceCache.shared.recordPreferredURL(preferredURL, for: sourceURLs)
            }
            if payload.index > 0 {
                await VideoRangeCache.shared.store(payload.data, url: primaryURL, range: range)
                PlayerMetricsLog.logger.info(
                    "hlsBridgeByteRangeFastFallbackSuccess fallbackIndex=\(payload.index, privacy: .public) range=\(range.start, privacy: .public)-\(range.endInclusive, privacy: .public)"
                )
            }
            return payload.data
        case let .failure(error):
            throw error
        }
    }

    private nonisolated static func fetchRemoteByteRangeWithRetry(
        _ range: HTTPByteRange,
        from url: URL,
        headers: [String: String],
        policy: HLSRemoteByteRangeRequestPolicy
    ) async throws -> Data {
        var lastError: Error?
        for attempt in 0..<policy.attempts {
            do {
                return try await fetchRemoteByteRange(
                    range,
                    from: url,
                    headers: headers,
                    timeoutInterval: policy.timeoutInterval(for: range)
                )
            } catch {
                lastError = error
                guard attempt < policy.attempts - 1, !Task.isCancelled else { break }
                PlayerMetricsLog.logger.info(
                    "hlsBridgeByteRangeRetry attempt=\(attempt + 1, privacy: .public) range=\(range.start, privacy: .public)-\(range.endInclusive, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
                try? await Task.sleep(nanoseconds: policy.retryDelayNanoseconds)
            }
        }
        throw lastError ?? PlayerEngineError.unsupportedMedia
    }

    fileprivate nonisolated static func fetchRemoteByteRange(
        _ range: HTTPByteRange,
        from url: URL,
        headers: [String: String]
    ) async throws -> Data {
        try await fetchRemoteByteRange(
            range,
            from: url,
            headers: headers,
            timeoutInterval: HLSRemoteByteRangeRequestPolicy.default(for: range).timeoutInterval(for: range)
        )
    }

    fileprivate nonisolated static func fetchRemoteByteRange(
        _ range: HTTPByteRange,
        from url: URL,
        headers: [String: String],
        timeoutInterval: TimeInterval
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = timeoutInterval
        request.networkServiceType = .video
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.setValue("bytes=\(range.start)-\(range.endInclusive)", forHTTPHeaderField: "Range")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await BiliPlaybackNetworkSessionPool.shared.playbackDataSession().data(for: request)
        } catch let error as URLError {
            throw HLSBridgeRemoteFailure.urlSession(error, url: url, range: range)
        } catch {
            throw error
        }
        do {
            try HLSRemoteRangeResponseValidator.validate(response, requestedRange: range, url: url)
        } catch {
            if let httpResponse = response as? HTTPURLResponse {
                PlayerMetricsLog.logger.error(
                    "hlsBridgeByteRangeHTTPError status=\(httpResponse.statusCode, privacy: .public) range=\(range.start, privacy: .public)-\(range.endInclusive, privacy: .public) url=\(url.absoluteString, privacy: .private)"
                )
            }
            throw error
        }
        guard !data.isEmpty else {
            PlayerMetricsLog.logger.error(
                "hlsBridgeByteRangeEmptyResponse range=\(range.start, privacy: .public)-\(range.endInclusive, privacy: .public) url=\(url.absoluteString, privacy: .private)"
            )
            throw HLSBridgeRemoteFailure.emptyResponse(url: url, range: range)
        }
        return data
    }

    @discardableResult
    nonisolated static func warmup(
        videoTrack: HLSBridgeTrack,
        audioTrack: HLSBridgeTrack?,
        headers: [String: String],
        around playbackTime: TimeInterval? = nil
    ) async -> Bool {
        await warmup(
            videoTracks: [videoTrack],
            audioTrack: audioTrack,
            headers: headers,
            around: playbackTime
        )
    }

    nonisolated static func warmStartupPackets(
        videoTrack: HLSBridgeTrack,
        audioTrack: HLSBridgeTrack,
        headers: [String: String]
    ) async -> HLSStartupPacketWarmupResult {
        async let videoReady = warmup(track: videoTrack, headers: headers)
        async let audioReady = warmup(track: audioTrack, headers: headers)
        let result = await (videoReady, audioReady)
        return HLSStartupPacketWarmupResult(
            videoReady: result.0,
            audioReady: result.1
        )
    }

    @discardableResult
    nonisolated static func warmup(
        videoTracks: [HLSBridgeTrack],
        audioTrack: HLSBridgeTrack?,
        headers: [String: String],
        around playbackTime: TimeInterval? = nil
    ) async -> Bool {
        let tracks = videoTracks + [audioTrack].compactMap { $0 }
        guard !tracks.isEmpty else { return false }
        return await withTaskGroup(of: Bool.self, returning: Bool.self) { group in
            for track in tracks {
                group.addTask(priority: .utility) {
                    await warmup(track: track, headers: headers, around: playbackTime)
                }
            }

            var didWarm = false
            for await result in group where result {
                didWarm = true
            }
            return didWarm
        }
    }

    nonisolated static func clearWarmupCache(for mediaURLs: Set<String> = []) async {
        guard !mediaURLs.isEmpty else {
            await HLSBridgeRoutePlanCache.shared.removeAll()
            await LocalHLSBridgeInstanceCache.shared.removeAll()
            await HLSRenditionCache.shared.removeAll()
            return
        }
        await HLSBridgeRoutePlanCache.shared.removeAll(containingAny: mediaURLs)
        await LocalHLSBridgeInstanceCache.shared.removeAll(containingAny: mediaURLs)
        await HLSRenditionCache.shared.removeAll(containingAny: mediaURLs)
    }

    nonisolated static func sourceDiagnostics(for urls: [URL]) async -> [HLSBridgeSourceDiagnosticsSnapshot] {
        await HLSSourcePreferenceCache.shared.diagnostics(for: urls)
    }

    private nonisolated static func warmup(
        track: HLSBridgeTrack,
        headers: [String: String],
        around playbackTime: TimeInterval? = nil
    ) async -> Bool {
        guard let segmentBase = track.stream?.segmentBase,
              let initialization = segmentBase.initializationByteRange,
              let indexRange = segmentBase.indexByteRange
        else { return false }

        do {
            let sourceURLs = [track.url] + track.fallbackURLs
            let renditionResult = try await HLSRenditionCache.shared.cachedOrBuild(
                for: renditionCacheKey(
                    for: track,
                    initialization: initialization,
                    indexRange: indexRange,
                    renderingPolicy: nil
                )
            ) {
                let bootstrapPayload = try await fetchRenditionBootstrapPayload(
                    initialization: initialization,
                    indexRange: indexRange,
                    from: sourceURLs,
                    headers: headers
                )
                let initializationData = try await resolvedInitializationData(
                    bootstrapPayload.initializationData,
                    for: track,
                    initialization: initialization,
                    from: sourceURLs,
                    headers: headers
                )
                let references = try SIDXParser.parseReferences(from: bootstrapPayload.indexData, sidxStartOffset: indexRange.start)
                guard !references.isEmpty else {
                    throw PlayerEngineError.unsupportedMedia
                }
                let resolvedTimelineOffset = await startupTimelineOffset(
                    for: track,
                    references: references,
                    headers: headers,
                    metricsID: nil
                )
                return try makeRendition(
                    for: track,
                    initialization: initialization,
                    initializationData: initializationData,
                    references: references,
                    durationHint: nil,
                    timelineOffsetOverride: resolvedTimelineOffset
                )
            }
            let strategy = bootstrapFetchStrategy(urlCount: sourceURLs.count)
            await warmRanges(
                warmRanges(
                    initialization: initialization,
                    references: renditionResult.rendition.references,
                    mediaTimeOffset: renditionResult.rendition.mediaTimeOffset,
                    includeExtraVideoSegment: track.mediaType.isVideo,
                    around: playbackTime
                ),
                from: sourceURLs,
                headers: headers,
                strategy: strategy.fetchStrategy,
                delayStepNanoseconds: 0
            )
            return true
        } catch {
            return false
        }
    }

    private nonisolated static func warmRanges(
        initialization: HTTPByteRange,
        references: [SIDXParser.Reference],
        mediaTimeOffset: TimeInterval,
        includeExtraVideoSegment: Bool,
        around playbackTime: TimeInterval?
    ) -> [HTTPByteRange] {
        guard let playbackTime, playbackTime.isFinite, playbackTime > 0 else {
            return startupWarmRanges(
                initialization: initialization,
                references: references
            )
        }
        guard !references.isEmpty else { return [initialization] }
        let targetTime = max(0, playbackTime + mediaTimeOffset)
        let startIndex = references.lastIndex { reference in
            reference.startTime <= targetTime
        } ?? 0
        let segmentCount = includeExtraVideoSegment ? 3 : 2
        let endIndex = min(references.count, startIndex + segmentCount)
        return [initialization] + references[startIndex..<endIndex].map(\.range)
    }

    private nonisolated static func makeRendition(
        for track: HLSBridgeTrack,
        initialization: HTTPByteRange,
        initializationData: Data?,
        references: [SIDXParser.Reference],
        durationHint: TimeInterval?,
        timelineOffsetOverride: HLSRenditionTimelineOffset?,
        renderingPolicy: DolbyVisionRenderingPolicy? = nil
    ) throws -> HLSRendition {
        let timelineOffset = timelineOffsetOverride ?? HLSRenditionTimelineOffset(
            baseMediaDecodeTimeTicks: references.first?.startTimeTicks ?? 0
        )
        let mediaTimeOffsetTicks = timelineOffset.baseMediaDecodeTimeTicks
        let timescale = references.first?.timescale ?? 0
        let mediaTimeOffset = timescale > 0
            ? TimeInterval(mediaTimeOffsetTicks) / TimeInterval(timescale)
            : references.first?.startTime ?? 0
        let dolbyVisionConfiguration = dolbyVisionConfiguration(
            for: track,
            initializationData: initializationData
        )
        let dolbyVisionRenderingPolicy = (renderingPolicy ?? DolbyVisionRenderingPolicy.stored().hlsBridgePolicy).playablePolicy
        let streamCodec = normalizedCodec(track.stream?.codecs, mediaType: track.mediaType)
        let usesHEVCCompatibleHLS = track.dynamicRange == .dolbyVision && dolbyVisionConfiguration == nil
            ? false
            : usesHEVCCompatibleHLS(for: track, codec: streamCodec)
        let hevcInitializationNormalization = dolbyVisionConfiguration == nil && usesHEVCCompatibleHLS
            ? DolbyVisionCodecConfiguration.normalizedHEVCInitializationDataForHLS(initializationData)
            : nil
        let initializationNormalization = dolbyVisionConfiguration?.normalizedInitializationDataForHLS(
            initializationData,
            renderingPolicy: dolbyVisionRenderingPolicy
        )
            ?? hevcInitializationNormalization
        let normalizedInitializationData = initializationNormalization?.data ?? initializationData
        let videoColorInformation = track.mediaType.isVideo
            ? DolbyVisionCodecConfiguration.videoColorInformation(from: normalizedInitializationData ?? initializationData)
            : nil
        let hlsBaseLayerCodec = initializationNormalization?.hlsBaseLayerCodec
            ?? (usesHEVCCompatibleHLS
                ? DolbyVisionCodecConfiguration.hlsCompatibleHEVCCodec(from: streamCodec, initializationData: initializationData)
                : nil)
        let rendition = HLSRendition(
            sourceURL: track.url,
            fallbackSourceURLs: track.fallbackURLs,
            mediaType: track.mediaType,
            quality: track.stream?.id,
            initialization: initialization,
            initializationData: normalizedInitializationData,
            references: references,
            targetDuration: max(references.map(\.duration).max() ?? durationHint ?? 1, 1),
            bandwidth: max(track.stream?.bandwidth ?? 0, 128_000),
            codec: streamCodec,
            mediaTimeOffset: mediaTimeOffset,
            baseMediaDecodeTimeOffsetTicks: timelineOffset.baseMediaDecodeTimeTicks,
            dynamicRange: track.dynamicRange,
            dolbyVisionConfiguration: dolbyVisionConfiguration,
            dolbyVisionRenderingPolicy: dolbyVisionRenderingPolicy,
            videoColorInformation: videoColorInformation,
            hlsBaseLayerCodec: hlsBaseLayerCodec,
            dimensions: track.stream?.hlsDimensions,
            frameRate: DASHStream.numericFrameRate(from: track.stream?.frameRate)
        )
        if let dolbyVisionConfiguration {
            PlayerMetricsLog.logger.info(
                "hlsBridgeDolbyVisionConfigured q=\(track.stream?.id ?? -1, privacy: .public) policy=\(dolbyVisionRenderingPolicy.rawValue, privacy: .public) sourceCodec=\(rendition.codec, privacy: .public) baseCodec=\(rendition.hlsCompatibleBaseLayerCodec, privacy: .public) box=\(dolbyVisionConfiguration.boxType, privacy: .public) profile=\(dolbyVisionConfiguration.profile, privacy: .public) level=\(dolbyVisionConfiguration.level, privacy: .public) compatibility=\(dolbyVisionConfiguration.baseLayerSignalCompatibilityID, privacy: .public) color=\(videoColorInformation?.diagnosticSummary ?? "-", privacy: .public) sampleEntry=\(initializationNormalization?.originalSampleEntryType ?? "-", privacy: .public) hlsSampleEntry=\(initializationNormalization?.hlsSampleEntryType ?? "-", privacy: .public) initRewrite=\(initializationNormalization?.didRewriteSampleEntry == true, privacy: .public) hlsCodec=\(rendition.hlsAdvertisedCodec, privacy: .public) videoRange=\(rendition.hlsVideoRangeValue ?? "-", privacy: .public) supplemental=\(rendition.hlsAdvertisedSupplementalCodec ?? "-", privacy: .public)"
            )
        } else if usesHEVCCompatibleHLS {
            PlayerMetricsLog.logger.info(
                "hlsBridgeHEVCConfigured q=\(track.stream?.id ?? -1, privacy: .public) dynamicRange=\(track.dynamicRange.rawValue, privacy: .public) color=\(videoColorInformation?.diagnosticSummary ?? "-", privacy: .public) sourceCodec=\(rendition.codec, privacy: .public) hlsCodec=\(rendition.hlsAdvertisedCodec, privacy: .public) videoRange=\(rendition.hlsVideoRangeValue ?? "-", privacy: .public) sampleEntry=\(initializationNormalization?.originalSampleEntryType ?? "-", privacy: .public) hlsSampleEntry=\(initializationNormalization?.hlsSampleEntryType ?? "-", privacy: .public) initRewrite=\(initializationNormalization?.didRewriteSampleEntry == true, privacy: .public)"
            )
        }
        return rendition
    }

    private nonisolated static func resolvedInitializationData(
        _ existingData: Data?,
        for track: HLSBridgeTrack,
        initialization: HTTPByteRange,
        from sourceURLs: [URL],
        headers: [String: String]
    ) async throws -> Data? {
        guard existingData == nil,
              track.mediaType.isVideo,
              track.dynamicRange.isHDR
        else { return existingData }
        return try await fetchByteRange(
            initialization,
            from: sourceURLs,
            headers: headers,
            policy: bootstrapFetchStrategy(urlCount: sourceURLs.count)
        )
    }

    private nonisolated static func dolbyVisionConfiguration(
        for track: HLSBridgeTrack,
        initializationData: Data?
    ) -> DolbyVisionCodecConfiguration? {
        guard track.mediaType.isVideo,
              track.dynamicRange == .dolbyVision
        else { return nil }
        guard let configuration = DolbyVisionCodecConfiguration.parse(from: initializationData) else {
            PlayerMetricsLog.logger.info(
                "hlsBridgeDolbyVisionFallback reason=missingConfiguration codec=\(track.stream?.codecs ?? "-", privacy: .public) q=\(track.stream?.id ?? -1, privacy: .public)"
            )
            return nil
        }
        return configuration
    }

    private nonisolated static func usesHEVCCompatibleHLS(for track: HLSBridgeTrack, codec: String) -> Bool {
        guard track.mediaType.isVideo else { return false }
        let lowercasedCodec = codec.lowercased()
        return track.dynamicRange.isHDR
            || track.stream?.isHEVCVideoCodec == true
            || lowercasedCodec.contains("hvc1")
            || lowercasedCodec.contains("hev1")
            || lowercasedCodec.contains("dvh1")
            || lowercasedCodec.contains("dvhe")
    }

    private nonisolated static func startupTimelineOffset(
        for track: HLSBridgeTrack,
        references: [SIDXParser.Reference],
        headers _: [String: String],
        metricsID: String?
    ) async -> HLSRenditionTimelineOffset? {
        guard let firstReference = references.first else { return nil }
        await recordManifestStage(
            metricsID: metricsID,
            "\(track.mediaType.logLabel)Probe=sidx"
        )
        return HLSRenditionTimelineOffset(
            baseMediaDecodeTimeTicks: firstReference.startTimeTicks
        )
    }

    private nonisolated static func renditionCacheKey(
        for track: HLSBridgeTrack,
        initialization: HTTPByteRange,
        indexRange: HTTPByteRange,
        renderingPolicy: DolbyVisionRenderingPolicy? = nil
    ) -> String {
        let mediaType = switch track.mediaType {
        case .audio:
            "audio"
        case .video:
            "video"
        }
        let policy = (renderingPolicy ?? DolbyVisionRenderingPolicy.stored().hlsBridgePolicy).playablePolicy
        return [
            "timeline-v22-dv-apple-native-policy",
            mediaType,
            track.cacheIdentity,
            "\(initialization.start)-\(initialization.endInclusive)",
            "\(indexRange.start)-\(indexRange.endInclusive)",
            "\(track.stream?.bandwidth ?? 0)",
            track.stream?.codecs ?? "",
            track.dynamicRange.rawValue,
            policy.rawValue
        ].joined(separator: "|")
    }

    private nonisolated static func bridgeCacheKey(
        videoTracks: [HLSBridgeTrack],
        audioTrack: HLSBridgeTrack,
        headers: [String: String]
    ) -> String? {
        let videoKeys = videoTracks.compactMap(bridgeTrackCacheKey(for:))
        guard videoKeys.count == videoTracks.count,
              let audioKey = bridgeTrackCacheKey(for: audioTrack)
        else { return nil }
        let headerKey = headerCacheKey(headers)
        return [
            "route-plan-v8-media-identity",
            videoKeys.joined(separator: "@@"),
            audioKey,
            headerKey
        ].joined(separator: "||")
    }

    private nonisolated static func headerCacheKey(_ headers: [String: String]) -> String {
        guard !headers.isEmpty else { return "-" }
        return headers
            .filter { key, _ in
                key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "cookie"
            }
            .map { key, value in
                let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return "\(normalizedKey)=sha256:\(sha256Hex(value))"
            }
            .sorted()
            .joined(separator: "&")
    }

    private nonisolated static func sha256Hex(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private nonisolated static func bridgeTrackCacheKey(for track: HLSBridgeTrack) -> String? {
        guard let segmentBase = track.stream?.segmentBase,
              let initialization = segmentBase.initializationByteRange,
              let indexRange = segmentBase.indexByteRange
        else { return nil }
        return renditionCacheKey(for: track, initialization: initialization, indexRange: indexRange)
    }

    private nonisolated static func normalizedCodec(_ codec: String?, mediaType: HLSBridgeTrack.MediaType) -> String {
        guard let codec, !codec.isEmpty else {
            switch mediaType {
            case .audio:
                return "mp4a.40.2"
            case .video:
                return "hvc1.1.6.L120.B0"
            }
        }
        return codec
    }

    fileprivate nonisolated static func formatDuration(_ duration: TimeInterval) -> String {
        String(format: "%.6f", max(duration, 0.001))
    }
}

enum HLSPlaylistAttributeFormatter {
    nonisolated static func frameRateAttribute(for frameRate: Double?) -> String {
        guard let frameRate, frameRate.isFinite, frameRate > 0 else { return "" }
        let rounded = (frameRate * 1000).rounded() / 1000
        guard rounded > 0 else { return "" }
        if rounded.rounded() == rounded {
            return ",FRAME-RATE=\(Int(rounded))"
        }
        var value = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), rounded)
        while value.last == "0" {
            value.removeLast()
        }
        if value.last == "." {
            value.removeLast()
        }
        return ",FRAME-RATE=\(value)"
    }
}

struct HLSRendition: Sendable {
    let sourceURL: URL
    let fallbackSourceURLs: [URL]
    let mediaType: HLSBridgeTrack.MediaType
    let quality: Int?
    let initialization: HTTPByteRange
    let initializationData: Data?
    let references: [SIDXParser.Reference]
    let targetDuration: TimeInterval
    let bandwidth: Int
    let codec: String
    let mediaTimeOffset: TimeInterval
    let baseMediaDecodeTimeOffsetTicks: UInt64
    let dynamicRange: BiliVideoDynamicRange
    let dolbyVisionConfiguration: DolbyVisionCodecConfiguration?
    let dolbyVisionRenderingPolicy: DolbyVisionRenderingPolicy
    let videoColorInformation: VideoColorInformation?
    let hlsBaseLayerCodec: String?
    let dimensions: CGSize?
    let frameRate: Double?

    nonisolated init(
        sourceURL: URL,
        fallbackSourceURLs: [URL],
        mediaType: HLSBridgeTrack.MediaType,
        quality: Int?,
        initialization: HTTPByteRange,
        initializationData: Data?,
        references: [SIDXParser.Reference],
        targetDuration: TimeInterval,
        bandwidth: Int,
        codec: String,
        mediaTimeOffset: TimeInterval,
        baseMediaDecodeTimeOffsetTicks: UInt64,
        dynamicRange: BiliVideoDynamicRange,
        dolbyVisionConfiguration: DolbyVisionCodecConfiguration?,
        dolbyVisionRenderingPolicy: DolbyVisionRenderingPolicy = .stored(),
        videoColorInformation: VideoColorInformation? = nil,
        hlsBaseLayerCodec: String?,
        dimensions: CGSize?,
        frameRate: Double?
    ) {
        self.sourceURL = sourceURL
        self.fallbackSourceURLs = fallbackSourceURLs
        self.mediaType = mediaType
        self.quality = quality
        self.initialization = initialization
        self.initializationData = initializationData
        self.references = references
        self.targetDuration = targetDuration
        self.bandwidth = bandwidth
        self.codec = codec
        self.mediaTimeOffset = mediaTimeOffset
        self.baseMediaDecodeTimeOffsetTicks = baseMediaDecodeTimeOffsetTicks
        self.dynamicRange = dynamicRange
        self.dolbyVisionConfiguration = dolbyVisionConfiguration
        self.dolbyVisionRenderingPolicy = dolbyVisionRenderingPolicy
        self.videoColorInformation = videoColorInformation
        self.hlsBaseLayerCodec = hlsBaseLayerCodec
        self.dimensions = dimensions
        self.frameRate = frameRate
    }

    nonisolated var hlsCompatibleBaseLayerCodec: String {
        hlsBaseLayerCodec ?? DolbyVisionCodecConfiguration.hlsCompatibleBaseLayerCodec(from: codec)
    }

    nonisolated var hlsAdvertisedCodec: String {
        if dynamicRange == .dolbyVision,
           let dolbyVisionConfiguration {
            return dolbyVisionConfiguration.hlsAdvertisedCodec(
                baseLayerCodec: hlsCompatibleBaseLayerCodec,
                renderingPolicy: dolbyVisionRenderingPolicy
            )
        }
        if mediaType.isVideo,
           let hlsBaseLayerCodec {
            return hlsBaseLayerCodec
        }
        return codec
    }

    nonisolated var hlsAdvertisedSupplementalCodecAttribute: String {
        guard let hlsAdvertisedSupplementalCodec else { return "" }
        return ",SUPPLEMENTAL-CODECS=\"\(hlsAdvertisedSupplementalCodec)\""
    }

    nonisolated var hlsAdvertisedSupplementalCodec: String? {
        guard dynamicRange == .dolbyVision,
              let dolbyVisionConfiguration
        else { return nil }
        return dolbyVisionConfiguration.hlsAdvertisedSupplementalCodec(
            baseLayerCodec: hlsCompatibleBaseLayerCodec,
            renderingPolicy: dolbyVisionRenderingPolicy
        )
    }

    nonisolated var hlsVideoRangeAttribute: String {
        guard let hlsVideoRangeValue else { return "" }
        return ",VIDEO-RANGE=\(hlsVideoRangeValue)"
    }

    nonisolated var hlsVideoRangeValue: String? {
        if dynamicRange == .dolbyVision {
            if dolbyVisionRenderingPolicy.playablePolicy == .compatibleHLG
                || dolbyVisionRenderingPolicy.playablePolicy == .metadataPassthrough {
                return videoColorInformation?.hlsVideoRangeAttribute
                    ?? dolbyVisionConfiguration?.hlsVideoRangeAttribute
            }
            return dolbyVisionConfiguration?.hlsVideoRangeAttribute
                ?? videoColorInformation?.hlsVideoRangeAttribute
        }
        return videoColorInformation?.hlsVideoRangeAttribute
    }

    nonisolated var hlsResolutionAttribute: String {
        guard mediaType.isVideo,
              let dimensions,
              dimensions.width > 0,
              dimensions.height > 0
        else { return "" }
        return ",RESOLUTION=\(Int(dimensions.width))x\(Int(dimensions.height))"
    }

    nonisolated var hlsFrameRateAttribute: String {
        guard mediaType.isVideo else { return "" }
        return HLSPlaylistAttributeFormatter.frameRateAttribute(for: frameRate)
    }

    nonisolated var diagnosticSummary: String {
        var parts = [quality.map { "q\($0)" } ?? "q-", hlsAdvertisedCodec]
        if let videoRange = hlsVideoRangeValue {
            parts.append(videoRange)
        }
        if let videoColorInformation {
            parts.append("color=\(videoColorInformation.transferCharacteristics)")
        }
        if let supplemental = hlsAdvertisedSupplementalCodec {
            parts.append("supp=\(supplemental)")
        }
        if dynamicRange == .dolbyVision {
            parts.append("dvPolicy=\(dolbyVisionRenderingPolicy.rawValue)")
            parts.append("dvPath=\(dolbyVisionRenderingPath)")
        }
        return parts.joined(separator: " ")
    }

    nonisolated var dolbyVisionRenderingPath: String {
        switch dolbyVisionRenderingPolicy.playablePolicy {
        case .compatibleHLG:
            return "compatibleBaseLayer"
        case .metadataPassthrough:
            return "metadataPassthrough"
        case .appleNativeP8HLS:
            return "appleNativeP8HLS"
        case .protectedHLG, .fullEffect, .supplementalHLS:
            return "deprecated"
        }
    }

    nonisolated func playlist(baseURL: URL, routePrefix: String) -> String {
        let initURL = mediaURL(baseURL: baseURL, routePrefix: routePrefix, component: "init.mp4")
        let playlistSegments = references.enumerated().map { index, reference in
            let segmentURL = mediaURL(baseURL: baseURL, routePrefix: routePrefix, component: "segment-\(index).m4s")
            return """
            #EXTINF:\(LocalHLSBridge.formatDuration(reference.duration)),
            \(segmentURL.absoluteString)
            """
        }

        return """
        #EXTM3U
        #EXT-X-VERSION:7
        #EXT-X-INDEPENDENT-SEGMENTS
        #EXT-X-PLAYLIST-TYPE:VOD
        #EXT-X-TARGETDURATION:\(Int(ceil(targetDuration)))
        #EXT-X-MAP:URI="\(initURL.absoluteString)"
        \(playlistSegments.joined(separator: "\n"))
        #EXT-X-ENDLIST
        """
    }

    nonisolated func registerRoutes(routePrefix: String, into routes: inout [String: HLSProxyRoute]) {
        let contentType = switch mediaType {
        case .audio:
            "audio/mp4"
        case .video:
            "video/mp4"
        }
        if let initializationData {
            routes["/media/\(routePrefix)/init.mp4"] = .data(initializationData, contentType: contentType)
        } else {
            routes["/media/\(routePrefix)/init.mp4"] = .remoteByteRange(
                url: sourceURL,
                fallbackURLs: fallbackSourceURLs,
                range: initialization,
                contentType: contentType,
                transform: nil
            )
        }

        let segmentTransform = baseMediaDecodeTimeOffsetTicks > 0
            ? HLSMediaSegmentTransform(baseMediaDecodeTimeOffset: baseMediaDecodeTimeOffsetTicks)
            : nil
        for (index, reference) in references.enumerated() {
            routes["/media/\(routePrefix)/segment-\(index).m4s"] = .remoteByteRange(
                url: sourceURL,
                fallbackURLs: fallbackSourceURLs,
                range: reference.range,
                contentType: contentType,
                transform: segmentTransform
            )
        }
    }

    nonisolated func seekMap(includeExtraSegment: Bool) -> HLSBridgeSeekMap {
        HLSBridgeSeekMap(
            sourceURLs: ([sourceURL] + fallbackSourceURLs).removingDuplicates(),
            initialization: initialization,
            segments: references.map {
                HLSBridgeSeekSegment(
                    startTime: max($0.startTime - mediaTimeOffset, 0),
                    duration: $0.duration,
                    range: $0.range
                )
            },
            includeExtraSegment: includeExtraSegment
        )
    }

    nonisolated private func mediaURL(baseURL: URL, routePrefix: String, component: String) -> URL {
        baseURL
            .appendingPathComponent("media")
            .appendingPathComponent(routePrefix)
            .appendingPathComponent(component)
    }
}

struct HLSBridgeRoutePlan: Sendable {
    let videoRenditions: [HLSRendition]
    let audioRendition: HLSRendition
    let masterPlaylistVersion: Int
}

struct HLSBridgeRenderedPlaylists: Sendable {
    let masterPlaylistURL: URL
    let routes: [String: HLSProxyRoute]
}

nonisolated private final class HLSContinuationResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return false }
        didResume = true
        return true
    }
}

private struct HLSBridgeSeekPlanner: Sendable {
    let video: HLSBridgeSeekMap?
    let audio: HLSBridgeSeekMap
    let headers: [String: String]

    nonisolated func alignedSeekTime(near playbackTime: TimeInterval) -> TimeInterval? {
        (video ?? audio).alignedSeekTime(near: playbackTime)
    }

    nonisolated func warm(around playbackTime: TimeInterval, metricsID: String?) async {
        guard !Task.isCancelled else { return }
        let start = CACurrentMediaTime()
        let videoRanges = video?.warmRanges(around: playbackTime) ?? []
        let audioRanges = audio.warmRanges(around: playbackTime)
        guard !videoRanges.isEmpty || !audioRanges.isEmpty else { return }

        await withTaskGroup(of: Bool.self) { group in
            if !videoRanges.isEmpty, !Task.isCancelled {
                group.addTask(priority: .utility) {
                    guard let video else { return false }
                    return await Self.warm(ranges: videoRanges, map: video, headers: headers)
                }
            }
            if !audioRanges.isEmpty, !Task.isCancelled {
                group.addTask(priority: .utility) {
                    await Self.warm(ranges: audioRanges, map: audio, headers: headers)
                }
            }
            var didWarm = false
            for await result in group where result {
                guard !Task.isCancelled else { return }
                didWarm = true
            }
            guard didWarm else { return }
            let elapsed = PlayerMetricsLog.elapsedMilliseconds(since: start)
            await MainActor.run {
                PlayerMetricsLog.record(
                    .mediaCache,
                    metricsID: metricsID ?? "hls-seek-warm",
                    message: "seekWarm target=\(String(format: "%.2fs", playbackTime)) elapsed=\(String(format: "%.0fms", elapsed))"
                )
            }
        }
    }

    private nonisolated static func warm(
        ranges: [HTTPByteRange],
        map: HLSBridgeSeekMap,
        headers: [String: String]
    ) async -> Bool {
        guard !map.sourceURLs.isEmpty else { return false }
        var didWarm = false
        for range in ranges {
            guard !Task.isCancelled else { return didWarm }
            do {
                _ = try await LocalHLSBridge.fetchByteRange(
                    range,
                    from: map.sourceURLs,
                    headers: headers,
                    strategy: .fastFallback
                )
                guard !Task.isCancelled else { return didWarm }
                didWarm = true
            } catch {}
        }
        return didWarm
    }
}

nonisolated private final class LocalLiveHLSProxy: @unchecked Sendable {
    let playlistURL: URL

    private let sourcePlaylistURL: URL
    nonisolated(unsafe) private var headers: [String: String]
    private let metricsID: String?
    private let listener: NWListener
    private let queue: DispatchQueue
    nonisolated(unsafe) private var segmentRoutes: [String: URL] = [:]
    nonisolated(unsafe) private var activeConnections: [ObjectIdentifier: NWConnection] = [:]
    nonisolated(unsafe) private var isStarted = false
    nonisolated(unsafe) private var isClosed = false

    private init(port: UInt16, sourcePlaylistURL: URL, headers: [String: String], metricsID: String?) throws {
        guard let endpointPort = NWEndpoint.Port(rawValue: port),
              let baseURL = URL(string: "http://127.0.0.1:\(port)")
        else {
            throw PlayerEngineError.unsupportedMedia
        }
        self.playlistURL = baseURL.appendingPathComponent("live.m3u8")
        self.sourcePlaylistURL = sourcePlaylistURL
        self.headers = headers
        self.metricsID = metricsID
        self.listener = try NWListener(using: Self.listenerParameters(), on: endpointPort)
        self.queue = DispatchQueue(label: "cc.bili.live-hls.\(port)", qos: .userInitiated)
    }

    deinit {
        listener.cancel()
        activeConnections.values.forEach { $0.cancel() }
    }

    nonisolated func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isClosed = true
            self.isStarted = false
            self.segmentRoutes.removeAll(keepingCapacity: false)
            self.listener.cancel()
            self.activeConnections.values.forEach { $0.cancel() }
            self.activeConnections.removeAll(keepingCapacity: false)
        }
    }

    static func make(playlistURL: URL, headers: [String: String], metricsID: String?) async throws -> LocalLiveHLSProxy {
        var lastError: Error?
        for _ in 0..<24 {
            let port = UInt16.random(in: 49152...61000)
            do {
                let proxy = try LocalLiveHLSProxy(
                    port: port,
                    sourcePlaylistURL: playlistURL,
                    headers: headers,
                    metricsID: metricsID
                )
                try await proxy.start()
                PlayerMetricsLog.logger.info(
                    "directLiveHLSProxyReady url=\(proxy.playlistURL.absoluteString, privacy: .public)"
                )
                return proxy
            } catch {
                lastError = error
            }
        }
        throw lastError ?? PlayerEngineError.unsupportedMedia
    }

    private func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: PlayerEngineError.unsupportedMedia)
                    return
                }
                guard !self.isStarted else {
                    continuation.resume()
                    return
                }
                self.isStarted = true

                let resumeGate = HLSContinuationResumeGate()
                self.listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        guard resumeGate.claim() else { return }
                        continuation.resume()
                    case let .failed(error):
                        guard resumeGate.claim() else { return }
                        continuation.resume(throwing: error)
                    case .cancelled:
                        break
                    default:
                        break
                    }
                }
                self.listener.newConnectionHandler = { [weak self] connection in
                    self?.handleConnection(connection)
                }
                self.listener.start(queue: self.queue)
            }
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        guard !isClosed else {
            connection.cancel()
            return
        }
        guard Self.allowsConnectionEndpoint(connection.endpoint) else {
            PlayerMetricsLog.logger.error(
                "directLiveHLSRejectedNonLoopback endpoint=\(String(describing: connection.endpoint), privacy: .private)"
            )
            connection.cancel()
            return
        }
        let identifier = ObjectIdentifier(connection)
        activeConnections[identifier] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed:
                self?.queue.async { [weak self] in
                    self?.activeConnections[identifier] = nil
                }
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveRequest(from: connection, accumulatedData: Data())
    }

    private func receiveRequest(from connection: NWConnection, accumulatedData: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            if error != nil {
                connection.cancel()
                return
            }

            var requestData = accumulatedData
            if let data {
                requestData.append(data)
            }

            if requestData.range(of: Data("\r\n\r\n".utf8)) != nil {
                self.respond(to: connection, requestData: requestData)
            } else if isComplete || requestData.count > 64 * 1024 {
                self.sendError(400, reason: "Bad Request", to: connection)
            } else {
                self.receiveRequest(from: connection, accumulatedData: requestData)
            }
        }
    }

    private func respond(to connection: NWConnection, requestData: Data) {
        let connectionID = ObjectIdentifier(connection)
        guard let request = HLSProxyRequest(data: requestData) else {
            sendError(400, reason: "Bad Request", to: connection)
            return
        }

        guard request.method == "GET" || request.method == "HEAD" else {
            sendError(405, reason: "Method Not Allowed", to: connection)
            return
        }

        if request.path == "/live.m3u8" {
            Task.detached(priority: .userInitiated) { [headers, sourcePlaylistURL, playlistURL, metricsID] in
                do {
                    let start = CACurrentMediaTime()
                    let (playlistData, routes) = try await Self.fetchRewrittenPlaylist(
                        sourcePlaylistURL,
                        headers: headers,
                        localPlaylistURL: playlistURL
                    )
                    self.queue.async {
                        guard self.isConnectionActive(connectionID) else { return }
                        self.segmentRoutes.merge(routes) { _, new in new }
                        self.sendData(
                            playlistData,
                            contentType: "application/vnd.apple.mpegurl",
                            request: request,
                            to: connection
                        )
                    }
                    PlayerMetricsLog.logger.info(
                        "directLiveHLSPlaylistProxy segments=\(routes.count, privacy: .public) elapsedMs=\(PlayerMetricsLog.elapsedMilliseconds(since: start), format: .fixed(precision: 1), privacy: .public)"
                    )
                    if let metricsID {
                        await PlayerMetricsLog.record(
                            .network,
                            metricsID: metricsID,
                            message: "live playlist \(routes.count) segments"
                        )
                    }
                } catch {
                    PlayerMetricsLog.logger.error(
                        "directLiveHLSPlaylistProxyFailed error=\(error.localizedDescription, privacy: .public)"
                    )
                    self.queue.async {
                        guard self.isConnectionActive(connectionID) else { return }
                        self.sendError(502, reason: "Bad Gateway", to: connection)
                    }
                }
            }
            return
        }

        guard let remoteURL = segmentRoutes[request.path] else {
            PlayerMetricsLog.logger.error(
                "directLiveHLSSegmentMiss path=\(request.path, privacy: .public)"
            )
            sendError(404, reason: "Not Found", to: connection)
            return
        }

        Task.detached(priority: .userInitiated) { [headers, metricsID] in
            do {
                let start = CACurrentMediaTime()
                let (data, contentType) = try await Self.fetchSegment(remoteURL, headers: headers)
                let responseData: Data
                let servedRange: HTTPByteRange?
                if let range = request.range?.clamped(toLength: Int64(data.count)),
                   let lowerBound = Int(exactly: range.start),
                   let upperBoundInclusive = Int(exactly: range.endInclusive),
                   lowerBound >= 0,
                   upperBoundInclusive < data.count {
                    responseData = data.subdata(in: lowerBound..<(upperBoundInclusive + 1))
                    servedRange = range
                } else {
                    responseData = data
                    servedRange = nil
                }
                self.queue.async {
                    guard self.isConnectionActive(connectionID) else { return }
                    self.sendData(
                        responseData,
                        contentType: contentType,
                        request: request,
                        totalLength: Int64(data.count),
                        servedRange: servedRange,
                        to: connection
                    )
                }
                PlayerMetricsLog.logger.info(
                    "directLiveHLSSegmentProxy bytes=\(data.count, privacy: .public) elapsedMs=\(PlayerMetricsLog.elapsedMilliseconds(since: start), format: .fixed(precision: 1), privacy: .public)"
                )
                if let metricsID {
                    await PlayerMetricsLog.record(
                        .network,
                        metricsID: metricsID,
                        message: "live segment \(data.count / 1024)KB"
                    )
                }
            } catch {
                PlayerMetricsLog.logger.error(
                    "directLiveHLSSegmentProxyFailed url=\(remoteURL.absoluteString, privacy: .private) error=\(error.localizedDescription, privacy: .public)"
                )
                self.queue.async {
                    guard self.isConnectionActive(connectionID) else { return }
                    self.sendError(502, reason: "Bad Gateway", to: connection)
                }
            }
        }
    }

    private static func fetchRewrittenPlaylist(
        _ url: URL,
        headers: [String: String],
        localPlaylistURL: URL
    ) async throws -> (Data, [String: URL]) {
        let data = try await fetchRemoteData(url, headers: headers, timeoutInterval: 8)
        guard let playlist = String(data: data, encoding: .utf8) else {
            throw PlayerEngineError.unsupportedMedia
        }

        var routes: [String: URL] = [:]
        var hasIndependentSegments = false
        var hasPlaylistType = false
        var hasEndList = false
        let lines = playlist.components(separatedBy: .newlines)
        var rewrittenLines = lines.compactMap { line -> String? in
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.hasPrefix("#EXT-X-INDEPENDENT-SEGMENTS") {
                hasIndependentSegments = true
            } else if trimmedLine.hasPrefix("#EXT-X-PLAYLIST-TYPE") {
                hasPlaylistType = true
            } else if trimmedLine.hasPrefix("#EXT-X-ENDLIST") {
                hasEndList = true
            }
            guard !trimmedLine.isEmpty, !trimmedLine.hasPrefix("#") else {
                return line
            }
            guard let remoteURL = URL(string: trimmedLine, relativeTo: url)?.absoluteURL else {
                return line
            }
            let routePath = liveSegmentPath(for: remoteURL)
            routes[routePath] = remoteURL
            return URL(string: routePath, relativeTo: localPlaylistURL)?.absoluteString ?? line
        }

        if !hasIndependentSegments,
           let insertionIndex = rewrittenLines.firstIndex(where: { !$0.hasPrefix("#EXTM3U") && !$0.hasPrefix("#EXT-X-VERSION") }) {
            rewrittenLines.insert("#EXT-X-INDEPENDENT-SEGMENTS", at: insertionIndex)
        }
        if !hasPlaylistType, !hasEndList,
           let insertionIndex = rewrittenLines.firstIndex(where: { $0.hasPrefix("#EXT-X-MEDIA-SEQUENCE") }) {
            rewrittenLines.insert("#EXT-X-PLAYLIST-TYPE:EVENT", at: insertionIndex)
        }
        if rewrittenLines.last?.isEmpty != true {
            rewrittenLines.append("")
        }
        return (Data(rewrittenLines.joined(separator: "\n").utf8), routes)
    }

    private static func fetchSegment(_ url: URL, headers: [String: String]) async throws -> (Data, String) {
        let data = try await fetchRemoteData(url, headers: headers, timeoutInterval: 12)
        let contentType = url.pathExtension.localizedCaseInsensitiveCompare("m4s") == .orderedSame
            ? "video/iso.segment"
            : "video/mp2t"
        return (data, contentType)
    }

    fileprivate nonisolated static func listenerParameters() throws -> NWParameters {
        try HLSLoopbackEndpointPolicy.tcpListenerParameters()
    }

    fileprivate nonisolated static func allowsConnectionEndpoint(_ endpoint: NWEndpoint) -> Bool {
        HLSLoopbackEndpointPolicy.allows(endpoint)
    }

    private static func fetchRemoteData(_ url: URL, headers: [String: String], timeoutInterval: TimeInterval) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = timeoutInterval
        request.networkServiceType = .video
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await BiliNetworkRetry.data(
            sessionProvider: { BiliPlaybackNetworkSessionPool.shared.playbackDataSession() },
            request: request,
            policy: .playbackShortResource
        )
        if let response = response as? HTTPURLResponse,
           !(200...299).contains(response.statusCode) {
            throw PlayerEngineError.unsupportedMedia
        }
        return data
    }

    private static func liveSegmentPath(for url: URL) -> String {
        let filename = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        if !filename.isEmpty,
           let encodedFilename = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
            return "/live-segment/\(encodedFilename)"
        }
        return "/live-segment/\(abs(url.absoluteString.hashValue)).ts"
    }

    private func sendData(
        _ data: Data,
        contentType: String,
        request: HLSProxyRequest,
        totalLength: Int64? = nil,
        servedRange: HTTPByteRange? = nil,
        to connection: NWConnection,
        closesConnection: Bool = true
    ) {
        let body = request.method == "HEAD" ? Data() : data
        var headers = [
            "Content-Type": contentType,
            "Content-Length": "\(data.count)",
            "Accept-Ranges": "bytes",
            "Cache-Control": request.path.hasSuffix(".m3u8") ? "no-cache" : "public, max-age=15",
            "Connection": closesConnection ? "close" : "keep-alive"
        ]
        let statusLine: String
        if let servedRange, let totalLength {
            statusLine = "HTTP/1.1 206 Partial Content"
            headers["Content-Range"] = "bytes \(servedRange.start)-\(servedRange.endInclusive)/\(totalLength)"
        } else {
            statusLine = "HTTP/1.1 200 OK"
        }
        sendResponse(statusLine: statusLine, headers: headers, body: body, to: connection, closesConnection: closesConnection)
    }

    private func sendError(_ statusCode: Int, reason: String, to connection: NWConnection) {
        let body = Data(reason.utf8)
        sendResponse(
            statusLine: "HTTP/1.1 \(statusCode) \(reason)",
            headers: [
                "Content-Type": "text/plain; charset=utf-8",
                "Content-Length": "\(body.count)",
                "Connection": "close"
            ],
            body: body,
            to: connection
        )
    }

    private func sendResponse(
        statusLine: String,
        headers: [String: String],
        body: Data,
        to connection: NWConnection,
        closesConnection: Bool = true
    ) {
        let headerText = ([statusLine] + headers.map { "\($0.key): \($0.value)" })
            .joined(separator: "\r\n") + "\r\n\r\n"
        var response = Data(headerText.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { [weak self] _ in
            guard !closesConnection, let self else {
                connection.cancel()
                return
            }
            self.receiveRequest(from: connection, accumulatedData: Data())
        })
    }

    private func isConnectionActive(_ identifier: ObjectIdentifier) -> Bool {
        !isClosed && activeConnections[identifier] != nil
    }
}

#if DEBUG
enum LocalLiveHLSProxyTesting {
    nonisolated static func listenerRequiredLocalEndpoint() throws -> NWEndpoint? {
        try LocalLiveHLSProxy.listenerParameters().requiredLocalEndpoint
    }

    nonisolated static func allowsConnectionEndpoint(_ endpoint: NWEndpoint) -> Bool {
        LocalLiveHLSProxy.allowsConnectionEndpoint(endpoint)
    }
}
#endif

private actor HLSRenditionCache {
    static let shared = HLSRenditionCache()

    enum State: String, Sendable {
        case hit
        case disk
        case pending
        case miss
    }

    private let ttl: TimeInterval = 8 * 60
    private let maxCount = 48
    private let maxDiskCount = 96
    private let fileManager = FileManager.default
    private let rootURL: URL
    private var cache: [String: Entry] = [:]
    private let pendingJoinTimeoutNanoseconds: UInt64 = 220_000_000
    private var pendingBuilds: [String: PendingBuild] = [:]
    private var storeCountSinceDiskTrim = 0
    private var diskTrimTask: Task<Void, Never>?

    init() {
        rootURL = fileManager
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HLSRenditionCache", isDirectory: true)
    }

    func cachedOrBuild(
        for key: String,
        builder: @escaping @Sendable () async throws -> HLSRendition
    ) async throws -> (rendition: HLSRendition, state: State) {
        trimExpired()
        if let entry = cache[key] {
            cache[key] = Entry(rendition: entry.rendition, date: Date())
            return (entry.rendition, .hit)
        }
        if let entry = loadPersistedEntry(for: key) {
            cache[key] = entry
            trimIfNeeded()
            return (entry.rendition, .disk)
        }
        if let pendingBuild = pendingBuilds[key] {
            do {
                let rendition = try await HLSCachePendingWaiter.value(
                    of: pendingBuild.task,
                    timeout: pendingJoinTimeoutNanoseconds
                )
                return (rendition, .pending)
            } catch HLSCachePendingWaiter.Timeout.timedOut {
                let rendition = try await pendingBuild.task.value
                return (rendition, .pending)
            } catch {
                if pendingBuilds[key]?.id == pendingBuild.id {
                    pendingBuilds[key] = nil
                }
                throw error
            }
        }

        let pendingBuild = PendingBuild(task: Task.detached(priority: .userInitiated) {
            try await builder()
        })
        pendingBuilds[key] = pendingBuild
        do {
            let rendition = try await pendingBuild.task.value
            pendingBuilds[key] = nil
            cache[key] = Entry(rendition: rendition, date: Date())
            storePersistedEntry(Entry(rendition: rendition, date: Date()), for: key)
            trimIfNeeded()
            return (rendition, .miss)
        } catch {
            pendingBuilds[key] = nil
            throw error
        }
    }

    func removeAll() {
        pendingBuilds.values.forEach { $0.task.cancel() }
        pendingBuilds.removeAll()
        cache.removeAll()
        try? fileManager.removeItem(at: rootURL)
    }

    func removeAll(containingAny mediaURLs: Set<String>) {
        guard !mediaURLs.isEmpty else { return }
        let keys = Set(cache.keys).union(pendingBuilds.keys).filter {
            Self.key($0, containsAny: mediaURLs)
        }
        for key in keys {
            pendingBuilds.removeValue(forKey: key)?.task.cancel()
            cache[key] = nil
            try? fileManager.removeItem(at: cacheFileURL(for: key))
        }
        guard let files = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil
        ) else { return }
        for fileURL in files {
            guard let data = try? Data(contentsOf: fileURL),
                  let entry = try? JSONDecoder().decode(PersistedEntry.self, from: data)
            else { continue }
            let sourceURLs = Set([entry.rendition.sourceURL] + entry.rendition.fallbackSourceURLs)
            if !sourceURLs.isDisjoint(with: mediaURLs) {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }

    private nonisolated static func key(_ key: String, containsAny mediaURLs: Set<String>) -> Bool {
        mediaURLs.contains { key.contains($0) }
    }

    private func trimExpired() {
        let expiry = Date().addingTimeInterval(-ttl)
        cache = cache.filter { $0.value.date >= expiry }
    }

    private func trimIfNeeded() {
        trimExpired()
        guard cache.count > maxCount else { return }
        let keptKeys = Set(
            cache
                .sorted { $0.value.date > $1.value.date }
                .prefix(maxCount)
                .map(\.key)
        )
        cache = cache.filter { keptKeys.contains($0.key) }
    }

    private struct Entry {
        let rendition: HLSRendition
        let date: Date
    }

    private func loadPersistedEntry(for key: String) -> Entry? {
        let fileURL = cacheFileURL(for: key)
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let persisted = try? JSONDecoder().decode(PersistedEntry.self, from: data)
        else { return nil }
        guard persisted.date >= Date().addingTimeInterval(-ttl),
              let rendition = persisted.rendition.makeRendition()
        else {
            try? fileManager.removeItem(at: fileURL)
            return nil
        }
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
        return Entry(rendition: rendition, date: persisted.date)
    }

    private func storePersistedEntry(_ entry: Entry, for key: String) {
        guard let persisted = PersistedEntry(entry: entry) else { return }
        let fileURL = cacheFileURL(for: key)
        Task.detached(priority: .utility) {
            do {
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let data = try JSONEncoder().encode(persisted)
                try data.write(to: fileURL, options: .atomic)
            } catch {}
        }
        scheduleDiskTrimIfNeeded()
    }

    private func scheduleDiskTrimIfNeeded() {
        storeCountSinceDiskTrim += 1
        guard diskTrimTask == nil, storeCountSinceDiskTrim >= 16 else { return }
        let actor = self
        diskTrimTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await actor.trimDiskIfNeeded()
            await actor.completeDiskTrim()
        }
    }

    private func completeDiskTrim() {
        diskTrimTask = nil
        storeCountSinceDiskTrim = 0
    }

    private func trimDiskIfNeeded() {
        guard let files = try? fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else { return }
        let expiry = Date().addingTimeInterval(-ttl)
        let entries = files.compactMap { url -> (url: URL, date: Date, size: Int64)? in
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else { return nil }
            return (url, values.contentModificationDate ?? .distantPast, Int64(values.fileSize ?? 0))
        }
        for entry in entries where entry.date < expiry {
            try? fileManager.removeItem(at: entry.url)
        }
        let retained = entries.filter { $0.date >= expiry }
        guard retained.count > maxDiskCount else { return }
        for entry in retained.sorted(by: { $0.date < $1.date }).prefix(retained.count - maxDiskCount) {
            try? fileManager.removeItem(at: entry.url)
        }
    }

    private func cacheFileURL(for key: String) -> URL {
        rootURL.appendingPathComponent("\(Self.stableCacheHash(key)).json")
    }

    private nonisolated static func stableCacheHash(_ string: String) -> String {
        let basis: UInt64 = 14_695_981_039_346_656_037
        let prime: UInt64 = 1_099_511_628_211
        let value = string.utf8.reduce(basis) { partial, byte in
            (partial ^ UInt64(byte)) &* prime
        }
        return String(value, radix: 16)
    }

    private struct PersistedEntry: Codable {
        let date: Date
        let rendition: PersistedRendition

        init?(entry: Entry) {
            guard let rendition = PersistedRendition(rendition: entry.rendition) else { return nil }
            self.date = entry.date
            self.rendition = rendition
        }
    }

    private struct PersistedRendition: Codable {
        let sourceURL: String
        let fallbackSourceURLs: [String]
        let mediaType: String
        let quality: Int?
        let initialization: PersistedRange
        let initializationData: Data?
        let references: [PersistedReference]
        let targetDuration: TimeInterval
        let bandwidth: Int
        let codec: String
        let mediaTimeOffset: TimeInterval
        let baseMediaDecodeTimeOffsetTicks: UInt64
        let dynamicRange: String
        let dolbyVisionConfiguration: PersistedDolbyVisionConfiguration?
        let dolbyVisionRenderingPolicy: String?
        let videoColorInformation: VideoColorInformation?
        let hlsBaseLayerCodec: String?
        let dimensionsWidth: Double?
        let dimensionsHeight: Double?
        let frameRate: Double?

        init?(rendition: HLSRendition) {
            self.sourceURL = rendition.sourceURL.absoluteString
            self.fallbackSourceURLs = rendition.fallbackSourceURLs.map(\.absoluteString)
            self.mediaType = rendition.mediaType.logLabel
            self.quality = rendition.quality
            self.initialization = PersistedRange(range: rendition.initialization)
            self.initializationData = rendition.initializationData
            self.references = rendition.references.map(PersistedReference.init(reference:))
            self.targetDuration = rendition.targetDuration
            self.bandwidth = rendition.bandwidth
            self.codec = rendition.codec
            self.mediaTimeOffset = rendition.mediaTimeOffset
            self.baseMediaDecodeTimeOffsetTicks = rendition.baseMediaDecodeTimeOffsetTicks
            self.dynamicRange = rendition.dynamicRange.rawValue
            self.dolbyVisionConfiguration = rendition.dolbyVisionConfiguration.map(PersistedDolbyVisionConfiguration.init(configuration:))
            self.dolbyVisionRenderingPolicy = rendition.dolbyVisionRenderingPolicy.rawValue
            self.videoColorInformation = rendition.videoColorInformation
            self.hlsBaseLayerCodec = rendition.hlsBaseLayerCodec
            self.dimensionsWidth = rendition.dimensions.map { Double($0.width) }
            self.dimensionsHeight = rendition.dimensions.map { Double($0.height) }
            self.frameRate = rendition.frameRate
        }

        func makeRendition() -> HLSRendition? {
            guard let sourceURL = URL(string: sourceURL) else { return nil }
            let resolvedMediaType: HLSBridgeTrack.MediaType = mediaType == "audio" ? .audio : .video
            let dimensions: CGSize?
            if let dimensionsWidth, let dimensionsHeight, dimensionsWidth > 0, dimensionsHeight > 0 {
                dimensions = CGSize(width: dimensionsWidth, height: dimensionsHeight)
            } else {
                dimensions = nil
            }
            return HLSRendition(
                sourceURL: sourceURL,
                fallbackSourceURLs: fallbackSourceURLs.compactMap(URL.init(string:)),
                mediaType: resolvedMediaType,
                quality: quality,
                initialization: initialization.makeRange(),
                initializationData: initializationData,
                references: references.map(\.makeReference),
                targetDuration: targetDuration,
                bandwidth: bandwidth,
                codec: codec,
                mediaTimeOffset: mediaTimeOffset,
                baseMediaDecodeTimeOffsetTicks: baseMediaDecodeTimeOffsetTicks,
                dynamicRange: BiliVideoDynamicRange(rawValue: dynamicRange) ?? .sdr,
                dolbyVisionConfiguration: dolbyVisionConfiguration?.makeConfiguration(),
                dolbyVisionRenderingPolicy: dolbyVisionRenderingPolicy
                    .flatMap(DolbyVisionRenderingPolicy.init(rawValue:))?
                    .playablePolicy ?? .compatibleHLG,
                videoColorInformation: videoColorInformation,
                hlsBaseLayerCodec: hlsBaseLayerCodec,
                dimensions: dimensions,
                frameRate: frameRate
            )
        }
    }

    private struct PersistedDolbyVisionConfiguration: Codable {
        let boxType: String
        let profile: Int
        let level: Int
        let rpuPresent: Bool
        let enhancementLayerPresent: Bool
        let baseLayerPresent: Bool
        let baseLayerSignalCompatibilityID: Int

        init(configuration: DolbyVisionCodecConfiguration) {
            self.boxType = configuration.boxType
            self.profile = configuration.profile
            self.level = configuration.level
            self.rpuPresent = configuration.rpuPresent
            self.enhancementLayerPresent = configuration.enhancementLayerPresent
            self.baseLayerPresent = configuration.baseLayerPresent
            self.baseLayerSignalCompatibilityID = configuration.baseLayerSignalCompatibilityID
        }

        func makeConfiguration() -> DolbyVisionCodecConfiguration {
            DolbyVisionCodecConfiguration(
                boxType: boxType,
                profile: profile,
                level: level,
                rpuPresent: rpuPresent,
                enhancementLayerPresent: enhancementLayerPresent,
                baseLayerPresent: baseLayerPresent,
                baseLayerSignalCompatibilityID: baseLayerSignalCompatibilityID
            )
        }
    }

    private struct PersistedRange: Codable {
        let start: Int64
        let endInclusive: Int64

        init(range: HTTPByteRange) {
            self.start = range.start
            self.endInclusive = range.endInclusive
        }

        func makeRange() -> HTTPByteRange {
            HTTPByteRange(start: start, endInclusive: endInclusive)
        }
    }

    private struct PersistedReference: Codable {
        let range: PersistedRange
        let duration: TimeInterval
        let startTime: TimeInterval
        let startTimeTicks: UInt64
        let timescale: UInt32

        init(reference: SIDXParser.Reference) {
            self.range = PersistedRange(range: reference.range)
            self.duration = reference.duration
            self.startTime = reference.startTime
            self.startTimeTicks = reference.startTimeTicks
            self.timescale = reference.timescale
        }

        var makeReference: SIDXParser.Reference {
            SIDXParser.Reference(
                range: range.makeRange(),
                duration: duration,
                startTime: startTime,
                startTimeTicks: startTimeTicks,
                timescale: timescale
            )
        }
    }

    private struct PendingBuild {
        let id = UUID()
        let task: Task<HLSRendition, Error>
    }
}

nonisolated private enum HLSCachePendingWaiter {
    enum Timeout: Error {
        case timedOut
    }

    static func value<T: Sendable>(
        of task: Task<T, Error>,
        timeout: UInt64
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await task.value
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeout)
                throw Timeout.timedOut
            }
            guard let value = try await group.next() else {
                throw Timeout.timedOut
            }
            group.cancelAll()
            return value
        }
    }
}

private actor HLSBridgeRoutePlanCache {
    static let shared = HLSBridgeRoutePlanCache()

    enum State: String, Sendable {
        case hit
        case pending
        case miss
        case skippedPending
    }

    private let ttl: TimeInterval = 3 * 60
    private let maxCount = 12
    private let pendingJoinTimeoutNanoseconds: UInt64 = 220_000_000
    private var cache: [String: Entry] = [:]
    private var pendingBuilds: [String: PendingBuild] = [:]

    func cachedOrBuild(
        for key: String,
        builder: @escaping @Sendable () async throws -> HLSBridgeRoutePlan
    ) async throws -> (plan: HLSBridgeRoutePlan, state: State) {
        trimExpired()
        if let entry = cache[key] {
            cache[key] = Entry(plan: entry.plan, date: Date())
            return (entry.plan, .hit)
        }
        if let pendingBuild = pendingBuilds[key] {
            do {
                let plan = try await HLSCachePendingWaiter.value(
                    of: pendingBuild.task,
                    timeout: pendingJoinTimeoutNanoseconds
                )
                return (plan, .pending)
            } catch HLSCachePendingWaiter.Timeout.timedOut {
                let plan = try await pendingBuild.task.value
                return (plan, .pending)
            } catch {
                if pendingBuilds[key]?.id == pendingBuild.id {
                    pendingBuilds[key] = nil
                }
                throw error
            }
        }

        let pendingBuild = PendingBuild(task: Task.detached(priority: .userInitiated) {
            try await builder()
        })
        pendingBuilds[key] = pendingBuild
        do {
            let plan = try await pendingBuild.task.value
            pendingBuilds[key] = nil
            cache[key] = Entry(plan: plan, date: Date())
            trimIfNeeded()
            return (plan, .miss)
        } catch {
            pendingBuilds[key] = nil
            throw error
        }
    }

    func prebuild(
        for key: String,
        builder: @escaping @Sendable () async throws -> HLSBridgeRoutePlan
    ) async throws -> State {
        trimExpired()
        if let entry = cache[key] {
            cache[key] = Entry(plan: entry.plan, date: Date())
            return .hit
        }
        guard pendingBuilds[key] == nil else {
            return .skippedPending
        }

        let pendingBuild = PendingBuild(task: Task.detached(priority: .utility) {
            try await builder()
        })
        pendingBuilds[key] = pendingBuild
        do {
            let plan = try await pendingBuild.task.value
            if pendingBuilds[key]?.id == pendingBuild.id {
                pendingBuilds[key] = nil
            }
            cache[key] = Entry(plan: plan, date: Date())
            trimIfNeeded()
            return .miss
        } catch {
            if pendingBuilds[key]?.id == pendingBuild.id {
                pendingBuilds[key] = nil
            }
            throw error
        }
    }

    func removeAll() {
        pendingBuilds.values.forEach { $0.task.cancel() }
        pendingBuilds.removeAll()
        cache.removeAll()
    }

    func removeAll(containingAny mediaURLs: Set<String>) {
        guard !mediaURLs.isEmpty else { return }
        let keys = Set(cache.keys).union(pendingBuilds.keys).filter {
            Self.key($0, containsAny: mediaURLs)
        }
        for key in keys {
            pendingBuilds.removeValue(forKey: key)?.task.cancel()
            cache[key] = nil
        }
    }

    private nonisolated static func key(_ key: String, containsAny mediaURLs: Set<String>) -> Bool {
        mediaURLs.contains { key.contains($0) }
    }

    private func trimExpired() {
        let expiry = Date().addingTimeInterval(-ttl)
        cache = cache.filter { $0.value.date >= expiry }
    }

    private func trimIfNeeded() {
        trimExpired()
        guard cache.count > maxCount else { return }
        let keptKeys = Set(
            cache
                .sorted { $0.value.date > $1.value.date }
                .prefix(maxCount)
                .map(\.key)
        )
        cache = cache.filter { keptKeys.contains($0.key) }
    }

    private struct Entry {
        let plan: HLSBridgeRoutePlan
        let date: Date
    }

    private struct PendingBuild {
        let id = UUID()
        let task: Task<HLSBridgeRoutePlan, Error>
    }
}

private actor LocalHLSBridgeInstanceCache {
    static let shared = LocalHLSBridgeInstanceCache()

    enum State: String, Sendable {
        case hit
        case pending
        case miss
    }

    private let ttl: TimeInterval = 45
    private let maxCount = 3
    private var cache: [String: Entry] = [:]
    private var pendingBuilds: [String: PendingBuild] = [:]

    func cachedOrBuild(
        for key: String,
        storesForReuse: Bool,
        builder: @escaping @Sendable () async throws -> LocalHLSBridge
    ) async throws -> (bridge: LocalHLSBridge, state: State) {
        trimExpired()

        if storesForReuse {
            if let entry = cache[key] {
                cache[key] = Entry(bridge: entry.bridge, date: Date())
                return (entry.bridge, .hit)
            }

            if let pendingBuild = pendingBuilds[key] {
                do {
                    let bridge = try await pendingBuild.task.value
                    if pendingBuilds[key]?.id == pendingBuild.id {
                        pendingBuilds[key] = nil
                        if pendingBuild.storesForReuse {
                            cache[key] = Entry(bridge: bridge, date: Date())
                            trimIfNeeded()
                        }
                    }
                    return (bridge, .pending)
                } catch {
                    if pendingBuilds[key]?.id == pendingBuild.id {
                        pendingBuilds[key] = nil
                    }
                    throw error
                }
            }

            let pendingBuild = PendingBuild(
                storesForReuse: true,
                task: Task.detached(priority: .userInitiated) {
                    try await builder()
                }
            )
            pendingBuilds[key] = pendingBuild
            do {
                let bridge = try await pendingBuild.task.value
                if pendingBuilds[key]?.id == pendingBuild.id {
                    pendingBuilds[key] = nil
                    cache[key] = Entry(bridge: bridge, date: Date())
                    trimIfNeeded()
                }
                return (bridge, .miss)
            } catch {
                if pendingBuilds[key]?.id == pendingBuild.id {
                    pendingBuilds[key] = nil
                }
                throw error
            }
        }

        if let entry = cache.removeValue(forKey: key) {
            return (entry.bridge, .hit)
        }

        if let pendingBuild = pendingBuilds[key] {
            if pendingBuild.storesForReuse {
                pendingBuilds[key] = nil
            }
            do {
                let bridge = try await pendingBuild.task.value
                if !pendingBuild.storesForReuse,
                   pendingBuilds[key]?.id == pendingBuild.id {
                    pendingBuilds[key] = nil
                }
                return (bridge, .pending)
            } catch {
                if !pendingBuild.storesForReuse,
                   pendingBuilds[key]?.id == pendingBuild.id {
                    pendingBuilds[key] = nil
                }
                throw error
            }
        }

        let pendingBuild = PendingBuild(
            storesForReuse: false,
            task: Task.detached(priority: .userInitiated) {
                try await builder()
            }
        )
        pendingBuilds[key] = pendingBuild
        do {
            let bridge = try await pendingBuild.task.value
            if pendingBuilds[key]?.id == pendingBuild.id {
                pendingBuilds[key] = nil
            }
            return (bridge, .miss)
        } catch {
            if pendingBuilds[key]?.id == pendingBuild.id {
                pendingBuilds[key] = nil
            }
            throw error
        }
    }

    func removeAll() {
        pendingBuilds.values.forEach { $0.task.cancel() }
        pendingBuilds.removeAll()
        cache.values.forEach { $0.bridge.stop() }
        cache.removeAll()
    }

    func removeAll(containingAny mediaURLs: Set<String>) {
        guard !mediaURLs.isEmpty else { return }
        let keys = Set(cache.keys).union(pendingBuilds.keys).filter {
            Self.key($0, containsAny: mediaURLs)
        }
        for key in keys {
            pendingBuilds.removeValue(forKey: key)?.task.cancel()
            cache.removeValue(forKey: key)?.bridge.stop()
        }
    }

    private nonisolated static func key(_ key: String, containsAny mediaURLs: Set<String>) -> Bool {
        mediaURLs.contains { key.contains($0) }
    }

    private func trimExpired() {
        let expiry = Date().addingTimeInterval(-ttl)
        let expiredKeys = cache
            .filter { $0.value.date < expiry }
            .map(\.key)
        for key in expiredKeys {
            cache.removeValue(forKey: key)?.bridge.stop()
        }
    }

    private func trimIfNeeded() {
        trimExpired()
        guard cache.count > maxCount else { return }
        let keptKeys = Set(
            cache
                .sorted { $0.value.date > $1.value.date }
                .prefix(maxCount)
                .map(\.key)
        )
        let removedKeys = cache.keys.filter { !keptKeys.contains($0) }
        for key in removedKeys {
            cache.removeValue(forKey: key)?.bridge.stop()
        }
    }

    private struct Entry {
        let bridge: LocalHLSBridge
        let date: Date
    }

    private struct PendingBuild {
        let id = UUID()
        let storesForReuse: Bool
        let task: Task<LocalHLSBridge, Error>
    }
}

private actor HLSSourcePreferenceCache {
    static let shared = HLSSourcePreferenceCache()

    private let ttl: TimeInterval = 24 * 60 * 60
    private let sessionAvoidanceTTL: TimeInterval = 10 * 60
    private let maxCount = 256
    private let maxHostScoreCount = 192
    private let fileManager = FileManager.default
    private let storeURL: URL
    private let hostScoreStoreURL: URL
    private var entries: [String: Entry] = [:]
    private var hostScores: [String: HostScore] = [:]
    private var sessionAvoidance: [String: SessionAvoidance] = [:]
    private var hasLoadedStore = false
    private var persistTask: Task<Void, Never>?
    private var persistDirty = false

    init() {
        storeURL = fileManager
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HLSSourcePreferenceCache.json")
        hostScoreStoreURL = fileManager
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HLSSourceScores.json")
    }

    func preferredURLs(for urls: [URL]) -> [URL] {
        loadStoreIfNeeded()
        trimExpired()
        guard urls.count > 1 else { return urls }
        let scoredURLs = urls.enumerated().map { index, url -> (index: Int, url: URL, score: Double?) in
            guard let host = url.host, let hostScore = hostScores[host] else {
                return (index, url, nil)
            }
            return (index, url, hostScore.rankScore)
        }
        let urlsWithScores = scoredURLs.filter { $0.score != nil }
        if !urlsWithScores.isEmpty {
            let ordered = scoredURLs
                .sorted { lhs, rhs in
                    let leftScore = lhs.score ?? HostScore.unmeasuredRankScore
                    let rightScore = rhs.score ?? HostScore.unmeasuredRankScore
                    if abs(leftScore - rightScore) > 0.01 {
                        return leftScore < rightScore
                    }
                    if (lhs.score == nil) != (rhs.score == nil) {
                        return lhs.index < rhs.index
                    }
                    return lhs.index < rhs.index
                }
                .map(\.url)
            return applyingCellularBiliTrafficCompatibility(to: demoteSessionAvoidedHosts(ordered))
        }
        guard let preferredURL = preferredURL(for: urls),
              let preferredIndex = urls.firstIndex(of: preferredURL),
              preferredIndex > 0
        else {
            return applyingCellularBiliTrafficCompatibility(to: demoteSessionAvoidedHosts(urls))
        }
        var reordered = urls
        let preferred = reordered.remove(at: preferredIndex)
        reordered.insert(preferred, at: 0)
        return applyingCellularBiliTrafficCompatibility(to: demoteSessionAvoidedHosts(reordered))
    }

    private func applyingCellularBiliTrafficCompatibility(to urls: [URL]) -> [URL] {
        guard CellularBiliTrafficCompatibilityExperiment.currentState.isActive else { return urls }

        let availableURLs = urls.filter { !isSessionAvoided($0.host) }
        let avoidedURLs = urls.filter { isSessionAvoided($0.host) }
        return CellularBiliTrafficCompatibilityExperiment.prioritizedURLsForCurrentEnvironment(availableURLs)
            + avoidedURLs
    }

    func recordPreferredURL(_ url: URL, for urls: [URL]) {
        loadStoreIfNeeded()
        guard urls.contains(url) else { return }
        let now = Date()
        entries[exactCacheKey(for: urls)] = Entry(preferredURLString: url.absoluteString, date: now)
        if let hostKey = hostCacheKey(for: urls) {
            entries[hostKey] = Entry(preferredURLString: url.absoluteString, date: now)
        }
        trimExpired()
        trimIfNeeded()
        persistDirty = true
        schedulePersist()
    }

    func recordResult(
        url: URL,
        for urls: [URL],
        elapsedMilliseconds: Double,
        bytes: Int64,
        succeeded: Bool,
        failureReason: String? = nil,
        failurePenaltyMultiplier: Int = 1,
        metricsID: String? = nil,
        title: String? = nil
    ) {
        loadStoreIfNeeded()
        guard urls.contains(url), let host = url.host else { return }
        let now = Date()
        var score = hostScores[host] ?? HostScore()
        score.record(
            elapsedMilliseconds: elapsedMilliseconds,
            bytes: bytes,
            succeeded: succeeded,
            date: now
        )
        PlaybackURLPreferenceStore.shared.record(
            url: url,
            elapsedMilliseconds: elapsedMilliseconds,
            bytes: bytes,
            succeeded: succeeded
        )
        hostScores[host] = score
        if succeeded {
            clearSessionAvoidance(for: host)
            entries[exactCacheKey(for: urls)] = Entry(preferredURLString: url.absoluteString, date: now)
            if let hostKey = hostCacheKey(for: urls) {
                entries[hostKey] = Entry(preferredURLString: url.absoluteString, date: now)
            }
        } else {
            markSessionAvoidedHost(
                host,
                reason: failureReason ?? "range-failed",
                penaltyMultiplier: max(failurePenaltyMultiplier, 1),
                metricsID: metricsID,
                title: title
            )
        }
        trimExpired()
        trimIfNeeded()
        trimHostScoresIfNeeded()
        persistDirty = true
        schedulePersist()
    }

    func recordFailure(
        url: URL,
        for urls: [URL],
        elapsedMilliseconds: Double,
        error: Error,
        metricsID: String? = nil,
        title: String? = nil
    ) {
        guard HLSBridgeRemoteFailure.shouldRecordSourceFailure(error) else { return }
        recordResult(
            url: url,
            for: urls,
            elapsedMilliseconds: elapsedMilliseconds,
            bytes: 0,
            succeeded: false,
            failureReason: HLSBridgeRemoteFailure.sourceAvoidanceReason(for: error),
            failurePenaltyMultiplier: HLSBridgeRemoteFailure.sourceAvoidancePenaltyMultiplier(for: error),
            metricsID: metricsID,
            title: title
        )
    }

    func recordSessionAvoidance(
        host: String?,
        reason: String,
        metricsID: String?,
        title: String? = nil
    ) {
        loadStoreIfNeeded()
        guard let host else { return }
        markSessionAvoidedHost(
            host,
            reason: reason,
            penaltyMultiplier: 2,
            metricsID: metricsID,
            title: title
        )
    }

    func diagnostics(for urls: [URL]) -> [HLSBridgeSourceDiagnosticsSnapshot] {
        loadStoreIfNeeded()
        trimExpired()
        let orderedURLs = preferredURLs(for: urls.removingDuplicates())
        let now = Date()
        var seenHosts = Set<String>()
        return orderedURLs.enumerated().compactMap { index, url -> HLSBridgeSourceDiagnosticsSnapshot? in
            guard let host = normalizedHost(url.host),
                  seenHosts.insert(host).inserted
            else { return nil }
            let score = hostScores[host] ?? url.host.flatMap { hostScores[$0] }
            let avoidance = sessionAvoidance[host]
            let isAvoided = avoidance.map { $0.expiresAt > now } ?? false
            return HLSBridgeSourceDiagnosticsSnapshot(
                host: host,
                order: index + 1,
                averageMilliseconds: score.map { Int($0.averageMilliseconds.rounded()) },
                averageKilobytesPerSecond: Int((score?.averageKilobytesPerSecond ?? 0).rounded()),
                successCount: score?.successCount ?? 0,
                failureCount: score?.failureCount ?? 0,
                isSessionAvoided: isAvoided,
                avoidanceReason: isAvoided ? avoidance?.reason : nil,
                avoidanceExpiresAt: isAvoided ? avoidance?.expiresAt : nil
            )
        }
    }

    private func preferredURL(for urls: [URL]) -> URL? {
        let keys = [exactCacheKey(for: urls), hostCacheKey(for: urls)]
            .compactMap { $0 }
        for key in keys {
            guard let entry = entries[key],
                  let url = URL(string: entry.preferredURLString)
            else { continue }
            if urls.contains(url) {
                return url
            }
            if let host = url.host,
               let matchingURL = urls.first(where: { $0.host == host }) {
                return matchingURL
            }
        }
        return nil
    }

    private func exactCacheKey(for urls: [URL]) -> String {
        "exact|" + urls
            .map(\.absoluteString)
            .joined(separator: "|")
    }

    private func hostCacheKey(for urls: [URL]) -> String? {
        let hosts = urls.compactMap(\.host)
        guard hosts.count > 1 else { return nil }
        return "host|" + hosts.joined(separator: "|")
    }

    private func demoteSessionAvoidedHosts(_ urls: [URL]) -> [URL] {
        trimSessionAvoidance()
        guard !sessionAvoidance.isEmpty else { return urls }
        var preferred: [URL] = []
        var avoided: [URL] = []
        for url in urls {
            if isSessionAvoided(url.host) {
                avoided.append(url)
            } else {
                preferred.append(url)
            }
        }
        guard !preferred.isEmpty else { return urls }
        return preferred + avoided
    }

    private func markSessionAvoidedHost(
        _ host: String,
        reason: String,
        penaltyMultiplier: Int,
        metricsID: String?,
        title: String?
    ) {
        guard let key = normalizedHost(host) else { return }
        trimSessionAvoidance()
        let existing = sessionAvoidance[key]
        let failureCount = min((existing?.failureCount ?? 0) + max(penaltyMultiplier, 1), 8)
        let penaltySeconds = min(sessionAvoidanceTTL, 90 + TimeInterval(failureCount) * 75)
        let expiresAt = Date().addingTimeInterval(penaltySeconds)
        sessionAvoidance[key] = SessionAvoidance(
            reason: reason,
            failureCount: failureCount,
            expiresAt: expiresAt
        )
        PlayerMetricsLog.logger.info(
            "hlsSourceSessionAvoid host=\(key, privacy: .public) reason=\(reason, privacy: .public) failures=\(failureCount, privacy: .public) ttl=\(Int(penaltySeconds), privacy: .public)s"
        )
        if let metricsID {
            Task { @MainActor in
                PlayerMetricsLog.record(
                    .network,
                    metricsID: metricsID,
                    title: title,
                    message: "sessionAvoid host=\(key) reason=\(reason) failures=\(failureCount) ttl=\(Int(penaltySeconds))s"
                )
            }
        }
    }

    private func clearSessionAvoidance(for host: String) {
        guard let key = normalizedHost(host) else { return }
        sessionAvoidance[key] = nil
    }

    private func isSessionAvoided(_ host: String?) -> Bool {
        guard let key = normalizedHost(host) else { return false }
        guard let avoidance = sessionAvoidance[key] else { return false }
        return avoidance.expiresAt > Date()
    }

    private func normalizedHost(_ host: String?) -> String? {
        let trimmed = host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func trimSessionAvoidance() {
        let now = Date()
        sessionAvoidance = sessionAvoidance.filter { $0.value.expiresAt > now }
    }

    private func trimExpired() {
        let expiry = Date().addingTimeInterval(-ttl)
        entries = entries.filter { $0.value.date >= expiry }
        hostScores = hostScores.filter { $0.value.date >= expiry }
        trimSessionAvoidance()
    }

    private func trimIfNeeded() {
        guard entries.count > maxCount else { return }
        let keptKeys = Set(
            entries
                .sorted { $0.value.date > $1.value.date }
                .prefix(maxCount)
                .map(\.key)
        )
        entries = entries.filter { keptKeys.contains($0.key) }
    }

    private func trimHostScoresIfNeeded() {
        guard hostScores.count > maxHostScoreCount else { return }
        let keptKeys = Set(
            hostScores
                .sorted { $0.value.date > $1.value.date }
                .prefix(maxHostScoreCount)
                .map(\.key)
        )
        hostScores = hostScores.filter { keptKeys.contains($0.key) }
    }

    private func loadStoreIfNeeded() {
        guard !hasLoadedStore else { return }
        hasLoadedStore = true
        if let data = try? Data(contentsOf: storeURL),
           let persisted = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = persisted
        }
        if let data = try? Data(contentsOf: hostScoreStoreURL),
           let persistedScores = try? JSONDecoder().decode([String: HostScore].self, from: data) {
            hostScores = persistedScores
        }
        trimExpired()
        trimIfNeeded()
        trimHostScoresIfNeeded()
    }

    private func schedulePersist() {
        guard persistTask == nil else { return }
        let actor = self
        let storeURL = storeURL
        let hostScoreStoreURL = hostScoreStoreURL
        persistTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 700_000_000)
            let entries = await actor.persistenceSnapshotForWrite()
            Self.writePersistedEntries(entries.entries, hostScores: entries.hostScores, to: storeURL, hostScoreStoreURL: hostScoreStoreURL)
            await actor.completePersist()
        }
    }

    private func persistenceSnapshotForWrite() async -> PersistenceSnapshot {
        persistDirty = false
        return PersistenceSnapshot(entries: entries, hostScores: hostScores)
    }

    private func completePersist() async {
        persistTask = nil
        if persistDirty {
            schedulePersist()
        }
    }

    nonisolated private static func writePersistedEntries(
        _ entries: [String: Entry],
        hostScores: [String: HostScore],
        to storeURL: URL,
        hostScoreStoreURL: URL
    ) {
        do {
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(entries)
            try data.write(to: storeURL, options: .atomic)
            let scoreData = try JSONEncoder().encode(hostScores)
            try scoreData.write(to: hostScoreStoreURL, options: .atomic)
        } catch {}
    }

    private struct PersistenceSnapshot: Sendable {
        let entries: [String: Entry]
        let hostScores: [String: HostScore]
    }

    private struct Entry: Codable, Sendable {
        let preferredURLString: String
        let date: Date
    }

    private struct SessionAvoidance: Sendable {
        var reason: String
        var failureCount: Int
        var expiresAt: Date
    }

    private struct HostScore: Codable, Sendable {
        var averageMilliseconds: Double
        var averageKilobytesPerSecond: Double
        var successCount: Int
        var failureCount: Int
        var date: Date

        init(
            averageMilliseconds: Double = 900,
            averageKilobytesPerSecond: Double = 0,
            successCount: Int = 0,
            failureCount: Int = 0,
            date: Date = .distantPast
        ) {
            self.averageMilliseconds = averageMilliseconds
            self.averageKilobytesPerSecond = averageKilobytesPerSecond
            self.successCount = successCount
            self.failureCount = failureCount
            self.date = date
        }

        var rankScore: Double {
            let attempts = max(successCount + failureCount, 1)
            let failureRate = Double(failureCount) / Double(attempts)
            let throughputBonus = min(averageKilobytesPerSecond / 256.0, 300)
            return averageMilliseconds + failureRate * 900 - throughputBonus
        }

        static var unmeasuredRankScore: Double { 900 }

        mutating func record(
            elapsedMilliseconds: Double,
            bytes: Int64,
            succeeded: Bool,
            date: Date
        ) {
            let boundedElapsed = min(max(elapsedMilliseconds, 10), 8_000)
            let alpha = successCount + failureCount == 0 ? 1.0 : 0.28
            averageMilliseconds = averageMilliseconds * (1 - alpha) + boundedElapsed * alpha
            if succeeded {
                successCount += 1
                if bytes > 0, boundedElapsed > 0 {
                    let kbps = (Double(bytes) / 1024.0) / max(boundedElapsed / 1000.0, 0.001)
                    let throughputAlpha = averageKilobytesPerSecond <= 0 ? 1.0 : 0.24
                    averageKilobytesPerSecond = averageKilobytesPerSecond * (1 - throughputAlpha) + kbps * throughputAlpha
                }
            } else {
                failureCount += 1
            }
            if successCount + failureCount > 80 {
                successCount = max(successCount / 2, succeeded ? 1 : 0)
                failureCount = failureCount / 2
            }
            self.date = date
        }
    }
}

nonisolated private final class LocalHLSProxyServer: @unchecked Sendable {
    nonisolated private static let maxStreamingCacheBytes: Int64 = 24 * 1024 * 1024

    nonisolated(unsafe) private var headers: [String: String]
    nonisolated(unsafe) private var metricsID: String?
    private let listener: NWListener
    private let queue: DispatchQueue
    private let failureStore = HLSProxyFailureStore()
    nonisolated(unsafe) private var remoteFailureHandler: HLSRemoteFailureHandler?
    nonisolated(unsafe) private var routes: [String: HLSProxyRoute] = [:]
    nonisolated(unsafe) private var activeConnections: [ObjectIdentifier: NWConnection] = [:]
    nonisolated(unsafe) private var isStarted = false
    nonisolated(unsafe) private var isClosed = false

    nonisolated private init(
        headers: [String: String],
        metricsID: String?,
        onRemoteFailure: HLSRemoteFailureHandler?
    ) throws {
        self.headers = headers
        self.metricsID = metricsID
        self.remoteFailureHandler = onRemoteFailure
        self.listener = try NWListener(
            using: HLSLoopbackEndpointPolicy.tcpListenerParameters(),
            on: .any
        )
        self.queue = DispatchQueue(label: "cc.bili.local-hls", qos: .userInitiated)
    }

    deinit {
        listener.cancel()
        activeConnections.values.forEach { $0.cancel() }
    }

    nonisolated func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isClosed = true
            self.isStarted = false
            self.routes.removeAll(keepingCapacity: false)
            self.listener.cancel()
            self.activeConnections.values.forEach { $0.cancel() }
            self.activeConnections.removeAll(keepingCapacity: false)
        }
    }

    nonisolated static func make(
        headers: [String: String],
        metricsID: String? = nil,
        onRemoteFailure: HLSRemoteFailureHandler? = nil
    ) throws -> LocalHLSProxyServer {
        try LocalHLSProxyServer(
            headers: headers,
            metricsID: metricsID,
            onRemoteFailure: onRemoteFailure
        )
    }

    nonisolated func updateMetricsID(_ metricsID: String?) {
        queue.async { [weak self] in
            self?.metricsID = metricsID
        }
    }

    nonisolated func updateHeaders(_ headers: [String: String]) {
        queue.async { [weak self] in
            self?.headers = headers
        }
    }

    nonisolated func updateRemoteFailureHandler(_ handler: HLSRemoteFailureHandler?) {
        queue.async { [weak self] in
            self?.remoteFailureHandler = handler
        }
    }

    nonisolated func recentRemoteFailureReason() -> HLSBridgeFailureReason? {
        failureStore.recentReason()
    }

    nonisolated private func notifyRemoteFailure(_ reason: HLSBridgeFailureReason) {
        guard let remoteFailureHandler else { return }
        Task { @MainActor in
            remoteFailureHandler(reason)
        }
    }

    nonisolated func start(
        renderPlaylists: @escaping @Sendable (URL) -> HLSBridgeRenderedPlaylists
    ) async throws -> HLSBridgeRenderedPlaylists {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: PlayerEngineError.unsupportedMedia)
                    return
                }
                guard !self.isStarted else {
                    continuation.resume(throwing: PlayerEngineError.unsupportedMedia)
                    return
                }
                self.isStarted = true

                let resumeGate = HLSContinuationResumeGate()
                self.listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        guard resumeGate.claim() else { return }
                        guard let port = self.listener.port,
                              let baseURL = URL(string: "http://127.0.0.1:\(port.rawValue)")
                        else {
                            self.listener.cancel()
                            continuation.resume(throwing: PlayerEngineError.unsupportedMedia)
                            return
                        }
                        let renderedPlaylists = renderPlaylists(baseURL)
                        self.routes = renderedPlaylists.routes
                        continuation.resume(returning: renderedPlaylists)
                    case let .failed(error):
                        guard resumeGate.claim() else { return }
                        continuation.resume(throwing: error)
                    case .cancelled:
                        break
                    default:
                        break
                    }
                }
                self.listener.newConnectionHandler = { [weak self] connection in
                    self?.handleConnection(connection)
                }
                self.listener.start(queue: self.queue)
            }
        }
    }

    nonisolated private func handleConnection(_ connection: NWConnection) {
        guard !isClosed else {
            connection.cancel()
            return
        }
        guard HLSLoopbackEndpointPolicy.allows(connection.endpoint) else {
            PlayerMetricsLog.logger.error(
                "hlsProxyRejectedNonLoopback endpoint=\(String(describing: connection.endpoint), privacy: .private)"
            )
            connection.cancel()
            return
        }
        let identifier = ObjectIdentifier(connection)
        activeConnections[identifier] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed:
                self?.queue.async { [weak self] in
                    self?.activeConnections[identifier] = nil
                }
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveRequest(from: connection, accumulatedData: Data())
    }

    nonisolated private func receiveRequest(from connection: NWConnection, accumulatedData: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            if error != nil {
                connection.cancel()
                return
            }

            var requestData = accumulatedData
            if let data {
                requestData.append(data)
            }

            if requestData.range(of: Data("\r\n\r\n".utf8)) != nil {
                self.respond(to: connection, requestData: requestData)
            } else if isComplete || requestData.count > 64 * 1024 {
                self.sendError(400, reason: "Bad Request", to: connection)
            } else {
                self.receiveRequest(from: connection, accumulatedData: requestData)
            }
        }
    }

    nonisolated private func respond(to connection: NWConnection, requestData: Data) {
        let connectionID = ObjectIdentifier(connection)
        let requestStart = CACurrentMediaTime()
        guard let request = HLSProxyRequest(data: requestData) else {
            PlayerMetricsLog.logger.error("hlsProxyBadRequest")
            sendError(400, reason: "Bad Request", to: connection)
            return
        }

        guard request.method == "GET" || request.method == "HEAD" else {
            PlayerMetricsLog.logger.error(
                "hlsProxyMethodRejected method=\(request.method, privacy: .public) path=\(request.path, privacy: .public)"
            )
            sendError(405, reason: "Method Not Allowed", to: connection)
            return
        }

        guard let route = routes[request.path] else {
            PlayerMetricsLog.logger.error(
                "hlsProxyRouteMiss method=\(request.method, privacy: .public) path=\(request.path, privacy: .public)"
            )
            sendError(404, reason: "Not Found", to: connection)
            return
        }

        switch route {
        case let .data(data, contentType):
            PlayerMetricsLog.logger.debug(
                "hlsProxyServeData method=\(request.method, privacy: .public) path=\(request.path, privacy: .public) type=\(contentType, privacy: .public) bytes=\(data.count, privacy: .public)"
            )
            sendData(
                data,
                contentType: contentType,
                request: request,
                to: connection,
                closesConnection: request.shouldCloseConnection
            )
            Task.detached(priority: .utility) { [metricsID] in
                await HLSProxyStartupMetrics.shared.record(
                    metricsID: metricsID,
                    path: request.path,
                    bytes: data.count,
                    elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: requestStart),
                    source: "data"
                )
            }
        case let .remoteByteRange(url, fallbackURLs, sourceRange, contentType, transform):
            Task.detached(priority: .userInitiated) { [headers] in
                await self.serveRemoteByteRange(
                    url: url,
                    fallbackURLs: fallbackURLs,
                    sourceRange: sourceRange,
                    contentType: contentType,
                    transform: transform,
                    request: request,
                    headers: headers,
                    connectionID: connectionID,
                    to: connection
                )
            }
        }
    }

    nonisolated private func serveRemoteByteRange(
        url: URL,
        fallbackURLs: [URL],
        sourceRange: HTTPByteRange,
        contentType: String,
        transform: HLSMediaSegmentTransform?,
        request: HLSProxyRequest,
        headers: [String: String],
        connectionID: ObjectIdentifier,
        to connection: NWConnection
    ) async {
        let start = CACurrentMediaTime()
        let resolvedRange = request.range?.clamped(toLength: sourceRange.length)
        let fetchRange: HTTPByteRange
        if transform != nil {
            fetchRange = sourceRange
        } else if let resolvedRange {
            fetchRange = HTTPByteRange(
                start: sourceRange.start + resolvedRange.start,
                endInclusive: sourceRange.start + resolvedRange.endInclusive
            )
        } else {
            fetchRange = sourceRange
        }

        let sourceURLs = ([url] + fallbackURLs).removingDuplicates()
        if let cached = await cachedRange(fetchRange, sourceURLs: sourceURLs, transform: transform) {
            let responseData = responseData(from: cached, servedRange: resolvedRange, transform: transform)
            let elapsedMilliseconds = PlayerMetricsLog.elapsedMilliseconds(since: start)
            PlayerMetricsLog.logger.info(
                "hlsProxyRangeCacheHit path=\(request.path, privacy: .public) bytes=\(responseData.count, privacy: .public) elapsedMs=\(elapsedMilliseconds, format: .fixed(precision: 1), privacy: .public)"
            )
            await HLSProxyCacheMetrics.shared.record(
                metricsID: metricsID,
                path: request.path,
                source: "cache",
                bytes: responseData.count,
                elapsedMilliseconds: elapsedMilliseconds
            )
            await HLSProxyStartupMetrics.shared.record(
                metricsID: metricsID,
                path: request.path,
                bytes: responseData.count,
                elapsedMilliseconds: elapsedMilliseconds,
                source: "cache"
            )
            queue.async {
                guard self.isConnectionActive(connectionID) else { return }
                self.sendData(
                    responseData,
                    contentType: contentType,
                    request: request,
                    totalLength: sourceRange.length,
                    servedRange: resolvedRange,
                    to: connection,
                    closesConnection: true
                )
            }
            return
        }

        do {
            let fetchStart = CACurrentMediaTime()
            if shouldStreamRemoteRange(request: request, range: fetchRange, transform: transform) {
                try await streamRemoteByteRange(
                    fetchRange,
                    from: sourceURLs,
                    primaryURL: url,
                    contentType: contentType,
                    transform: transform,
                    request: request,
                    headers: headers,
                    totalLength: sourceRange.length,
                    servedRange: resolvedRange,
                    connectionID: connectionID,
                    to: connection
                )
                PlayerMetricsLog.logger.info(
                    "hlsProxyRangeStreamed path=\(request.path, privacy: .public) bytes=\(fetchRange.length, privacy: .public) elapsedMs=\(PlayerMetricsLog.elapsedMilliseconds(since: fetchStart), format: .fixed(precision: 1), privacy: .public)"
                )
                return
            }

            let fetchedData = try await LocalHLSBridge.fetchByteRange(
                fetchRange,
                from: sourceURLs,
                headers: headers,
                strategy: startupFetchStrategy(for: request.path)
            )
            let transformedData = transform?.apply(to: fetchedData) ?? fetchedData
            let data = responseData(from: transformedData, servedRange: resolvedRange, transform: transform)
            let elapsedMilliseconds = PlayerMetricsLog.elapsedMilliseconds(since: start)
            PlayerMetricsLog.logger.info(
                "hlsProxyRangeFetched path=\(request.path, privacy: .public) bytes=\(data.count, privacy: .public) fetchMs=\(PlayerMetricsLog.elapsedMilliseconds(since: fetchStart), format: .fixed(precision: 1), privacy: .public) elapsedMs=\(elapsedMilliseconds, format: .fixed(precision: 1), privacy: .public)"
            )
            await HLSProxyCacheMetrics.shared.record(
                metricsID: metricsID,
                path: request.path,
                source: "fetch",
                bytes: data.count,
                elapsedMilliseconds: elapsedMilliseconds
            )
            await HLSProxyStartupMetrics.shared.record(
                metricsID: metricsID,
                path: request.path,
                bytes: data.count,
                elapsedMilliseconds: elapsedMilliseconds,
                source: "fetch"
            )
            queue.async {
                guard self.isConnectionActive(connectionID) else { return }
                self.sendData(
                    data,
                    contentType: contentType,
                    request: request,
                    totalLength: sourceRange.length,
                    servedRange: resolvedRange,
                    to: connection,
                    closesConnection: true
                )
            }
        } catch {
            let proxyFailure = HLSBridgeRemoteFailure.proxyHTTPStatus(for: error)
            let failureReason = HLSBridgeRemoteFailure.reason(for: error)
            failureStore.record(failureReason)
            notifyRemoteFailure(failureReason)
            PlayerMetricsLog.logger.error(
                "hlsProxyRemoteFetchFailed path=\(request.path, privacy: .public) range=\(fetchRange.start, privacy: .public)-\(fetchRange.endInclusive, privacy: .public) status=\(proxyFailure.statusCode, privacy: .public) url=\(url.absoluteString, privacy: .private) error=\(error.localizedDescription, privacy: .public)"
            )
            queue.async {
                guard self.isConnectionActive(connectionID) else { return }
                self.sendError(proxyFailure.statusCode, reason: proxyFailure.reason, to: connection)
            }
        }
    }

    nonisolated private func responseData(
        from data: Data,
        servedRange: HTTPByteRange?,
        transform: HLSMediaSegmentTransform?
    ) -> Data {
        guard transform != nil, let servedRange else { return data }
        guard let lowerBound = Int(exactly: servedRange.start),
              let upperBoundInclusive = Int(exactly: servedRange.endInclusive),
              lowerBound >= 0,
              upperBoundInclusive >= lowerBound,
              upperBoundInclusive < data.count
        else {
            return Data()
        }
        return data.subdata(in: lowerBound..<(upperBoundInclusive + 1))
    }

    nonisolated private func cachedRange(_ range: HTTPByteRange, sourceURLs: [URL], transform: HLSMediaSegmentTransform?) async -> Data? {
        for url in sourceURLs {
            if let cached = await VideoRangeCache.shared.data(url: url, range: range) {
                return transform?.apply(to: cached) ?? cached
            }
        }
        return nil
    }

    nonisolated private func startupFetchStrategy(for path: String) -> HLSByteRangeFetchStrategy {
        if PlaybackEnvironment.current.shouldPreferConservativePlayback {
            return .sequential
        }
        if path.hasSuffix("/init.mp4") {
            return .fastFallback
        }
        return .sequential
    }

    nonisolated private func shouldStreamRemoteRange(
        request: HLSProxyRequest,
        range: HTTPByteRange,
        transform: HLSMediaSegmentTransform?
    ) -> Bool {
        guard case nil = request.range else { return false }
        guard request.method == "GET" else { return false }
        if request.path.contains("/media/video") {
            return range.length >= 512 * 1024
        }
        return request.path.contains("/media/audio/")
            && (request.path.contains("/segment-0.m4s") || request.path.contains("/segment-1.m4s"))
            && range.length >= 128 * 1024
    }

    nonisolated private func startupChunkSize(for path: String, transform: HLSMediaSegmentTransform?) -> Int {
        if transform != nil {
            return 16 * 1024
        }
        if path.contains("/media/audio/") {
            return 12 * 1024
        }
        if path.contains("/segment-0.m4s") || path.contains("/segment-1.m4s") {
            return 8 * 1024
        }
        return 32 * 1024
    }

    nonisolated private static func isStartupCriticalMediaPath(_ path: String) -> Bool {
        path.hasSuffix("/init.mp4")
            || path.contains("/segment-0.m4s")
            || path.contains("/segment-1.m4s")
    }

    nonisolated private static func shouldSessionAvoidSlowStartupHost(
        path: String,
        elapsedMilliseconds: Double,
        bytes: Int,
        sourceURLCount: Int
    ) -> Bool {
        guard sourceURLCount > 1,
              isStartupCriticalMediaPath(path),
              !PlaybackEnvironment.current.shouldPreferConservativePlayback
        else { return false }

        if path.hasSuffix("/init.mp4") {
            return elapsedMilliseconds >= 850
        }

        let kilobytesPerSecond = bytes > 0 && elapsedMilliseconds > 0
            ? (Double(bytes) / 1024.0) / max(elapsedMilliseconds / 1000.0, 0.001)
            : 0
        let threshold: Double = path.contains("/segment-0.m4s") ? 2_200 : 2_800
        return elapsedMilliseconds >= threshold && kilobytesPerSecond < 768
    }

    nonisolated private static var startupHedgeDelayNanoseconds: UInt64 {
        switch PlaybackEnvironment.current.networkClass {
        case .wifi:
            return 420_000_000
        case .cellular:
            return 520_000_000
        case .constrained:
            return 620_000_000
        case .unknown:
            return 480_000_000
        }
    }

    nonisolated private static func shouldHedgeStartupRange(
        path: String,
        sourceURLCount: Int
    ) -> Bool {
        sourceURLCount > 1
            && isStartupCriticalMediaPath(path)
            && !PlaybackEnvironment.current.shouldPreferConservativePlayback
    }

    nonisolated private static func slowStartupAvoidanceReason(path: String, elapsedMilliseconds: Double) -> String {
        let bucket: String
        if path.hasSuffix("/init.mp4") {
            bucket = "init"
        } else if path.contains("/segment-0.m4s") {
            bucket = "seg0"
        } else if path.contains("/segment-1.m4s") {
            bucket = "seg1"
        } else {
            bucket = "startup"
        }
        return "\(bucket)-slow-\(Int(elapsedMilliseconds.rounded()))ms"
    }

    nonisolated private func streamHedgedStartupRange(
        _ range: HTTPByteRange,
        canonicalURLs: [URL],
        sourceURLs: [URL],
        primaryURL: URL,
        contentType: String,
        transform: HLSMediaSegmentTransform?,
        request: HLSProxyRequest,
        headers: [String: String],
        totalLength: Int64,
        servedRange: HTTPByteRange?,
        to connection: NWConnection
    ) async throws {
        let streamStart = CACurrentMediaTime()
        let responseHeader = streamingHeaderData(
            contentType: contentType,
            request: request,
            responseLength: range.length,
            totalLength: totalLength,
            servedRange: servedRange
        )
        let startupMetricsID = metricsID
        let result = try await HLSRemoteRangeStreamer.streamHedged(
            range: range,
            from: sourceURLs,
            headers: headers,
            responseHeader: responseHeader,
            connection: connection,
            cacheLimit: Self.maxStreamingCacheBytes,
            startupChunkSize: startupChunkSize(for: request.path, transform: transform),
            transform: transform,
            hedgeDelayNanoseconds: Self.startupHedgeDelayNanoseconds
        ) { bytes in
            await HLSProxyStartupMetrics.shared.record(
                metricsID: startupMetricsID,
                path: request.path,
                bytes: bytes,
                elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: streamStart),
                source: "startupHedge"
            )
        }
        let elapsedMilliseconds = PlayerMetricsLog.elapsedMilliseconds(since: streamStart)
        let streamedBytes = result.cachePayload?.byteCount ?? Int(range.length)
        let selectedURL = result.sourceURL
        let shouldAvoidSlowStartupHost = Self.shouldSessionAvoidSlowStartupHost(
            path: request.path,
            elapsedMilliseconds: elapsedMilliseconds,
            bytes: streamedBytes,
            sourceURLCount: canonicalURLs.count
        )
        await HLSSourcePreferenceCache.shared.recordResult(
            url: selectedURL,
            for: canonicalURLs,
            elapsedMilliseconds: elapsedMilliseconds,
            bytes: Int64(streamedBytes),
            succeeded: true,
            metricsID: metricsID
        )
        if shouldAvoidSlowStartupHost {
            let reason = Self.slowStartupAvoidanceReason(
                path: request.path,
                elapsedMilliseconds: elapsedMilliseconds
            )
            await HLSSourcePreferenceCache.shared.recordSessionAvoidance(
                host: selectedURL.host,
                reason: reason,
                metricsID: metricsID
            )
        } else {
            await HLSSourcePreferenceCache.shared.recordPreferredURL(selectedURL, for: canonicalURLs)
        }
        await HLSProxyCacheMetrics.shared.record(
            metricsID: metricsID,
            path: request.path,
            source: "startupHedge",
            bytes: streamedBytes,
            elapsedMilliseconds: elapsedMilliseconds
        )
        await HLSProxyStartupMetrics.shared.record(
            metricsID: metricsID,
            path: request.path,
            bytes: streamedBytes,
            elapsedMilliseconds: elapsedMilliseconds,
            source: "startupHedge"
        )
        if let cacheData = result.cachePayload {
            do {
                let data = try cacheData.loadData()
                await VideoRangeCache.shared.store(data, url: selectedURL, range: range)
                if selectedURL != primaryURL {
                    await VideoRangeCache.shared.store(data, url: primaryURL, range: range)
                }
            } catch {
                PlayerMetricsLog.logger.error(
                    "hlsProxyStartupHedgeCacheWriteFailed path=\(request.path, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
            }
            cacheData.cleanup()
        }
        await PlayerMetricsLog.record(
            .network,
            metricsID: metricsID ?? request.path,
            message: "startupHedge winner=\(selectedURL.host ?? "-") index=\(result.sourceIndex) delay=\(Int(Self.startupHedgeDelayNanoseconds / 1_000_000))ms first=\(Int(result.firstChunkElapsedMilliseconds.rounded()))ms total=\(Int(elapsedMilliseconds.rounded()))ms"
        )
    }

    nonisolated private func streamRemoteByteRange(
        _ range: HTTPByteRange,
        from urls: [URL],
        primaryURL: URL,
        contentType: String,
        transform: HLSMediaSegmentTransform?,
        request: HLSProxyRequest,
        headers: [String: String],
        totalLength: Int64,
        servedRange: HTTPByteRange?,
        connectionID: ObjectIdentifier,
        to connection: NWConnection
    ) async throws {
        let canonicalURLs = urls.removingDuplicates()
        let sourceURLs = await HLSSourcePreferenceCache.shared.preferredURLs(for: canonicalURLs)
        if Self.shouldHedgeStartupRange(
            path: request.path,
            sourceURLCount: canonicalURLs.count
        ) {
            try await streamHedgedStartupRange(
                range,
                canonicalURLs: canonicalURLs,
                sourceURLs: sourceURLs,
                primaryURL: primaryURL,
                contentType: contentType,
                transform: transform,
                request: request,
                headers: headers,
                totalLength: totalLength,
                servedRange: servedRange,
                to: connection
            )
            return
        }
        var lastError: Error?

        for (index, url) in sourceURLs.enumerated() {
            let reservation = await VideoRangeCache.shared.reserveExternalFetch(
                url: url,
                range: range,
                maxCacheBytes: Self.maxStreamingCacheBytes
            )
            switch reservation {
            case let .cached(data):
                let cachedStart = CACurrentMediaTime()
                let responseData = transform?.apply(to: data) ?? data
                queue.async {
                    guard self.isConnectionActive(connectionID) else { return }
                    self.sendData(
                        responseData,
                        contentType: contentType,
                        request: request,
                        totalLength: totalLength,
                        servedRange: servedRange,
                        to: connection,
                        closesConnection: true
                    )
                }
                PlayerMetricsLog.logger.info(
                    "hlsProxyRangeStreamCacheHit path=\(request.path, privacy: .public) bytes=\(responseData.count, privacy: .public)"
                )
                await HLSProxyCacheMetrics.shared.record(
                    metricsID: metricsID,
                    path: request.path,
                    source: "streamCache",
                    bytes: responseData.count,
                    elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: cachedStart)
                )
                await HLSProxyStartupMetrics.shared.record(
                    metricsID: metricsID,
                    path: request.path,
                    bytes: responseData.count,
                    elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: cachedStart),
                    source: "streamCache"
                )
                return
            case let .pending(task):
                do {
                    let joinedStart = CACurrentMediaTime()
                    let data = try await task.value
                    let responseData = transform?.apply(to: data) ?? data
                    queue.async {
                        guard self.isConnectionActive(connectionID) else { return }
                        self.sendData(
                            responseData,
                            contentType: contentType,
                            request: request,
                            totalLength: totalLength,
                            servedRange: servedRange,
                            to: connection,
                            closesConnection: true
                        )
                    }
                    PlayerMetricsLog.logger.info(
                        "hlsProxyRangeStreamJoined path=\(request.path, privacy: .public) bytes=\(responseData.count, privacy: .public)"
                    )
                    await HLSProxyCacheMetrics.shared.record(
                        metricsID: metricsID,
                        path: request.path,
                        source: "streamJoin",
                        bytes: responseData.count,
                        elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: joinedStart)
                    )
                    await HLSProxyStartupMetrics.shared.record(
                        metricsID: metricsID,
                        path: request.path,
                        bytes: responseData.count,
                        elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: joinedStart),
                        source: "streamJoin"
                    )
                    return
                } catch {
                    lastError = error
                    guard index < sourceURLs.count - 1, !Task.isCancelled else { break }
                    continue
                }
            case .unreserved, .reserved:
                break
            }

            do {
                let streamStart = CACurrentMediaTime()
                let responseHeader = streamingHeaderData(
                    contentType: contentType,
                    request: request,
                    responseLength: range.length,
                    totalLength: totalLength,
                    servedRange: servedRange
                )
                let startupMetricsID = metricsID
                let cacheData = try await HLSRemoteRangeStreamer.stream(
                    range: range,
                    from: url,
                    headers: headers,
                    responseHeader: responseHeader,
                    connection: connection,
                    cacheLimit: Self.maxStreamingCacheBytes,
                    startupChunkSize: startupChunkSize(for: request.path, transform: transform),
                    transform: transform
                ) { bytes in
                    await HLSProxyStartupMetrics.shared.record(
                        metricsID: startupMetricsID,
                        path: request.path,
                        bytes: bytes,
                        elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: streamStart),
                        source: "stream"
                    )
                }
                let streamElapsed = PlayerMetricsLog.elapsedMilliseconds(since: streamStart)
                let streamedBytes = cacheData?.byteCount ?? Int(range.length)
                let shouldAvoidSlowStartupHost = Self.shouldSessionAvoidSlowStartupHost(
                    path: request.path,
                    elapsedMilliseconds: streamElapsed,
                    bytes: streamedBytes,
                    sourceURLCount: canonicalURLs.count
                )
                await HLSSourcePreferenceCache.shared.recordResult(
                    url: url,
                    for: canonicalURLs,
                    elapsedMilliseconds: streamElapsed,
                    bytes: Int64(streamedBytes),
                    succeeded: true,
                    metricsID: metricsID
                )
                if shouldAvoidSlowStartupHost {
                    let reason = Self.slowStartupAvoidanceReason(path: request.path, elapsedMilliseconds: streamElapsed)
                    await HLSSourcePreferenceCache.shared.recordSessionAvoidance(
                        host: url.host,
                        reason: reason,
                        metricsID: metricsID
                    )
                    await PlayerMetricsLog.record(
                        .network,
                        metricsID: metricsID ?? request.path,
                        message: "startupAvoid host=\(url.host ?? "-") reason=\(reason) bytes=\(streamedBytes / 1024)KB"
                    )
                }
                if request.path.contains("/segment-0.m4s") || request.path.contains("/init.mp4") {
                    await PlayerMetricsLog.record(
                        .network,
                        metricsID: metricsID ?? request.path,
                        message: "host=\(url.host ?? "-") \(Int(streamElapsed.rounded()))ms \(streamedBytes / 1024)KB"
                    )
                }
                await HLSProxyCacheMetrics.shared.record(
                    metricsID: metricsID,
                    path: request.path,
                    source: "stream",
                    bytes: streamedBytes,
                    elapsedMilliseconds: streamElapsed
                )
                if !shouldAvoidSlowStartupHost {
                    await HLSSourcePreferenceCache.shared.recordPreferredURL(url, for: canonicalURLs)
                }
                if case let .reserved(token) = reservation {
                    if let cacheData {
                        do {
                            let data = try cacheData.loadData()
                            await VideoRangeCache.shared.finishExternalFetch(token, data: data)
                        } catch {
                            await VideoRangeCache.shared.failExternalFetch(token, error: error)
                        }
                    } else {
                        await VideoRangeCache.shared.failExternalFetch(token, error: HLSRangeStreamError.notCacheable)
                    }
                }
                if let cacheData, !reservation.isReserved {
                    do {
                        let data = try cacheData.loadData()
                        await VideoRangeCache.shared.store(data, url: url, range: range)
                        if url != primaryURL {
                            await VideoRangeCache.shared.store(data, url: primaryURL, range: range)
                        }
                    } catch {
                        PlayerMetricsLog.logger.error(
                            "hlsProxyRangeStreamCacheWriteFailed path=\(request.path, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                        )
                    }
                }
                cacheData?.cleanup()
                if index > 0 {
                    PlayerMetricsLog.logger.info(
                        "hlsProxyRangeStreamFallbackSuccess fallbackIndex=\(index, privacy: .public) path=\(request.path, privacy: .public)"
                    )
                }
                return
            } catch {
                if case let .reserved(token) = reservation {
                    await VideoRangeCache.shared.failExternalFetch(token, error: error)
                }
                await HLSSourcePreferenceCache.shared.recordFailure(
                    url: url,
                    for: canonicalURLs,
                    elapsedMilliseconds: 0,
                    error: error,
                    metricsID: metricsID
                )
                lastError = error
                if let streamError = error as? HLSRangeStreamError,
                   !streamError.isRetryable {
                    break
                }
                guard index < sourceURLs.count - 1, !Task.isCancelled else { break }
                PlayerMetricsLog.logger.info(
                    "hlsProxyRangeStreamFallbackSwitch fallbackIndex=\(index + 1, privacy: .public) path=\(request.path, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
            }
        }

        throw lastError ?? PlayerEngineError.unsupportedMedia
    }

    nonisolated private func streamingHeaderData(
        contentType: String,
        request: HLSProxyRequest,
        responseLength: Int64,
        totalLength: Int64,
        servedRange: HTTPByteRange?
    ) -> Data {
        HLSProxyHTTPResponseBuilder.dataResponse(
            contentType: contentType,
            request: request,
            responseLength: responseLength,
            totalLength: totalLength,
            servedRange: servedRange,
            closesConnection: true
        ).headerData
    }

    nonisolated private func sendData(
        _ data: Data,
        contentType: String,
        request: HLSProxyRequest,
        totalLength: Int64? = nil,
        servedRange: HTTPByteRange? = nil,
        to connection: NWConnection,
        closesConnection: Bool = true
    ) {
        let body = request.method == "HEAD" ? Data() : data
        let response = HLSProxyHTTPResponseBuilder.dataResponse(
            contentType: contentType,
            request: request,
            responseLength: Int64(data.count),
            totalLength: totalLength,
            servedRange: servedRange,
            closesConnection: closesConnection
        )
        sendResponse(
            statusLine: response.statusLine,
            headers: response.headers,
            body: body,
            to: connection,
            closesConnection: closesConnection
        )
    }

    nonisolated private func sendError(_ statusCode: Int, reason: String, to connection: NWConnection) {
        let errorResponse = HLSProxyHTTPResponseBuilder.errorResponse(statusCode: statusCode, reason: reason)
        sendResponse(
            statusLine: errorResponse.response.statusLine,
            headers: errorResponse.response.headers,
            body: errorResponse.body,
            to: connection
        )
    }

    nonisolated private func sendStreamingHeader(
        contentType: String,
        request: HLSProxyRequest,
        responseLength: Int64,
        totalLength: Int64,
        servedRange: HTTPByteRange?,
        to connection: NWConnection
    ) async throws {
        let response = HLSProxyHTTPResponseBuilder.dataResponse(
            contentType: contentType,
            request: request,
            responseLength: responseLength,
            totalLength: totalLength,
            servedRange: servedRange,
            closesConnection: true
        )
        try await sendContent(response.headerData, to: connection)
    }

    nonisolated private func sendResponse(
        statusLine: String,
        headers: [String: String],
        body: Data,
        to connection: NWConnection,
        closesConnection: Bool = true
    ) {
        var response = HLSProxyHTTPResponse(statusLine: statusLine, headers: headers).headerData
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { [weak self] _ in
            guard !closesConnection, let self else {
                connection.cancel()
                return
            }
            guard self.isConnectionActive(ObjectIdentifier(connection)) else {
                connection.cancel()
                return
            }
            self.receiveRequest(from: connection, accumulatedData: Data())
        })
    }

    nonisolated private func isConnectionActive(_ identifier: ObjectIdentifier) -> Bool {
        !isClosed && activeConnections[identifier] != nil
    }

    nonisolated private func sendContent(_ data: Data, to connection: NWConnection) async throws {
        guard !data.isEmpty else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

}

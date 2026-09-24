import AVFoundation
@preconcurrency import AVKit
import Combine
import MediaPlayer
import OSLog
import SwiftUI
import UIKit

struct PlaybackTransitionSnapshot {
    let image: UIImage
    let isVideoFrame: Bool

    init(image: UIImage, isVideoFrame: Bool = true) {
        self.image = image
        self.isVideoFrame = isVideoFrame
    }
}

@MainActor
enum PlayerStartupResumePolicy {
    case deferred
    case immediate
}

enum PlaybackRecoveryWatchdogReason: Sendable, Equatable {
    case firstFrame
    case stall

    func delay(for dynamicRange: BiliVideoDynamicRange) -> UInt64 {
        switch self {
        case .firstFrame:
            return dynamicRange.isHDR ? 12_000_000_000 : 1_700_000_000
        case .stall:
            return dynamicRange.isHDR ? 7_000_000_000 : 3_200_000_000
        }
    }

    var logTitle: String {
        switch self {
        case .firstFrame:
            return "first-frame"
        case .stall:
            return "stall"
        }
    }
}

private struct NavigationAudioSuspension {
    let volume: Float
    let isMuted: Bool
    let resumeTime: TimeInterval
    let shouldResumePlayback: Bool
}

private struct PlayerNowPlayingMetadataFingerprint: Equatable {
    let playerID: ObjectIdentifier
    let title: String
    let artist: String
    let artworkURL: URL?
    let durationSeconds: Int?
    let playbackRatePercent: Int
    let playbackState: MPNowPlayingPlaybackState
    let isLiveStream: Bool
}

enum PlayerSystemMediaPresentationPolicy {
    static let publishesNowPlayingInfo = false
}

enum PlayerNowPlayingPublicationPolicy {
    static func shouldPublish(
        isActive: Bool,
        wantsAutoplay: Bool,
        isPlaying: Bool,
        isTerminated: Bool,
        hasPlaybackFailure: Bool,
        playbackContentMode: PlayerPlaybackContentMode = .video
    ) -> Bool {
        guard playbackContentMode == .audioOnly
                || PlayerSystemMediaPresentationPolicy.publishesNowPlayingInfo
        else {
            return false
        }
        return !isTerminated
            && !hasPlaybackFailure
            && isActive
            && (wantsAutoplay || isPlaying)
    }
}

@MainActor
private final class PlayerRemoteControlSession {
    static let shared = PlayerRemoteControlSession()

    private var currentPlayerID: ObjectIdentifier?
    private var remoteCommandTargets: [Any] = []
    private var currentArtworkURL: URL?
    private var currentArtwork: MPMediaItemArtwork?
    private var artworkTask: Task<Void, Never>?
    private var lastMetadataFingerprint: PlayerNowPlayingMetadataFingerprint?

    private init() {}

    func activate(
        for player: PlayerStateViewModel,
        forceNowPlayingTimeUpdate: Bool = false
    ) {
        guard ActivePlaybackCoordinator.shared.isActive(player) else { return }
        configureRemoteCommandsIfNeeded()
        UIApplication.shared.beginReceivingRemoteControlEvents()
        let playerID = ObjectIdentifier(player)
        if currentPlayerID != playerID {
            currentPlayerID = playerID
            resetDetailedMetadataCache()
        }

        publishNowPlayingMetadata(
            for: player,
            force: forceNowPlayingTimeUpdate
        )
    }

    func clearIfCurrent(_ player: PlayerStateViewModel) {
        clearIfCurrentPlayerID(ObjectIdentifier(player))
    }

    func clearIfCurrentPlayerID(_ playerID: ObjectIdentifier) {
        guard currentPlayerID == playerID else { return }
        clear()
    }

    func clear() {
        currentPlayerID = nil
        resetDetailedMetadataCache()
        let center = MPRemoteCommandCenter.shared()
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        UIApplication.shared.endReceivingRemoteControlEvents()
    }

    private func publishNowPlayingMetadata(
        for player: PlayerStateViewModel,
        force: Bool = false
    ) {
        let playerID = ObjectIdentifier(player)
        guard currentPlayerID == playerID else { return }

        let duration = player.displayDuration.flatMap { $0 > 0 ? $0 : nil }
        let playbackState = player.nowPlayingPlaybackState
        let fingerprint = PlayerNowPlayingMetadataFingerprint(
            playerID: playerID,
            title: player.title,
            artist: player.nowPlayingArtist,
            artworkURL: player.artworkURL,
            durationSeconds: duration.map { Int($0.rounded()) },
            playbackRatePercent: Int((player.playbackRate.rawValue * 100).rounded()),
            playbackState: playbackState,
            isLiveStream: player.isNowPlayingLiveStream
        )

        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.nextTrackCommand.isEnabled = player.canRequestNextTrack
        commandCenter.previousTrackCommand.isEnabled = player.canRequestPreviousTrack
        updateArtworkIfNeeded(for: player)
        guard force || fingerprint != lastMetadataFingerprint else { return }
        lastMetadataFingerprint = fingerprint

        let effectiveRate = playbackState == .playing ? max(player.playbackRate.rawValue, 0) : 0
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: player.title.isEmpty ? "CiliCili" : player.title,
            MPMediaItemPropertyArtist: player.nowPlayingArtist,
            MPNowPlayingInfoPropertyPlaybackRate: effectiveRate,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: max(player.playbackRate.rawValue, 0),
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]
        if player.isNowPlayingLiveStream {
            info[MPNowPlayingInfoPropertyIsLiveStream] = true
        } else if let duration {
            info[MPMediaItemPropertyPlaybackDuration] = duration
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = min(
                max(player.currentTime, 0),
                duration
            )
        }
        if let currentArtwork {
            info[MPMediaItemPropertyArtwork] = currentArtwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = playbackState
    }

    private func updateArtworkIfNeeded(for player: PlayerStateViewModel) {
        guard let artworkURL = player.artworkURL else {
            guard currentArtworkURL != nil || currentArtwork != nil else { return }
            currentArtworkURL = nil
            currentArtwork = nil
            artworkTask?.cancel()
            artworkTask = nil
            return
        }
        guard currentArtworkURL != artworkURL else { return }

        currentArtworkURL = artworkURL
        currentArtwork = nil
        artworkTask?.cancel()
        let playerID = ObjectIdentifier(player)
        artworkTask = Task { @MainActor [weak self, weak player] in
            let image = await RemoteImageCache.shared.load(
                url: artworkURL,
                scale: 1,
                targetPixelSize: 720
            )
            guard let self,
                  let player,
                  !Task.isCancelled,
                  self.currentPlayerID == playerID,
                  self.currentArtworkURL == artworkURL,
                  let image
            else { return }
            self.currentArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            self.publishNowPlayingMetadata(for: player, force: true)
        }
    }

    private func resetDetailedMetadataCache() {
        currentArtworkURL = nil
        currentArtwork = nil
        artworkTask?.cancel()
        artworkTask = nil
        lastMetadataFingerprint = nil
    }

    private func configureRemoteCommandsIfNeeded() {
        guard remoteCommandTargets.isEmpty else { return }
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true
        center.skipForwardCommand.isEnabled = true
        center.skipBackwardCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
        center.skipForwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.preferredIntervals = [15]

        remoteCommandTargets.append(center.playCommand.addTarget { _ in
            Task { @MainActor in
                ActivePlaybackCoordinator.shared.currentActivePlayer()?.play()
            }
            return .success
        })
        remoteCommandTargets.append(center.pauseCommand.addTarget { _ in
            Task { @MainActor in
                ActivePlaybackCoordinator.shared.currentActivePlayer()?.pause()
            }
            return .success
        })
        remoteCommandTargets.append(center.togglePlayPauseCommand.addTarget { _ in
            Task { @MainActor in
                ActivePlaybackCoordinator.shared.currentActivePlayer()?.togglePlayback()
            }
            return .success
        })
        remoteCommandTargets.append(center.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in
                guard let player = ActivePlaybackCoordinator.shared.currentActivePlayer(),
                      let duration = player.displayDuration,
                      duration > 0
                else { return }
                player.seek(to: min(max(event.positionTime / duration, 0), 1))
            }
            return .success
        })
        remoteCommandTargets.append(center.skipForwardCommand.addTarget { _ in
            Task { @MainActor in
                ActivePlaybackCoordinator.shared.currentActivePlayer()?.seek(by: 15)
            }
            return .success
        })
        remoteCommandTargets.append(center.skipBackwardCommand.addTarget { _ in
            Task { @MainActor in
                ActivePlaybackCoordinator.shared.currentActivePlayer()?.seek(by: -15)
            }
            return .success
        })
        remoteCommandTargets.append(center.nextTrackCommand.addTarget { _ in
            Task { @MainActor in
                ActivePlaybackCoordinator.shared.currentActivePlayer()?.requestNextTrack()
            }
            return .success
        })
        remoteCommandTargets.append(center.previousTrackCommand.addTarget { _ in
            Task { @MainActor in
                ActivePlaybackCoordinator.shared.currentActivePlayer()?.requestPreviousTrack()
            }
            return .success
        })
    }
}

@MainActor
enum PlayerSystemMediaControls {
    static func clear() {
        PlayerRemoteControlSession.shared.clear()
    }
}

enum PlayerScrubInteractionSource: String, Sendable {
    case nativeProgress = "native"
    case surfaceGesture = "surface"
    case pinnedProgress = "pinned"
}

@MainActor
final class PlayerPlaybackClock: ObservableObject {
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval?
    @Published private(set) var seekPreviewProgress: Double?

    var progress: Double {
        guard let duration, duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    var displayProgress: Double {
        seekPreviewProgress ?? progress
    }

    var displayCurrentTime: TimeInterval {
        guard let seekPreviewProgress, let duration, duration > 0 else {
            return currentTime
        }
        return min(max(seekPreviewProgress, 0), 1) * duration
    }

    func update(time: TimeInterval? = nil, duration: TimeInterval? = nil, force: Bool = false) {
        let nextTime = max(time ?? currentTime, 0)
        let nextDuration = duration
        let durationChanged: Bool
        if let currentDuration = self.duration, let nextDuration {
            durationChanged = abs(currentDuration - nextDuration) >= 0.5
        } else {
            durationChanged = self.duration != nil || nextDuration != nil
        }

        if force || durationChanged {
            self.duration = nextDuration
        }
        if force || abs(currentTime - nextTime) >= 0.2 || (currentTime <= 0 && nextTime > 0) {
            currentTime = nextTime
        }
    }

    func reset() {
        currentTime = 0
        duration = nil
        seekPreviewProgress = nil
    }

    func updateSeekPreview(progress: Double, force: Bool = false) {
        let clamped = min(max(progress, 0), 1)
        guard force || seekPreviewProgress != clamped else { return }
        seekPreviewProgress = clamped
    }

    func clearSeekPreview() {
        seekPreviewProgress = nil
    }
}

@MainActor
final class PlayerStateViewModel: NSObject, ObservableObject {
    let title: String
    let authorName: String?
    let artworkURL: URL?
    var onPlaybackFailure: ((String?) -> Void)?
    var onPlaybackFailureWithReason: ((String?, HLSBridgeFailureReason?) -> Void)?
    var onBufferingPressure: ((Int) -> Void)?
    var onFirstFramePresented: (@MainActor () -> Void)?
    var onExplicitPlaybackStartRequested: (@MainActor () -> Void)?
    var onPlaybackEnded: (@MainActor () -> Void)?
    var onNextTrackRequested: (@MainActor () -> Void)?
    var onPreviousTrackRequested: (@MainActor () -> Void)?
    var restoreUserInterfaceForPictureInPictureStop: (() async -> Bool)?
#if DEBUG
    var onVideoDetailPlaybackDiagnosticSurfaceEvent: (@MainActor (VideoDetailPlaybackDiagnosticSurfaceEvent) -> Void)?

    var debugPlayerIdentity: ObjectIdentifier {
        ObjectIdentifier(self)
    }

    var debugAVPlayerIdentity: ObjectIdentifier? {
        engine.debugPlayerIdentity
    }

    var debugAVPlayerItemIdentity: ObjectIdentifier? {
        engine.debugPlayerItemIdentity
    }

    var debugHasUsableVideoFrame: Bool? {
        guard let image = engine.currentVideoFrameImage() else { return nil }
        return !image.biliLooksLikeBlackFrame
    }
#endif

    private(set) var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval?
    @Published var isPlaying = false
    @Published var isSeekable = false
    @Published var playbackRate: BiliPlaybackRate = .x10
    @Published var isPreparing = true
    @Published var isBuffering = false
    @Published var errorMessage: String?
    @Published var isPictureInPictureActive = false
    @Published private(set) var isPictureInPictureEnabled = false
    @Published var volume: Float = 1
    @Published var isMuted = false
    @Published private(set) var loadingProgress = 0.08
    @Published private(set) var hasPresentedPlayback = false
    @Published private(set) var isPlaybackSurfaceReady = false
    @Published private(set) var isCurrentPlaybackSurfaceReadyForDisplay = false
    @Published private(set) var isAwaitingAppBackgroundSurfaceRecovery = false
    @Published private(set) var activeSponsorBlockSegment: SponsorBlockSegment?
    @Published private(set) var prepareElapsedMilliseconds: Int?
    @Published private(set) var firstFrameElapsedMilliseconds: Int?
    @Published private(set) var bufferingCount = 0
    @Published private(set) var lastBufferingElapsedMilliseconds: Int?
    @Published private(set) var playbackPhase: PlayerPlaybackPhase = .idle
    private(set) var canRequestNextTrack = false
    private(set) var canRequestPreviousTrack = false
    @Published private(set) var recoveryAttemptCount = 0
    @Published private(set) var engineDiagnostics: PlayerEngineDiagnostics = .empty
    @Published private(set) var videoPresentationSize: CGSize = .zero
    @Published private(set) var lastFailureReason: HLSBridgeFailureReason?
    @Published private(set) var isUserSeeking = false
    @Published private(set) var isAwaitingInitialManualPlayback = false
    @Published private(set) var isAwaitingRelatedVideoReturnPlayback = false
    private(set) var surfaceLayoutGeneration = 0
    var isCurrentPlaybackSurfaceReady: Bool {
        isCurrentPlaybackSurfaceReadyForDisplay
    }

    var videoAspectRatio: CGFloat? {
        guard videoPresentationSize.width > 0, videoPresentationSize.height > 0 else {
            return nil
        }
        return videoPresentationSize.width / videoPresentationSize.height
    }

    var requestedAudioStream: DASHStream? {
        streamSource.audioStream
    }

    private(set) var lastUserSeekAt: Date?

    let playbackClock = PlayerPlaybackClock()

    private(set) var wantsAutoplay = true
    private let metricsID: String
    private let metricsStartTime = CACurrentMediaTime()
    private let streamSource: PlayerStreamSource
    private let durationHint: TimeInterval?
    private let resumeTime: TimeInterval
    private let startupResumePolicy: PlayerStartupResumePolicy
    private var engine: PlayerRenderingEngine
    private var engineCallbackGeneration = 0
    private var currentVideoGravity: AVLayerVideoGravity = .resizeAspect
    private weak var surfaceView: VideoSurfaceContainerView?
    private var surfaceAttachmentGeneration = 0
    private weak var nativePlaybackController: AVPlayerViewController?
    private var prefersNativePlaybackControls = true
    private var timeObserver: Timer?
    private var didApplyResumeTime = false
    private var mediaPreparationTask: Task<Void, Never>?
    private var mediaPreparationGeneration = 0
    private var startupMediaWarmupTask: Task<Void, Never>?
    private var scrubSeekTask: Task<Void, Never>?
    private var scrubSeekGeneration = 0
    private var deferredStartupResumeTask: Task<Void, Never>?
    private var startupResumeRetryTask: Task<Void, Never>?
    private var startupResumeRetryGeneration = 0
    private var resumeRecoveryWatchdogTask: Task<Void, Never>?
    private var deferredBufferingIndicatorTask: Task<Void, Never>?
    private var playbackRecoveryWatchdogTask: Task<Void, Never>?
    private var appBackgroundResumeRecoveryTask: Task<Void, Never>?
    private var appBackgroundResumeRecoveryGeneration = 0
    private var seekRecoveryWatchdogTask: Task<Void, Never>?
    private var speedBoostRecoveryTask: Task<Void, Never>?
    private var surfaceReadinessResetTask: Task<Void, Never>?
    private var shouldResumeAfterTransientSystemOverlay = false
    private var shouldResumePlaybackAfterAppBackground = false
    private var isPlaybackStoppedForAppBackground = false
    private var didPrepareStoppedAppBackgroundPlayback = false
    private var appBackgroundPlaybackRestoreTime: TimeInterval?
    private var appBackgroundSurfaceRecoveryBaselineTime: TimeInterval?
    private var appBackgroundSurfaceRecoveryLastRenderedTime: TimeInterval?
    private var appBackgroundSurfaceRecoveryStableSampleCount = 0
    private var shouldResumePlaybackAfterUserScrub = false
    private var surfaceReadinessConfirmationTask: Task<Void, Never>?
    private var surfaceLayoutStabilizationTask: Task<Void, Never>?
    private var surfaceMigrationTask: Task<Void, Never>?
    private var isSurfaceMigrating = false
    private var currentPlaybackSurfaceReadyGeneration: Int?
    private var isNativePictureInPictureActive = false
    private var shouldPausePlaybackAfterPictureInPictureStops = false
    private var pictureInPictureStartRetryTask: Task<Void, Never>?
    private var pictureInPictureInlineRecoveryTask: Task<Void, Never>?
    private var pictureInPictureStartRetryGeneration = 0
    private var audioSessionCancellables = Set<AnyCancellable>()
    private var audioInterruptionState = VideoListenAudioInterruptionState()
    private var sponsorBlockSkipReportTasks: [UUID: Task<Void, Never>] = [:]
    private var pictureInPictureController: AVPictureInPictureController?
    private var didConfigurePictureInPicture = false
    private var sponsorBlockSegments: [SponsorBlockSegment] = []
    private var sponsorBlockSearchIndex = 0
    private var skippedSponsorBlockIDs = Set<String>()
    private var sponsorBlockReportedIDs = Set<String>()
    private var ignoredStartupPlaybackTimeOutliers = 0
    private var didRecordFirstFrameEvent = false
    private var pendingEngineFirstFrameTime: TimeInterval?
    private var forcedPlaybackTimeGuard: ForcedPlaybackTimeGuard?
    private var pendingStartupResume: PendingStartupResume?
    private var pendingResumeRecoveryMetric: PendingStartupResumeRecoveryMetric?
    private var pendingSeekRecoveryMetric: PendingSeekRecoveryMetric?
    private var lastRecoveredSeekMetricID: UUID?
    private var lastSeekBufferReadyMetricID: UUID?
    private var activeUserScrubSource: PlayerScrubInteractionSource?
    private var activeUserScrubStartedAt: CFTimeInterval?
    private var pendingUserSeekRevealTargetTime: TimeInterval?
    private var pendingUserSeekRevealReadySince: CFTimeInterval?
    private var pendingUserSeekRevealStartedAt: CFTimeInterval?
    private var navigationAudioSuspension: NavigationAudioSuspension?
    private weak var seamlessPlaybackHandoffSource: PlayerStateViewModel?
    private var lastUsablePlaybackSnapshotImage: UIImage?
    private var currentSurfaceRevealHoldUntilNanoseconds: UInt64 = 0
    private var sponsorBlockEnabled = false
    private var onSponsorBlockSegmentSkipped: (@Sendable (SponsorBlockSkipEvent) async -> Void)?
    private(set) var isTerminated = false
    private var isStopping = false
    private var lastBufferingPressureNotificationCount = 0
    private var lastPeriodicEngineDiagnosticsSyncTime: CFTimeInterval = 0
    private var playbackStateRefreshInterval: TimeInterval = 1.0
    private let sponsorBlockPrerollTolerance: TimeInterval = 0.35
    private let sponsorBlockTailTolerance: TimeInterval = 0.12
    private let forcedPlaybackTimeGuardDuration: TimeInterval = 3.5
    private let forcedPlaybackTimeGuardTolerance: TimeInterval = 2.0
    private let forcedPlaybackTimeRollbackTolerance: TimeInterval = 0.08
    private let forcedPlaybackTimeSettleAdvance: TimeInterval = 0.16
    private let forcedPlaybackTimeForwardJumpTolerance: TimeInterval = 2.0
    private let startupResumeVerificationToleranceBefore: TimeInterval = 1.2
    private let maximumPlaybackRecoveryAttempts = 2
    private let deferredBufferingIndicatorDelayNanoseconds: UInt64 = 750_000_000
    private let appBackgroundResumeRecoveryDelayNanoseconds: UInt64 = 900_000_000
    private let appBackgroundVideoOutputRecoveryGraceDelayNanoseconds: UInt64 = 1_200_000_000
    private let appBackgroundPlayerItemRecoveryGraceDelayNanoseconds: UInt64 = 1_500_000_000
    private let stoppedAppBackgroundRefreshDelayNanoseconds: UInt64 = 650_000_000
    private let stoppedAppBackgroundPlayerItemDelayNanoseconds: UInt64 = 850_000_000
    private let stoppedAppBackgroundMediaRebuildDelayNanoseconds: UInt64 = 1_200_000_000
    private let seekCoalescingDelayNanoseconds: UInt64 = 45_000_000
    private let resumeRecoveryWatchdogDelayNanoseconds: UInt64 = 2_400_000_000
    private let seekRecoveryWatchdogDelayNanoseconds: UInt64 = 2_800_000_000
    private let userSeekRevealSettleDelay: CFTimeInterval = 0.12
    private let userSeekRevealMaximumWait: CFTimeInterval = 2.4
    private static let currentSurfaceReadinessConfirmationDelays: [UInt64] = [
        34_000_000,
        90_000_000,
        180_000_000
    ]
    private static let surfaceLayoutStabilizationDelays: [UInt64] = [
        0,
        16_000_000,
        34_000_000,
        84_000_000,
        160_000_000
    ]
    private static let surfaceHandoffReadinessResetDelayNanoseconds: UInt64 = 240_000_000
    private static let surfaceMigrationHoldNanoseconds: UInt64 = 700_000_000
    private static let currentSurfaceRevealSettleDelayNanoseconds: UInt64 = 380_000_000

    init(
        videoURL: URL?,
        audioURL: URL?,
        videoStream: DASHStream? = nil,
        audioStream: DASHStream? = nil,
        alternateVideoRenditions: [PlayerVideoRenditionSource] = [],
        title: String,
        authorName: String? = nil,
        referer: String,
        durationHint: TimeInterval? = nil,
        isLiveStream: Bool = false,
        isLiveHLS: Bool = false,
        liveHLSFormat: String? = nil,
        resumeTime: TimeInterval = 0,
        startupResumePolicy: PlayerStartupResumePolicy = .deferred,
        dynamicRange: BiliVideoDynamicRange = .sdr,
        cdnPreference: PlaybackCDNPreference = .automatic,
        metricsID: String? = nil,
        httpHeaders: [String: String]? = nil,
        artworkURL: URL? = nil,
        playbackContentMode: PlayerPlaybackContentMode = .video,
        engine: PlayerRenderingEngine? = nil
    ) {
        let resolvedMetricsID = metricsID?.isEmpty == false ? metricsID! : UUID().uuidString
        self.title = title
        self.authorName = authorName
        self.artworkURL = artworkURL
        self.metricsID = resolvedMetricsID
        self.streamSource = PlayerStreamSource(
            metricsID: resolvedMetricsID,
            videoURL: videoURL,
            audioURL: audioURL,
            videoStream: videoStream,
            audioStream: audioStream,
            alternateVideoRenditions: alternateVideoRenditions,
            referer: referer,
            httpHeaders: httpHeaders ?? BiliHLSManifestBuilder.httpHeaders(referer: referer),
            title: title,
            durationHint: durationHint,
            isLiveStream: isLiveStream,
            isLiveHLS: isLiveHLS,
            liveHLSFormat: liveHLSFormat,
            resumeTime: resumeTime,
            dynamicRange: dynamicRange,
            cdnPreference: cdnPreference,
            playbackContentMode: playbackContentMode
        )
        self.durationHint = durationHint
        self.duration = durationHint
        self.playbackClock.update(time: 0, duration: durationHint, force: true)
        self.resumeTime = resumeTime
        self.startupResumePolicy = startupResumePolicy
        self.engine = engine ?? DefaultPlayerRenderingEngine.make()
        super.init()
        bindEngine(self.engine, restoreVolumeState: false)
        configureAudioSessionNotificationsIfNeeded()
        PlayerMetricsLog.logger.info(
            "created id=\(self.metricsID, privacy: .public) title=\(PlayerMetricsLog.shortTitle(title), privacy: .public) hasAudio=\((audioURL != nil), privacy: .public) resume=\(resumeTime, privacy: .public)"
        )
        PlayerMetricsLog.record(.playerCreated, metricsID: self.metricsID, title: title)
        ActivePlaybackCoordinator.shared.register(self)
        rescheduleTimeObserverIfNeeded(force: true)
    }

    isolated deinit {
        isTerminated = true
        let nowPlayingPlayerID = ObjectIdentifier(self)
        Task { @MainActor in
            PlayerRemoteControlSession.shared.clearIfCurrentPlayerID(nowPlayingPlayerID)
        }
        engineCallbackGeneration &+= 1
        mediaPreparationTask?.cancel()
        mediaPreparationTask = nil
        startupMediaWarmupTask?.cancel()
        startupMediaWarmupTask = nil
        scrubSeekTask?.cancel()
        scrubSeekTask = nil
        deferredStartupResumeTask?.cancel()
        deferredStartupResumeTask = nil
        deferredBufferingIndicatorTask?.cancel()
        deferredBufferingIndicatorTask = nil
        startupResumeRetryTask?.cancel()
        startupResumeRetryTask = nil
        startupResumeRetryGeneration &+= 1
        resumeRecoveryWatchdogTask?.cancel()
        resumeRecoveryWatchdogTask = nil
        playbackRecoveryWatchdogTask?.cancel()
        playbackRecoveryWatchdogTask = nil
        appBackgroundResumeRecoveryTask?.cancel()
        appBackgroundResumeRecoveryTask = nil
        seekRecoveryWatchdogTask?.cancel()
        seekRecoveryWatchdogTask = nil
        speedBoostRecoveryTask?.cancel()
        speedBoostRecoveryTask = nil
        surfaceReadinessResetTask?.cancel()
        surfaceReadinessResetTask = nil
        surfaceReadinessConfirmationTask?.cancel()
        surfaceReadinessConfirmationTask = nil
        surfaceLayoutStabilizationTask?.cancel()
        surfaceLayoutStabilizationTask = nil
        surfaceMigrationTask?.cancel()
        surfaceMigrationTask = nil
        pictureInPictureStartRetryTask?.cancel()
        pictureInPictureStartRetryTask = nil
        pictureInPictureStartRetryGeneration &+= 1
        audioSessionCancellables.removeAll()
        sponsorBlockSkipReportTasks.values.forEach { $0.cancel() }
        sponsorBlockSkipReportTasks.removeAll()
        onPlaybackFailure = nil
        onPlaybackFailureWithReason = nil
        onFirstFramePresented = nil
        onPlaybackEnded = nil
        onNextTrackRequested = nil
        onPreviousTrackRequested = nil
        timeObserver?.invalidate()
        let engine = engine
        Task { @MainActor in
            engine.onPlaybackStateChange = nil
            engine.onPlaybackIntentChange = nil
            engine.onLoadingProgressChange = nil
            engine.onFirstFrame = nil
            engine.stop()
            engine.setViewModel(nil)
        }
    }

    private func configureAudioSessionNotificationsIfNeeded() {
        guard playbackContentMode == .audioOnly else { return }
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                self?.handleAudioSessionInterruption(notification)
            }
            .store(in: &audioSessionCancellables)

        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                self?.handleAudioRouteChange(notification)
            }
            .store(in: &audioSessionCancellables)

        NotificationCenter.default.publisher(for: AVAudioSession.mediaServicesWereResetNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleAudioMediaServicesReset()
            }
            .store(in: &audioSessionCancellables)
    }

    private func handleAudioSessionInterruption(_ notification: Notification) {
        guard playbackContentMode == .audioOnly,
              let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType)
        else { return }

        switch type {
        case .began:
            let hadPlaybackIntent = wantsAutoplay || isPlaying || playbackSnapshot().isPlaying
            let shouldPause = audioInterruptionState.begin(hadPlaybackIntent: hadPlaybackIntent)
            recordAudioSessionEvent("interruption=began resumeIntent=\(hadPlaybackIntent)")
            if shouldPause {
                pause(retainingAppBackgroundResumeIntent: false)
            }
        case .ended:
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            let systemAllowsResume = options.contains(.shouldResume)
            let shouldResume = audioInterruptionState.end(systemAllowsResume: systemAllowsResume)
            let didReactivate = shouldResume
                ? reactivateAudioSessionForListenPlayback()
                : true
            recordAudioSessionEvent(
                "interruption=ended systemAllowsResume=\(systemAllowsResume) resume=\(shouldResume) sessionActive=\(didReactivate)"
            )
            if shouldResume {
                play()
            }
        @unknown default:
            audioInterruptionState.reset()
        }
    }

    private func handleAudioRouteChange(_ notification: Notification) {
        guard playbackContentMode == .audioOnly,
              let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              AVAudioSession.RouteChangeReason(rawValue: rawReason) == .oldDeviceUnavailable,
              let previousRoute = notification.userInfo?[AVAudioSessionRouteChangePreviousRouteKey]
                as? AVAudioSessionRouteDescription,
              previousRoute.outputs.contains(where: { Self.isPrivateListeningPort($0.portType) })
        else { return }
        audioInterruptionState.reset()
        recordAudioSessionEvent("route=oldDeviceUnavailable action=pause")
        pause()
    }

    private func handleAudioMediaServicesReset() {
        guard playbackContentMode == .audioOnly, !isTerminated else { return }
        let shouldResume = wantsAutoplay
            || isPlaying
            || playbackSnapshot().isPlaying
            || audioInterruptionState.shouldResume
        audioInterruptionState.reset()
        let didReactivate = reactivateAudioSessionForListenPlayback()
        wantsAutoplay = shouldResume
        recordAudioSessionEvent(
            "mediaServices=reset resume=\(shouldResume) sessionActive=\(didReactivate)"
        )
        rebuildMediaAfterPlaybackInterruption(allowsDetachedSurface: true)
    }

    @discardableResult
    private func reactivateAudioSessionForListenPlayback() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
            return true
        } catch {
            recordAudioSessionEvent("sessionActivation=failed error=\(error.localizedDescription)")
            return false
        }
    }

    private func recordAudioSessionEvent(_ message: String) {
        PlayerMetricsLog.record(
            .playbackRecovery,
            metricsID: metricsID,
            title: title,
            message: "listenAudioSession \(message)"
        )
    }

    private static func isPrivateListeningPort(_ portType: AVAudioSession.Port) -> Bool {
        switch portType {
        case .headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
            return true
        default:
            return false
        }
    }

    var canSeek: Bool {
        isSeekable || (duration ?? durationHint ?? 0) > 0
    }

    var isPictureInPictureSupported: Bool {
        playbackContentMode == .video
            && isPictureInPictureEnabled
            && (engine.supportsPictureInPicture
            || (AVPictureInPictureController.isPictureInPictureSupported()
                && (pictureInPictureController != nil || engine.pictureInPictureContentSource() != nil)))
    }

    var usesNativePlaybackControls: Bool {
        engine.usesNativePlaybackControls
    }

    var displayDuration: TimeInterval? {
        duration ?? durationHint
    }

    var isLiveStream: Bool {
        streamSource.isLiveStream
    }

    var playbackContentMode: PlayerPlaybackContentMode {
        streamSource.playbackContentMode
    }

    var isAudioOnlyPlayback: Bool {
        playbackContentMode == .audioOnly
    }

    fileprivate var isNowPlayingLiveStream: Bool {
        isLiveStream
    }

    var nowPlayingArtist: String {
        let trimmedName = authorName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName?.isEmpty == false ? trimmedName! : "CiliCili"
    }

    fileprivate var nowPlayingPlaybackState: MPNowPlayingPlaybackState {
        switch playbackPhase {
        case .ended, .failed:
            return .stopped
        case .playing:
            return .playing
        case .idle:
            return wantsAutoplay ? .playing : .stopped
        default:
            return (wantsAutoplay || isPlaying) ? .playing : .paused
        }
    }

    private var shouldPublishNowPlayingMetadata: Bool {
        PlayerNowPlayingPublicationPolicy.shouldPublish(
            isActive: ActivePlaybackCoordinator.shared.isActive(self),
            wantsAutoplay: wantsAutoplay,
            isPlaying: isPlaying,
            isTerminated: isTerminated,
            hasPlaybackFailure: errorMessage != nil,
            playbackContentMode: playbackContentMode
        )
    }

    var currentProgress: Double {
        playbackClock.progress
    }

    func setTrackNavigationAvailability(hasPrevious: Bool, hasNext: Bool) {
        guard canRequestPreviousTrack != hasPrevious || canRequestNextTrack != hasNext else { return }
        canRequestPreviousTrack = hasPrevious
        canRequestNextTrack = hasNext
        syncRemotePlaybackControls()
    }

    func requestNextTrack() {
        guard canRequestNextTrack else { return }
        onNextTrackRequested?()
    }

    func requestPreviousTrack() {
        guard canRequestPreviousTrack else { return }
        onPreviousTrackRequested?()
    }

    func makePlaybackTransitionSnapshot() -> PlaybackTransitionSnapshot? {
        guard !isTerminated else { return nil }
        if let image = firstUsablePlaybackSnapshotImage(
            currentVideoFrameSnapshotImage(),
            currentSurfaceSnapshotImage()
        ) {
            rememberUsablePlaybackSnapshotImage(image)
            return PlaybackTransitionSnapshot(image: image, isVideoFrame: true)
        }
        guard let image = firstUsablePlaybackSnapshotImage(
            surfaceView?.makePlaybackTransitionSnapshotImage(),
            lastUsablePlaybackSnapshotImage
        ) else { return nil }
        rememberUsablePlaybackSnapshotImage(image)
        return PlaybackTransitionSnapshot(image: image, isVideoFrame: false)
    }

    func makeCurrentVideoFrameTransitionSnapshot() -> PlaybackTransitionSnapshot? {
        guard !isTerminated else { return nil }
        if let image = firstUsablePlaybackSnapshotImage(
            currentVideoFrameSnapshotImage(),
            currentSurfaceSnapshotImage()
        ) {
            rememberUsablePlaybackSnapshotImage(image)
            return PlaybackTransitionSnapshot(image: image, isVideoFrame: true)
        }
        guard let image = firstUsablePlaybackSnapshotImage(
            surfaceView?.makePlaybackTransitionSnapshotImage(),
            lastUsablePlaybackSnapshotImage
        ) else { return nil }
        rememberUsablePlaybackSnapshotImage(image)
        return PlaybackTransitionSnapshot(image: image, isVideoFrame: false)
    }

    func makeCurrentVisibleSurfaceTransitionSnapshot() -> PlaybackTransitionSnapshot? {
        guard !isTerminated else { return nil }
        guard let image = firstUsablePlaybackSnapshotImage(
            currentSurfaceSnapshotImage(),
            surfaceView?.makePlaybackTransitionSnapshotImage()
        ) else { return nil }
        rememberUsablePlaybackSnapshotImage(image)
        return PlaybackTransitionSnapshot(image: image, isVideoFrame: false)
    }

    func isSeekRecoverySnapshotReadyForReveal() -> Bool {
        guard !isTerminated else { return false }
        let snapshot = engine.snapshot(durationHint: durationHint)
        if let targetTime = pendingUserSeekRevealTargetTime {
            let pending = userSeekRevealMetric(targetTime: targetTime)
            return isSeekRecoveryFrameReadyForReveal(pending: pending, snapshot: snapshot)
                || hasSeekRecoveryPausedTargetFrameForReveal(pending: pending, snapshot: snapshot)
        }
        guard let pending = pendingSeekRecoveryMetric else {
            return makeCurrentVisibleSurfaceTransitionSnapshot() != nil
        }
        return isSeekRecoveryFrameReadyForReveal(pending: pending, snapshot: snapshot)
            || hasSeekRecoveryPausedTargetFrameForReveal(pending: pending, snapshot: snapshot)
    }

    func makePlaybackTransitionSnapshotView() -> UIView? {
        guard !isTerminated else { return nil }
        if let imageView = makeCurrentVideoFrameSnapshotView() {
            imageView.frame = surfaceView?.bounds ?? CGRect(origin: .zero, size: imageView.bounds.size)
            return imageView
        }
        return surfaceView?.makePlaybackTransitionSnapshotView()
    }

    func makeCurrentVideoFrameSnapshotView() -> UIView? {
        guard !isTerminated else { return nil }
        guard let image = firstUsablePlaybackSnapshotImage(
            currentVideoFrameSnapshotImage(),
            currentSurfaceSnapshotImage()
        )
        else { return nil }
        rememberUsablePlaybackSnapshotImage(image)
        let imageView = UIImageView(image: image)
        imageView.backgroundColor = .black
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.isOpaque = true
        imageView.frame = CGRect(origin: .zero, size: image.size)
        return imageView
    }

    private func currentVideoFrameSnapshotImage() -> UIImage? {
        guard !isTerminated else { return nil }
        return engine.currentVideoFrameImage()
    }

    private func currentSurfaceSnapshotImage() -> UIImage? {
        guard !isTerminated else { return nil }
        return engine.currentSurfaceSnapshotImage()
    }

    private func firstUsablePlaybackSnapshotImage(_ images: UIImage?...) -> UIImage? {
        for image in images {
            guard let image, !image.biliLooksLikeBlackFrame else { continue }
            return image
        }
        return nil
    }

    private func hasVisibleSeekRecoveryFrame(
        pending: PendingSeekRecoveryMetric,
        snapshot: PlayerPlaybackSnapshot
    ) -> Bool {
        if let renderedVideoTime = snapshot.renderedVideoTime {
            guard isSeekRecoveryMatch(currentTime: renderedVideoTime, pending: pending) else {
                return false
            }
            return hasVisibleSeekRecoveryFrame()
        }

        if snapshot.requiresRenderedVideoTimeForRecovery {
            return false
        }

        return hasVisibleSeekRecoveryFrame()
    }

    private func hasVisibleSeekRecoveryFrame() -> Bool {
        let surfaceImage = currentSurfaceSnapshotImage()
        if let image = firstUsablePlaybackSnapshotImage(surfaceImage) {
            rememberUsablePlaybackSnapshotImage(image)
            return true
        }

        // If the current drawable surface is capturable but black, do not trust the
        // cached video frame: it may still be the frame from before the seek.
        guard surfaceImage == nil else { return false }

        if let image = firstUsablePlaybackSnapshotImage(
            surfaceView?.makePlaybackTransitionSnapshotImage(),
            currentVideoFrameSnapshotImage()
        ) {
            rememberUsablePlaybackSnapshotImage(image)
            return true
        }
        return false
    }

    private func rememberUsablePlaybackSnapshotImage(_ image: UIImage) {
        guard !image.biliLooksLikeBlackFrame else { return }
        lastUsablePlaybackSnapshotImage = image
    }

    func attachSurface(
        _ view: VideoSurfaceContainerView,
        prefersNativePlaybackControls: Bool = true,
        preservesReadinessDuringSurfaceHandoff: Bool = false
    ) {
        guard !isTerminated else {
            view.setNativePlaybackControllerEnabled(false)
            return
        }
        self.prefersNativePlaybackControls = prefersNativePlaybackControls
        surfaceReadinessResetTask?.cancel()
        surfaceReadinessResetTask = nil
        let isNewSurface = surfaceView !== view
        let usesNativePlaybackControls = engine.usesNativePlaybackControls && prefersNativePlaybackControls
        let shouldAttachDirectSurface = !usesNativePlaybackControls && nativePlaybackController != nil
        if isNewSurface || shouldAttachDirectSurface {
            PlayerMetricsLog.diagnostic(
                "surface attach view=\(ObjectIdentifier(view).hashValue) isNew=\(isNewSurface) preserve=\(preservesReadinessDuringSurfaceHandoff) hasPresented=\(hasPresentedPlayback) ready=\(isPlaybackSurfaceReady) currentReady=\(isCurrentPlaybackSurfaceReadyForDisplay) engineHasMedia=\(engine.hasMedia)"
            )
#if DEBUG
            onVideoDetailPlaybackDiagnosticSurfaceEvent?(
                .attached(
                    surfaceID: ObjectIdentifier(view),
                    playerID: debugAVPlayerIdentity,
                    playerItemID: debugAVPlayerItemIdentity
                )
            )
#endif
            surfaceAttachmentGeneration &+= 1
            if shouldPreservePlaybackReadinessDuringSurfaceHandoff(preservesReadinessDuringSurfaceHandoff) {
                currentPlaybackSurfaceReadyGeneration = surfaceAttachmentGeneration
                isCurrentPlaybackSurfaceReadyForDisplay = true
            } else {
                currentPlaybackSurfaceReadyGeneration = nil
                isCurrentPlaybackSurfaceReadyForDisplay = false
            }
        }
        surfaceView = view
        view.setNativePlaybackControllerEnabled(usesNativePlaybackControls)
        if usesNativePlaybackControls {
            let controller = view.nativePlayerViewController
            nativePlaybackController = controller
            controller.delegate = self
            engine.attachNativePlaybackController(controller)
            applyPictureInPicturePreferenceToNativePlaybackController()
        } else {
            if let nativePlaybackController {
                engine.detachNativePlaybackController(nativePlaybackController)
                self.nativePlaybackController = nil
            }
            engine.detachNativePlaybackController(view.nativePlayerViewController)
        }
        if isNewSurface || shouldAttachDirectSurface {
            engine.attachSurface(view.drawableView)
        }
        view.setPictureInPictureEnabled(isPictureInPictureEnabled)
        configurePictureInPictureIfNeeded()
        if (isNewSurface || shouldAttachDirectSurface), engine.hasMedia {
            engine.refreshSurfaceLayout()
        }
        markSurfaceLayoutRefreshed()
        if isNewSurface || shouldAttachDirectSurface {
            scheduleCurrentSurfaceReadinessConfirmationIfNeeded(generation: surfaceAttachmentGeneration)
            schedulePendingEngineFirstFrameConsumptionIfNeeded(generation: surfaceAttachmentGeneration)
            schedulePlaybackActivationAfterSurfaceAttachIfNeeded(generation: surfaceAttachmentGeneration)
            stabilizeSurfaceLayoutAfterGeometryChange()
        }
    }

    func attachNativePlaybackController(_ controller: AVPlayerViewController) {
        guard !isTerminated else { return }
        if nativePlaybackController !== controller {
            nativePlaybackController?.delegate = nil
            isNativePictureInPictureActive = false
        }
        nativePlaybackController = controller
        controller.delegate = self
        engine.attachNativePlaybackController(controller)
        applyPictureInPicturePreferenceToNativePlaybackController()
        configurePictureInPictureIfNeeded()
        if engine.hasMedia {
            engine.refreshSurfaceLayout()
        }
    }

    func detachNativePlaybackController(_ controller: AVPlayerViewController) {
        if !isTerminated {
            engine.detachNativePlaybackController(controller)
        }
        if nativePlaybackController === controller {
            controller.delegate = nil
            nativePlaybackController = nil
            isNativePictureInPictureActive = false
            syncPictureInPictureState()
        }
    }

    func setVideoGravity(_ gravity: AVLayerVideoGravity) {
        guard !isTerminated else { return }
        guard currentVideoGravity != gravity else { return }
        currentVideoGravity = gravity
        engine.setVideoGravity(gravity)
        engine.refreshSurfaceLayout()
        markSurfaceLayoutRefreshed()
    }

    func setContentOverlay(_ overlay: AnyView?) {
        guard !isTerminated else { return }
        engine.setContentOverlay(overlay)
        engine.refreshSurfaceLayout()
        markSurfaceLayoutRefreshed()
    }

    func setDanmakuControls(
        isEnabled: Bool,
        onToggle: (() -> Void)?,
        onShowSettings: (() -> Void)?
    ) {
        guard !isTerminated else { return }
        engine.setDanmakuControls(
            isEnabled: isEnabled,
            onToggle: onToggle,
            onShowSettings: onShowSettings
        )
    }

    func setQualityControls(_ controls: PlayerQualityControls?) {
        guard !isTerminated else { return }
        engine.setQualityControls(controls)
    }

    private func installPlaybackHandoffSnapshot(
        on hostView: UIView,
        fallbackView: UIView?,
        fadeDelay: TimeInterval,
        fadeDuration: TimeInterval
    ) {
        guard let snapshotView = makePlaybackHandoffSnapshotView(fallbackView: fallbackView) else { return }
        snapshotView.frame = hostView.bounds
        snapshotView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        snapshotView.isUserInteractionEnabled = false
        snapshotView.alpha = 1
        snapshotView.backgroundColor = .black
        hostView.addSubview(snapshotView)
        hostView.bringSubviewToFront(snapshotView)

        let delayNanoseconds = UInt64(max(fadeDelay, 0) * 1_000_000_000)
        Task { @MainActor [weak snapshotView] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard let snapshotView, snapshotView.superview != nil else { return }
            UIView.animate(withDuration: fadeDuration, delay: 0, options: [.curveEaseOut]) {
                snapshotView.alpha = 0
            } completion: { _ in
                snapshotView.removeFromSuperview()
            }
        }
    }

    private func makePlaybackHandoffSnapshotView(fallbackView: UIView?) -> UIView? {
        if let imageView = makeCurrentVideoFrameSnapshotView() {
            return imageView
        }

        guard let fallbackView,
              let snapshotView = fallbackView.snapshotView(afterScreenUpdates: false)
        else { return nil }
        snapshotView.backgroundColor = .black
        snapshotView.isOpaque = true
        return snapshotView
    }

    func detachSurface(
        _ view: VideoSurfaceContainerView,
        preservesReadinessDuringSurfaceHandoff: Bool = false
    ) {
        guard surfaceView === view else { return }
        PlayerMetricsLog.diagnostic(
            "surface detach view=\(ObjectIdentifier(view).hashValue) preserve=\(preservesReadinessDuringSurfaceHandoff) hasPresented=\(hasPresentedPlayback) ready=\(isPlaybackSurfaceReady) currentReady=\(isCurrentPlaybackSurfaceReadyForDisplay) engineHasMedia=\(engine.hasMedia)"
        )
#if DEBUG
        onVideoDetailPlaybackDiagnosticSurfaceEvent?(
            .detached(
                surfaceID: ObjectIdentifier(view),
                playerID: debugAVPlayerIdentity,
                playerItemID: debugAVPlayerItemIdentity
            )
        )
#endif
        surfaceAttachmentGeneration &+= 1
        surfaceReadinessConfirmationTask?.cancel()
        surfaceReadinessConfirmationTask = nil
        surfaceLayoutStabilizationTask?.cancel()
        surfaceLayoutStabilizationTask = nil
        if shouldPreservePlaybackReadinessDuringSurfaceHandoff(preservesReadinessDuringSurfaceHandoff) {
            currentPlaybackSurfaceReadyGeneration = surfaceAttachmentGeneration
            isCurrentPlaybackSurfaceReadyForDisplay = true
            scheduleSurfaceReadinessResetIfNeeded(
                generation: surfaceAttachmentGeneration,
                delayNanoseconds: Self.surfaceHandoffReadinessResetDelayNanoseconds
            )
        } else {
            currentPlaybackSurfaceReadyGeneration = nil
            isCurrentPlaybackSurfaceReadyForDisplay = false
            scheduleSurfaceReadinessResetIfNeeded(generation: surfaceAttachmentGeneration)
        }
        playbackRecoveryWatchdogTask?.cancel()
        playbackRecoveryWatchdogTask = nil
        if !isTerminated {
            engine.setContentOverlay(nil)
            engine.setDanmakuControls(isEnabled: false, onToggle: nil, onShowSettings: nil)
            engine.setQualityControls(nil)
            engine.detachNativePlaybackController(view.nativePlayerViewController)
            engine.detachSurface(view.drawableView)
        }
        view.setNativePlaybackControllerEnabled(false)
        if nativePlaybackController === view.nativePlayerViewController {
            nativePlaybackController?.delegate = nil
            nativePlaybackController = nil
            isNativePictureInPictureActive = false
        }
        surfaceView = nil
    }

    func beginSurfaceMigrationHold() {
        guard !isTerminated, hasPresentedPlayback, engine.hasMedia else { return }
        isSurfaceMigrating = true
        surfaceMigrationTask?.cancel()
        surfaceMigrationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.surfaceMigrationHoldNanoseconds)
            guard let self, !Task.isCancelled else { return }
            self.isSurfaceMigrating = false
            self.surfaceMigrationTask = nil
        }
    }

    func endSurfaceMigrationHold() {
        surfaceMigrationTask?.cancel()
        surfaceMigrationTask = nil
        isSurfaceMigrating = false
    }

    private func shouldPreservePlaybackReadinessDuringSurfaceHandoff(_ requested: Bool) -> Bool {
        requested
            && hasPresentedPlayback
            && isPlaybackSurfaceReady
            && engine.hasMedia
            && errorMessage == nil
            && !isTerminated
    }

    private func scheduleSurfaceReadinessResetIfNeeded(
        generation: Int,
        delayNanoseconds: UInt64 = 180_000_000
    ) {
        surfaceReadinessResetTask?.cancel()
        guard hasPresentedPlayback, isPlaybackSurfaceReady else {
            isPlaybackSurfaceReady = false
            currentPlaybackSurfaceReadyGeneration = nil
            isCurrentPlaybackSurfaceReadyForDisplay = false
            surfaceReadinessResetTask = nil
            return
        }
        surfaceReadinessResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard let self,
                  !Task.isCancelled,
                  !self.isTerminated,
                  self.surfaceAttachmentGeneration == generation,
                  self.surfaceView == nil
            else { return }
            self.isPlaybackSurfaceReady = false
            self.currentPlaybackSurfaceReadyGeneration = nil
            self.isCurrentPlaybackSurfaceReadyForDisplay = false
            self.surfaceReadinessResetTask = nil
        }
    }

    private func scheduleCurrentSurfaceReadinessConfirmationIfNeeded(generation: Int) {
        surfaceReadinessConfirmationTask?.cancel()
        guard hasPresentedPlayback,
              isPlaybackSurfaceReady,
              hasCurrentSurface(generation: generation)
        else {
            surfaceReadinessConfirmationTask = nil
            return
        }

        if confirmCurrentSurfaceReady(generation: generation) {
            surfaceReadinessConfirmationTask = nil
            return
        }

        surfaceReadinessConfirmationTask = Task { @MainActor [weak self] in
            defer { self?.clearSurfaceReadinessConfirmationTaskIfCurrent(generation: generation) }
            for delay in Self.currentSurfaceReadinessConfirmationDelays {
                try? await Task.sleep(nanoseconds: delay)
                guard let self,
                      !Task.isCancelled,
                      !self.isTerminated,
                      self.hasCurrentSurface(generation: generation),
                      self.hasPresentedPlayback,
                      self.isPlaybackSurfaceReady
                else { return }

                self.refreshSurfaceLayout()
                if self.confirmCurrentSurfaceReady(generation: generation) {
                    return
                }
            }

            guard let self,
                  !Task.isCancelled,
                  !self.isTerminated,
                  self.hasCurrentSurface(generation: generation),
                  self.hasPresentedPlayback,
                  self.isPlaybackSurfaceReady
            else { return }
            self.refreshSurfaceLayout()
            _ = self.confirmCurrentSurfaceReady(generation: generation)
        }
    }

    private func confirmCurrentSurfaceReady(generation: Int) -> Bool {
        guard !isAwaitingAppBackgroundSurfaceRecovery,
              hasCurrentSurface(generation: generation)
        else { return false }
        if let image = firstUsablePlaybackSnapshotImage(
            currentSurfaceSnapshotImage(),
            surfaceView?.makePlaybackTransitionSnapshotImage(),
            currentVideoFrameSnapshotImage()
        ) {
            rememberUsablePlaybackSnapshotImage(image)
        } else if canTrustCurrentPlaybackSurfaceWithoutSnapshot(generation: generation) {
            PlayerMetricsLog.diagnostic(
                "surface ready trustedWithoutSnapshot generation=\(generation) hasPresented=\(hasPresentedPlayback) ready=\(isPlaybackSurfaceReady) phase=\(playbackPhase)"
            )
        } else {
            return false
        }
        currentPlaybackSurfaceReadyGeneration = generation
        isCurrentPlaybackSurfaceReadyForDisplay = true
        return true
    }

    private func canTrustCurrentPlaybackSurfaceWithoutSnapshot(generation: Int) -> Bool {
        hasCurrentSurface(generation: generation)
            && hasPresentedPlayback
            && isPlaybackSurfaceReady
            && engine.hasMedia
            && errorMessage == nil
            && !isPreparing
            && playbackPhase != .waitingForFirstFrame
    }

    @discardableResult
    func validateCurrentPlaybackSurfaceReadyForDisplay() -> Bool {
        guard !isTerminated, surfaceView != nil else {
            currentPlaybackSurfaceReadyGeneration = nil
            isCurrentPlaybackSurfaceReadyForDisplay = false
            return false
        }
        if confirmCurrentSurfaceReady(generation: surfaceAttachmentGeneration) {
            return true
        }
        currentPlaybackSurfaceReadyGeneration = nil
        isCurrentPlaybackSurfaceReadyForDisplay = false
        return false
    }

    func validateCurrentPlaybackSurfaceReadyForReveal() -> Bool {
        guard !isTerminated, surfaceView != nil else { return false }
        if makeCurrentVisibleSurfaceTransitionSnapshot() != nil {
            currentPlaybackSurfaceReadyGeneration = surfaceAttachmentGeneration
            isCurrentPlaybackSurfaceReadyForDisplay = true
            PlayerMetricsLog.diagnostic(
                "surface reveal visibleSnapshot generation=\(surfaceAttachmentGeneration) layoutGeneration=\(surfaceLayoutGeneration)"
            )
            return true
        }

        guard canTrustCurrentPlaybackSurfaceWithoutSnapshot(generation: surfaceAttachmentGeneration) else {
            return false
        }

        let now = DispatchTime.now().uptimeNanoseconds
        guard now >= currentSurfaceRevealHoldUntilNanoseconds else {
            return false
        }

        currentPlaybackSurfaceReadyGeneration = surfaceAttachmentGeneration
        isCurrentPlaybackSurfaceReadyForDisplay = true
        PlayerMetricsLog.diagnostic(
            "surface reveal trustedAfterSettle generation=\(surfaceAttachmentGeneration) layoutGeneration=\(surfaceLayoutGeneration) phase=\(playbackPhase)"
        )
        return true
    }

    private func clearSurfaceReadinessConfirmationTaskIfCurrent(generation: Int) {
        guard hasCurrentSurface(generation: generation) else { return }
        surfaceReadinessConfirmationTask = nil
    }

    func refreshSurfaceLayout() {
        guard !isTerminated, surfaceView != nil else { return }
        engine.refreshSurfaceLayout()
        markSurfaceLayoutRefreshed()
    }

    func stabilizeSurfaceLayoutAfterGeometryChange() {
        guard !isTerminated, surfaceView != nil else { return }
        holdCurrentSurfaceRevealForGeometrySettle()
        surfaceLayoutStabilizationTask?.cancel()
        let generation = surfaceAttachmentGeneration
        surfaceLayoutStabilizationTask = Task { @MainActor [weak self] in
            defer {
                if self?.surfaceAttachmentGeneration == generation {
                    self?.surfaceLayoutStabilizationTask = nil
                }
            }
            for delay in Self.surfaceLayoutStabilizationDelays {
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                } else {
                    await Task.yield()
                }
                guard let self,
                      !Task.isCancelled,
                      !self.isTerminated,
                      self.hasCurrentSurface(generation: generation)
                else { return }
                self.refreshSurfaceLayout()
            }
        }
    }

    private func holdCurrentSurfaceRevealForGeometrySettle() {
        let holdUntil = DispatchTime.now().uptimeNanoseconds
            + Self.currentSurfaceRevealSettleDelayNanoseconds
        currentSurfaceRevealHoldUntilNanoseconds = max(
            currentSurfaceRevealHoldUntilNanoseconds,
            holdUntil
        )
    }

    private func hasCurrentSurface(generation: Int) -> Bool {
        surfaceAttachmentGeneration == generation && surfaceView != nil
    }

    private func canActivatePlayback() -> Bool {
        !isTerminated
            && surfaceView != nil
            && hasPlaybackActivationAuthority
            && allowsPlaybackInCurrentApplicationState
    }

    private func canActivatePlayback(generation: Int) -> Bool {
        !isTerminated
            && hasCurrentSurface(generation: generation)
            && hasPlaybackActivationAuthority
            && allowsPlaybackInCurrentApplicationState
    }

    private var hasPlaybackActivationAuthority: Bool {
        ActivePlaybackCoordinator.shared.isActive(self) || hasPendingSeamlessPlaybackHandoff
    }

    private var hasPendingSeamlessPlaybackHandoff: Bool {
        guard let source = seamlessPlaybackHandoffSource else { return false }
        return source !== self && !source.isTerminated
    }

    private var allowsPlaybackInCurrentApplicationState: Bool {
        playbackContentMode == .audioOnly
            || UIApplication.shared.applicationState == .active
            || isPictureInPictureActive
    }

    private func markSurfaceLayoutRefreshed() {
        guard surfaceView != nil else { return }
        surfaceLayoutGeneration &+= 1
    }

    func playbackSnapshot() -> PlayerPlaybackSnapshot {
        engine.snapshot(durationHint: duration ?? durationHint)
    }

    func preferVideoRenditionInCurrentItem(_ variant: PlayVariant) -> Bool {
        guard streamSource.audioURL == variant.audioURL,
              streamSource.dynamicRange == variant.dynamicRange,
              Self.videoCodecFamily(streamSource.videoStream) == Self.videoCodecFamily(variant.videoStream),
              let videoURL = variant.videoURL,
              currentHLSVideoRenditionURLs.contains(videoURL),
              let bandwidth = variant.videoStream?.bandwidth ?? variant.bandwidth,
              bandwidth > 0
        else { return false }
        let multiplier = PlaybackEnvironment.current.shouldPreferConservativePlayback ? 0.96 : 1.08
        engine.setPreferredPeakBitRate(Double(bandwidth) * multiplier)
        PlayerMetricsLog.record(
            .qualitySupplement,
            metricsID: metricsID,
            title: title,
            message: "manualInPlace q\(variant.quality) peak=\(Int((Double(bandwidth) * multiplier).rounded()))"
        )
        return true
    }

    private var currentHLSVideoRenditionURLs: Set<URL> {
        var urls = Set<URL>()
        if let videoURL = streamSource.videoURL {
            urls.insert(videoURL)
        }
        streamSource.alternateVideoRenditions.forEach { urls.insert($0.videoURL) }
        return urls
    }

    private static func videoCodecFamily(_ stream: DASHStream?) -> String? {
        if let codecid = stream?.codecid {
            switch codecid {
            case 7:
                return "avc"
            case 12:
                return "hevc"
            case 13:
                return "av1"
            default:
                break
            }
        }

        let codec = (stream?.codecs ?? "").lowercased()
        if codec.contains("avc1") || codec.contains("avc3") {
            return "avc"
        }
        if codec.contains("hvc1") || codec.contains("hev1") || codec.contains("dvh1") || codec.contains("dvhe") {
            return "hevc"
        }
        if codec.contains("av01") {
            return "av1"
        }
        return nil
    }

    func recoverPlaybackAfterAppResume() {
        guard !isTerminated else { return }
        guard ActivePlaybackCoordinator.shared.isActive(self) else { return }
        let baselineSurfaceGeneration = surfaceAttachmentGeneration
        if timeObserver == nil {
            startTimeObserver()
        }

        if hasCurrentSurface(generation: baselineSurfaceGeneration) {
            engine.recoverSurface()
            refreshSurfaceLayout()
        }
        configurePictureInPictureIfNeeded()
        invalidatePictureInPicturePlaybackState()
        schedulePlaybackRecoveryWatchdog(reason: hasPresentedPlayback ? .stall : .firstFrame)

        guard errorMessage == nil else { return }
        if engine.needsMediaRecovery {
            rebuildMediaAfterPlaybackInterruption()
            return
        }
        guard engine.hasMedia else {
            if wantsAutoplay {
                prepareMediaAndPlay()
            }
            return
        }
        if wantsAutoplay {
            startPreparedPlayback()
        } else {
            refreshPlaybackState()
        }
    }

    func preservePlaybackThroughTransientSystemOverlay() {
        guard !isTerminated else { return }
        guard ActivePlaybackCoordinator.shared.isActive(self) else { return }
        syncPictureInPictureState()
        guard !isPictureInPictureActive else { return }
        let snapshot = playbackSnapshot()
        let wasPlaying = wantsAutoplay || isPlaying || snapshot.isPlaying
        let shouldResume = shouldResumeAfterTransientSystemOverlay || wasPlaying
        shouldResumeAfterTransientSystemOverlay = shouldResumeAfterTransientSystemOverlay || shouldResume
        guard wasPlaying else { return }
        pause()
    }

    @discardableResult
    func recoverPlaybackAfterTransientSystemOverlayIfNeeded() -> Bool {
        let shouldResume = shouldResumeAfterTransientSystemOverlay
        shouldResumeAfterTransientSystemOverlay = false
        guard shouldResume else { return false }
        wantsAutoplay = true
        recoverPlaybackAfterAppResume()
        return true
    }

    func cancelTransientSystemOverlayPlaybackPreservation() {
        shouldResumeAfterTransientSystemOverlay = false
    }

    @discardableResult
    func pauseForAppBackground() -> Bool {
        guard !isTerminated else { return false }
        guard ActivePlaybackCoordinator.shared.isActive(self) else { return false }
        syncPictureInPictureState()
        guard !isPictureInPictureActive else { return false }
        if playbackContentMode == .audioOnly {
            syncRemotePlaybackControls(forceNowPlayingTimeUpdate: true)
            return false
        }

        // Recorded video should not pretend to keep playing when iOS has moved
        // the app off screen. Leave live playback on the existing resume path,
        // but make normal video an explicit manual restart after foregrounding.
        if !isLiveStream {
            if isPlaybackStoppedForAppBackground {
                return true
            }
            let snapshot = playbackSnapshot()
            let shouldStop = wantsAutoplay
                || isPlaying
                || isPreparing
                || snapshot.isPlaying
                || engine.hasMedia
            guard shouldStop else {
                appBackgroundPlaybackRestoreTime = nil
                cancelAppBackgroundSurfaceRecovery()
                return false
            }

            let snapshotTime = snapshot.currentTime ?? currentTime
            let restoreTime = snapshotTime.isFinite ? max(snapshotTime, 0) : nil
            isPlaybackStoppedForAppBackground = true
            didPrepareStoppedAppBackgroundPlayback = false
            appBackgroundPlaybackRestoreTime = restoreTime
            beginAppBackgroundSurfaceRecovery(at: restoreTime)
            pause(
                retainingAppBackgroundResumeIntent: false,
                usesAppBackgroundPause: true,
                preservesAppBackgroundSurfaceRecovery: true
            )
            PlayerMetricsLog.record(
                .resumeDecision,
                metricsID: metricsID,
                title: title,
                message: "appBackgroundStop mode=manual time=\(String(format: "%.2fs", restoreTime ?? currentTime))"
            )
            return true
        }

        if shouldResumePlaybackAfterAppBackground {
            let snapshot = playbackSnapshot()
            if wantsAutoplay || isPlaying || snapshot.isPlaying {
                pause(retainingAppBackgroundResumeIntent: true)
            }
            return true
        }
        let snapshot = playbackSnapshot()
        let shouldResume = wantsAutoplay
            || isPlaying
            || snapshot.isPlaying
        guard shouldResume else {
            appBackgroundPlaybackRestoreTime = nil
            cancelAppBackgroundSurfaceRecovery()
            return false
        }
        let snapshotTime = snapshot.currentTime ?? currentTime
        let restoreTime = snapshotTime.isFinite ? max(snapshotTime, 0) : nil
        appBackgroundPlaybackRestoreTime = restoreTime
        beginAppBackgroundSurfaceRecovery(at: restoreTime)
        shouldResumePlaybackAfterAppBackground = true
        pause(retainingAppBackgroundResumeIntent: true)
        return true
    }

    @discardableResult
    func prepareStoppedPlaybackAfterAppBackgroundIfNeeded() -> Bool {
        guard isPlaybackStoppedForAppBackground else { return false }
        guard !isTerminated,
              ActivePlaybackCoordinator.shared.isActive(self)
        else { return false }
        syncPictureInPictureState()
        guard !isPictureInPictureActive else { return false }
        guard !didPrepareStoppedAppBackgroundPlayback else { return true }
        didPrepareStoppedAppBackgroundPlayback = true

        if timeObserver == nil {
            startTimeObserver()
        }
        let restoreTime = max(
            appBackgroundPlaybackRestoreTime
                ?? engine.snapshot(durationHint: durationHint).currentTime
                ?? currentTime,
            0
        )
        if restoreTime > 0.25 {
            updatePlaybackTime(restoreTime, force: true, countsAsNaturalPlayback: false)
        }
        guard !engine.needsMediaRecovery, engine.hasMedia else {
            PlayerMetricsLog.record(
                .playbackRecovery,
                metricsID: metricsID,
                title: title,
                message: "stage=foregroundPausedMediaRebuild status=started target=\(String(format: "%.2fs", restoreTime))"
            )
            rebuildMediaAfterPlaybackInterruption()
            return true
        }

        let didRefreshVideoOutput = engine.refreshVideoOutputForPlaybackRecovery()
        let restoredTime = engine.seek(toTime: restoreTime) ?? restoreTime
        let didWarmPausedPlayback = engine.warmPausedPlaybackForRecovery()
        refreshSurfaceLayout()

        // Keep the existing AVPlayerItem and its buffered ranges whenever the
        // engine can refresh or preroll it. Replacing the item here discards the
        // useful media that survived a short lock and moves all startup work to
        // the user's later play tap.
        if !didRefreshVideoOutput, !didWarmPausedPlayback {
            guard let rebuiltTime = engine.rebuildPlayerItemForPlaybackRecovery(at: restoreTime) else {
                PlayerMetricsLog.record(
                    .playbackRecovery,
                    metricsID: metricsID,
                    title: title,
                    message: "stage=foregroundPausedMediaRebuild status=started reason=warm-unavailable target=\(String(format: "%.2fs", restoreTime))"
                )
                rebuildMediaAfterPlaybackInterruption()
                return true
            }
            appBackgroundSurfaceRecoveryBaselineTime = rebuiltTime
            resetAppBackgroundSurfaceRecoverySamples()
            updatePlaybackTime(rebuiltTime, force: true, countsAsNaturalPlayback: false)
            _ = engine.warmPausedPlaybackForRecovery()
            refreshSurfaceLayout()
            PlayerMetricsLog.record(
                .playbackRecovery,
                metricsID: metricsID,
                title: title,
                message: "stage=foregroundPausedPlayerItem status=fallback bridge=reused target=\(String(format: "%.2fs", rebuiltTime))"
            )
            return true
        }

        appBackgroundSurfaceRecoveryBaselineTime = restoredTime
        resetAppBackgroundSurfaceRecoverySamples()
        updatePlaybackTime(restoredTime, force: true, countsAsNaturalPlayback: false)
        PlayerMetricsLog.record(
            .playbackRecovery,
            metricsID: metricsID,
            title: title,
            message: "stage=foregroundPausedWarm status=ready item=retained output=\(didRefreshVideoOutput ? "refreshed" : "unchanged") preroll=\(didWarmPausedPlayback ? "started" : "unavailable") target=\(String(format: "%.2fs", restoredTime))"
        )
        return true
    }

    @discardableResult
    func resumePlaybackAfterAppBackgroundIfNeeded() -> Bool {
        guard shouldResumePlaybackAfterAppBackground else { return false }
        shouldResumePlaybackAfterAppBackground = false
        guard !isTerminated else {
            cancelAppBackgroundSurfaceRecovery()
            return false
        }
        guard ActivePlaybackCoordinator.shared.isActive(self) else {
            cancelAppBackgroundSurfaceRecovery()
            return false
        }
        syncPictureInPictureState()
        guard !isPictureInPictureActive else {
            cancelAppBackgroundSurfaceRecovery()
            return false
        }
        guard errorMessage == nil else {
            cancelAppBackgroundSurfaceRecovery()
            return false
        }

        let restoreTime = max(
            appBackgroundPlaybackRestoreTime
                ?? engine.snapshot(durationHint: durationHint).currentTime
                ?? currentTime,
            0
        )
        appBackgroundPlaybackRestoreTime = nil
        if restoreTime > 0.25 {
            updatePlaybackTime(restoreTime, force: true, countsAsNaturalPlayback: false)
        }
        wantsAutoplay = true
        if timeObserver == nil {
            startTimeObserver()
        }
        if engine.needsMediaRecovery {
            rebuildMediaAfterPlaybackInterruption()
            return true
        }
        guard engine.hasMedia else {
            prepareMediaAndPlay()
            return true
        }

        // A long lock can suspend the decoder while the AVPlayerItem remains ready.
        // Rebind the layer and seek back to the current frame before resuming, which
        // makes AVPlayer request a fresh drawable without changing the media source.
        engine.recoverSurface()
        refreshSurfaceLayout()
        if restoreTime > 0.25,
           let restoredTime = engine.seek(toTime: restoreTime) {
            updatePlaybackTime(restoredTime, force: true, countsAsNaturalPlayback: false)
        }
        startPreparedPlayback()
        scheduleAppBackgroundResumeRecovery(from: restoreTime)
        PlayerMetricsLog.record(
            .resumeDecision,
            metricsID: metricsID,
            title: title,
            message: "appBackgroundResume surface=rebound time=\(String(format: "%.2fs", restoreTime))"
        )
        return true
    }

    func isAppBackgroundSurfaceRecoveryReadyForReveal() -> Bool {
        guard isAwaitingAppBackgroundSurfaceRecovery else {
            return isCurrentPlaybackSurfaceReadyForDisplay
        }
        guard !isTerminated,
              ActivePlaybackCoordinator.shared.isActive(self),
              engine.hasMedia,
              errorMessage == nil,
              surfaceView != nil,
              let renderedTime = engine.currentRenderedVideoTime(),
              renderedTime.isFinite
        else {
            resetAppBackgroundSurfaceRecoverySamples()
            return false
        }

        let baseline = appBackgroundSurfaceRecoveryBaselineTime ?? currentTime
        guard renderedTime >= max(baseline - 0.5, 0) else {
            resetAppBackgroundSurfaceRecoverySamples()
            return false
        }

        if let previousRenderedTime = appBackgroundSurfaceRecoveryLastRenderedTime,
           renderedTime > previousRenderedTime + 0.008 {
            appBackgroundSurfaceRecoveryStableSampleCount += 1
        } else if appBackgroundSurfaceRecoveryLastRenderedTime == nil {
            appBackgroundSurfaceRecoveryStableSampleCount = 1
        }
        appBackgroundSurfaceRecoveryLastRenderedTime = renderedTime
        return appBackgroundSurfaceRecoveryStableSampleCount >= 2
    }

    func isStoppedAppBackgroundSurfaceRecoveryReadyForReveal() -> Bool {
        guard isAwaitingAppBackgroundSurfaceRecovery else {
            return isCurrentPlaybackSurfaceReadyForDisplay
        }
        guard !isTerminated,
              ActivePlaybackCoordinator.shared.isActive(self),
              engine.hasMedia,
              errorMessage == nil,
              surfaceView != nil
        else { return false }

        if makeCurrentVisibleSurfaceTransitionSnapshot() != nil {
            return true
        }
        guard let renderedTime = engine.currentRenderedVideoTime(),
              renderedTime.isFinite
        else { return false }
        let baseline = appBackgroundSurfaceRecoveryBaselineTime ?? currentTime
        return renderedTime >= max(baseline - 0.5, 0)
    }

    func finishAppBackgroundSurfaceRecoveryReveal() {
        guard isAwaitingAppBackgroundSurfaceRecovery else { return }
        isAwaitingAppBackgroundSurfaceRecovery = false
        appBackgroundSurfaceRecoveryBaselineTime = nil
        resetAppBackgroundSurfaceRecoverySamples()
        guard !isTerminated, surfaceView != nil else { return }
        currentPlaybackSurfaceReadyGeneration = surfaceAttachmentGeneration
        isCurrentPlaybackSurfaceReadyForDisplay = true
        isPlaybackSurfaceReady = true
        isPreparing = false
        isBuffering = false
        if wantsAutoplay {
            playbackPhase = .playing
        } else {
            playbackPhase = engine.hasMedia ? .paused : .idle
        }
        PlayerMetricsLog.record(
            .resumeDecision,
            metricsID: metricsID,
            title: title,
            message: "appBackgroundResume surface=visible"
        )
    }

    func cancelAppBackgroundSurfaceRecovery() {
        isAwaitingAppBackgroundSurfaceRecovery = false
        appBackgroundSurfaceRecoveryBaselineTime = nil
        resetAppBackgroundSurfaceRecoverySamples()
    }

    private func beginAppBackgroundSurfaceRecovery(at baselineTime: TimeInterval?) {
        isAwaitingAppBackgroundSurfaceRecovery = hasPresentedPlayback
        appBackgroundSurfaceRecoveryBaselineTime = baselineTime
        resetAppBackgroundSurfaceRecoverySamples()
        guard isAwaitingAppBackgroundSurfaceRecovery else { return }
        currentPlaybackSurfaceReadyGeneration = nil
        isCurrentPlaybackSurfaceReadyForDisplay = false
    }

    private func resetAppBackgroundSurfaceRecoverySamples() {
        appBackgroundSurfaceRecoveryLastRenderedTime = nil
        appBackgroundSurfaceRecoveryStableSampleCount = 0
    }

    private func schedulePlaybackRecoveryWatchdog(reason: PlaybackRecoveryWatchdogReason) {
        guard !isTerminated,
              wantsAutoplay,
              engine.hasMedia,
              errorMessage == nil,
              ActivePlaybackCoordinator.shared.isActive(self)
        else { return }
        guard reason == .stall || !hasPresentedPlayback else { return }

        playbackRecoveryWatchdogTask?.cancel()
        let baselineTime = currentTime
        let baselineAttempt = recoveryAttemptCount
        let baselineMediaPreparationGeneration = mediaPreparationGeneration
        let baselineSurfaceGeneration = surfaceAttachmentGeneration
        let delay = reason.delay(for: streamSource.dynamicRange)
        playbackRecoveryWatchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard let self,
                  !Task.isCancelled,
                  !self.isTerminated,
                  self.wantsAutoplay,
                  self.engine.hasMedia,
                  self.errorMessage == nil,
                  self.mediaPreparationGeneration == baselineMediaPreparationGeneration,
                  self.hasCurrentSurface(generation: baselineSurfaceGeneration),
                  ActivePlaybackCoordinator.shared.isActive(self)
            else { return }

            switch reason {
            case .firstFrame:
                guard !self.hasPresentedPlayback else { return }
            case .stall:
                guard self.isBuffering || self.playbackPhase == .recovering else { return }
                let snapshotTime = self.engine.snapshot(durationHint: self.durationHint).currentTime ?? self.currentTime
                guard abs(snapshotTime - baselineTime) < 0.25 else { return }
            }

            guard self.recoveryAttemptCount == baselineAttempt else { return }
            self.performPlaybackRecovery(
                reason: reason,
                baselineTime: baselineTime,
                surfaceGeneration: baselineSurfaceGeneration
            )
        }
    }

    private func scheduleAppBackgroundResumeRecovery(from baselineTime: TimeInterval) {
        cancelAppBackgroundResumeRecovery()
        let recoveryGeneration = appBackgroundResumeRecoveryGeneration
        let baselineMediaPreparationGeneration = mediaPreparationGeneration
        let baselineSurfaceGeneration = surfaceAttachmentGeneration
        appBackgroundResumeRecoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.appBackgroundResumeRecoveryDelayNanoseconds)
            guard !Task.isCancelled,
                  self.canContinueAppBackgroundResumeRecovery(
                    mediaPreparationGeneration: baselineMediaPreparationGeneration,
                    surfaceGeneration: baselineSurfaceGeneration
                  )
            else {
                self.clearAppBackgroundResumeRecoveryTaskIfCurrent(generation: recoveryGeneration)
                return
            }

            if self.isAppBackgroundSurfaceRecoveryReadyForReveal() {
                self.clearAppBackgroundResumeRecoveryTaskIfCurrent(generation: recoveryGeneration)
                return
            }

            let currentPlaybackTime = self.engine.snapshot(durationHint: self.durationHint).currentTime ?? self.currentTime
            guard self.isAwaitingAppBackgroundSurfaceRecovery
                    || abs(currentPlaybackTime - baselineTime) < 0.25
            else {
                self.clearAppBackgroundResumeRecoveryTaskIfCurrent(generation: recoveryGeneration)
                return
            }

            let didRefreshVideoOutput = self.engine.refreshVideoOutputForPlaybackRecovery()
            self.resetAppBackgroundSurfaceRecoverySamples()
            self.refreshSurfaceLayout()
            if baselineTime > 0.25,
               let restoredTime = self.engine.seek(toTime: baselineTime) {
                self.updatePlaybackTime(restoredTime, force: true, countsAsNaturalPlayback: false)
            }
            if self.canActivatePlayback(generation: baselineSurfaceGeneration) {
                self.engine.play()
                self.engine.setPlaybackRate(self.playbackRate.rawValue)
            }
            PlayerMetricsLog.record(
                .playbackRecovery,
                metricsID: self.metricsID,
                title: self.title,
                message: "stage=videoOutputRefresh status=\(didRefreshVideoOutput ? "applied" : "unavailable") reason=app-background-resume baseline=\(String(format: "%.2fs", baselineTime))"
            )

            try? await Task.sleep(nanoseconds: self.appBackgroundVideoOutputRecoveryGraceDelayNanoseconds)
            guard !Task.isCancelled,
                  self.canContinueAppBackgroundResumeRecovery(
                    mediaPreparationGeneration: baselineMediaPreparationGeneration,
                    surfaceGeneration: baselineSurfaceGeneration
                  )
            else {
                self.clearAppBackgroundResumeRecoveryTaskIfCurrent(generation: recoveryGeneration)
                return
            }

            if self.isAppBackgroundSurfaceRecoveryReadyForReveal() {
                self.clearAppBackgroundResumeRecoveryTaskIfCurrent(generation: recoveryGeneration)
                return
            }

            let playbackTimeAfterRefresh = self.engine.snapshot(durationHint: self.durationHint).currentTime ?? self.currentTime
            guard self.isAwaitingAppBackgroundSurfaceRecovery
                    || abs(playbackTimeAfterRefresh - baselineTime) < 0.25
            else {
                self.clearAppBackgroundResumeRecoveryTaskIfCurrent(generation: recoveryGeneration)
                return
            }

            guard let restoredTime = self.engine.rebuildPlayerItemForPlaybackRecovery(at: baselineTime) else {
                self.startFullAppBackgroundMediaRebuild(
                    reason: "player-item-unavailable",
                    baselineTime: baselineTime,
                    recoveryGeneration: recoveryGeneration
                )
                return
            }
            self.appBackgroundSurfaceRecoveryBaselineTime = restoredTime
            self.resetAppBackgroundSurfaceRecoverySamples()
            self.updatePlaybackTime(restoredTime, force: true, countsAsNaturalPlayback: false)
            self.refreshSurfaceLayout()
            if self.canActivatePlayback(generation: baselineSurfaceGeneration) {
                self.engine.play()
                self.engine.setPlaybackRate(self.playbackRate.rawValue)
            }
            PlayerMetricsLog.record(
                .playbackRecovery,
                metricsID: self.metricsID,
                title: self.title,
                message: "stage=playerItemRebuild status=applied bridge=reused target=\(String(format: "%.2fs", restoredTime))"
            )

            try? await Task.sleep(nanoseconds: self.appBackgroundPlayerItemRecoveryGraceDelayNanoseconds)
            guard !Task.isCancelled,
                  self.canContinueAppBackgroundResumeRecovery(
                    mediaPreparationGeneration: baselineMediaPreparationGeneration,
                    surfaceGeneration: baselineSurfaceGeneration
                  )
            else {
                self.clearAppBackgroundResumeRecoveryTaskIfCurrent(generation: recoveryGeneration)
                return
            }

            if self.isAppBackgroundSurfaceRecoveryReadyForReveal() {
                self.clearAppBackgroundResumeRecoveryTaskIfCurrent(generation: recoveryGeneration)
                return
            }

            let playbackTimeAfterItemRebuild = self.engine.snapshot(durationHint: self.durationHint).currentTime ?? self.currentTime
            guard self.isAwaitingAppBackgroundSurfaceRecovery
                    || abs(playbackTimeAfterItemRebuild - restoredTime) < 0.25
            else {
                self.clearAppBackgroundResumeRecoveryTaskIfCurrent(generation: recoveryGeneration)
                return
            }

            self.startFullAppBackgroundMediaRebuild(
                reason: "player-item-no-frame",
                baselineTime: restoredTime,
                recoveryGeneration: recoveryGeneration
            )
        }
    }

    private func scheduleStoppedAppBackgroundResumeRecovery(from baselineTime: TimeInterval) {
        cancelAppBackgroundResumeRecovery()
        playbackRecoveryWatchdogTask?.cancel()
        playbackRecoveryWatchdogTask = nil
        let recoveryGeneration = appBackgroundResumeRecoveryGeneration
        let baselineMediaPreparationGeneration = mediaPreparationGeneration
        let baselineSurfaceGeneration = surfaceAttachmentGeneration
        let isHDR = streamSource.dynamicRange.isHDR
        let refreshDelay = isHDR ? 1_400_000_000 : stoppedAppBackgroundRefreshDelayNanoseconds
        let itemDelay = isHDR ? 1_800_000_000 : stoppedAppBackgroundPlayerItemDelayNanoseconds
        let mediaDelay = isHDR ? 2_400_000_000 : stoppedAppBackgroundMediaRebuildDelayNanoseconds

        appBackgroundResumeRecoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: refreshDelay)
            guard !Task.isCancelled,
                  self.canContinueAppBackgroundResumeRecovery(
                    mediaPreparationGeneration: baselineMediaPreparationGeneration,
                    surfaceGeneration: baselineSurfaceGeneration
                  )
            else {
                self.clearAppBackgroundResumeRecoveryTaskIfCurrent(generation: recoveryGeneration)
                return
            }
            if self.hasPlaybackAdvancedAfterStoppedBackgroundResume(from: baselineTime) {
                self.clearAppBackgroundResumeRecoveryTaskIfCurrent(generation: recoveryGeneration)
                return
            }

            let didRefreshVideoOutput = self.engine.refreshVideoOutputForPlaybackRecovery()
            self.refreshSurfaceLayout()
            if baselineTime > 0.25,
               let restoredTime = self.engine.seek(toTime: baselineTime) {
                self.updatePlaybackTime(restoredTime, force: true, countsAsNaturalPlayback: false)
            }
            if self.canActivatePlayback(generation: baselineSurfaceGeneration) {
                self.engine.play()
                self.engine.setPlaybackRate(self.playbackRate.rawValue)
            }
            PlayerMetricsLog.record(
                .playbackRecovery,
                metricsID: self.metricsID,
                title: self.title,
                message: "stage=manualResumeVideoOutput status=\(didRefreshVideoOutput ? "applied" : "unavailable") baseline=\(String(format: "%.2fs", baselineTime))"
            )

            try? await Task.sleep(nanoseconds: itemDelay)
            guard !Task.isCancelled,
                  self.canContinueAppBackgroundResumeRecovery(
                    mediaPreparationGeneration: baselineMediaPreparationGeneration,
                    surfaceGeneration: baselineSurfaceGeneration
                  )
            else {
                self.clearAppBackgroundResumeRecoveryTaskIfCurrent(generation: recoveryGeneration)
                return
            }
            if self.hasPlaybackAdvancedAfterStoppedBackgroundResume(from: baselineTime) {
                self.clearAppBackgroundResumeRecoveryTaskIfCurrent(generation: recoveryGeneration)
                return
            }

            guard let restoredTime = self.engine.rebuildPlayerItemForPlaybackRecovery(at: baselineTime) else {
                self.startFullAppBackgroundMediaRebuild(
                    reason: "manual-resume-player-item-unavailable",
                    baselineTime: baselineTime,
                    recoveryGeneration: recoveryGeneration
                )
                return
            }
            self.updatePlaybackTime(restoredTime, force: true, countsAsNaturalPlayback: false)
            self.refreshSurfaceLayout()
            if self.canActivatePlayback(generation: baselineSurfaceGeneration) {
                self.engine.play()
                self.engine.setPlaybackRate(self.playbackRate.rawValue)
            }
            PlayerMetricsLog.record(
                .playbackRecovery,
                metricsID: self.metricsID,
                title: self.title,
                message: "stage=manualResumePlayerItem status=applied bridge=reused target=\(String(format: "%.2fs", restoredTime))"
            )

            try? await Task.sleep(nanoseconds: mediaDelay)
            guard !Task.isCancelled,
                  self.canContinueAppBackgroundResumeRecovery(
                    mediaPreparationGeneration: baselineMediaPreparationGeneration,
                    surfaceGeneration: baselineSurfaceGeneration
                  )
            else {
                self.clearAppBackgroundResumeRecoveryTaskIfCurrent(generation: recoveryGeneration)
                return
            }
            if self.hasPlaybackAdvancedAfterStoppedBackgroundResume(from: restoredTime) {
                self.clearAppBackgroundResumeRecoveryTaskIfCurrent(generation: recoveryGeneration)
                return
            }
            self.startFullAppBackgroundMediaRebuild(
                reason: "manual-resume-player-item-no-frame",
                baselineTime: restoredTime,
                recoveryGeneration: recoveryGeneration
            )
        }
    }

    private func hasPlaybackAdvancedAfterStoppedBackgroundResume(from baselineTime: TimeInterval) -> Bool {
        if let renderedTime = engine.currentRenderedVideoTime(),
           renderedTime.isFinite,
           renderedTime > baselineTime + 0.008 {
            return true
        }
        let playbackTime = engine.snapshot(durationHint: durationHint).currentTime ?? currentTime
        return playbackTime.isFinite && playbackTime > baselineTime + 0.2
    }

    private func startFullAppBackgroundMediaRebuild(
        reason: String,
        baselineTime: TimeInterval,
        recoveryGeneration: Int
    ) {
        clearAppBackgroundResumeRecoveryTaskIfCurrent(generation: recoveryGeneration)
        PlayerMetricsLog.record(
            .playbackRecovery,
            metricsID: metricsID,
            title: title,
            message: "stage=mediaRebuild status=started reason=app-background-\(reason) baseline=\(String(format: "%.2fs", baselineTime))"
        )
        rebuildMediaAfterPlaybackInterruption()
    }

    private func cancelAppBackgroundResumeRecovery() {
        appBackgroundResumeRecoveryGeneration &+= 1
        appBackgroundResumeRecoveryTask?.cancel()
        appBackgroundResumeRecoveryTask = nil
    }

    private func clearAppBackgroundResumeRecoveryTaskIfCurrent(generation: Int) {
        guard generation == appBackgroundResumeRecoveryGeneration else { return }
        appBackgroundResumeRecoveryTask = nil
    }

    private func canContinueAppBackgroundResumeRecovery(
        mediaPreparationGeneration: Int,
        surfaceGeneration: Int
    ) -> Bool {
        !isTerminated
            && wantsAutoplay
            && engine.hasMedia
            && errorMessage == nil
            && !isUserSeeking
            && self.mediaPreparationGeneration == mediaPreparationGeneration
            && canActivatePlayback(generation: surfaceGeneration)
    }

    private func performPlaybackRecovery(
        reason: PlaybackRecoveryWatchdogReason,
        baselineTime: TimeInterval,
        surfaceGeneration: Int
    ) {
        guard canActivatePlayback(generation: surfaceGeneration) else {
            playbackRecoveryWatchdogTask = nil
            return
        }
        guard recoveryAttemptCount < maximumPlaybackRecoveryAttempts else {
            playbackRecoveryWatchdogTask = nil
            failPlaybackRecovery(reason: reason)
            return
        }

        recoveryAttemptCount += 1
        playbackPhase = .recovering
        isPreparing = false
        isBuffering = true
        PlayerMetricsLog.logger.info(
            "playbackRecovery id=\(self.metricsID, privacy: .public) reason=\(reason.logTitle, privacy: .public) attempt=\(self.recoveryAttemptCount, privacy: .public) baseline=\(baselineTime, format: .fixed(precision: 2), privacy: .public)"
        )
        PlayerMetricsLog.record(
            .playbackRecovery,
            metricsID: metricsID,
            title: title,
            message: "stage=surfaceRecover status=started reason=\(reason.logTitle) attempt=\(recoveryAttemptCount) baseline=\(String(format: "%.2fs", baselineTime))"
        )

        engine.recoverSurface()
        refreshSurfaceLayout()
        configurePictureInPictureIfNeeded()
        engine.play()
        engine.setPlaybackRate(playbackRate.rawValue)

        schedulePlaybackRecoveryWatchdog(reason: reason)
    }

    private func failPlaybackRecovery(reason: PlaybackRecoveryWatchdogReason) {
        let message = reason == .firstFrame ? "播放首帧长时间无响应" : "播放长时间无进展"
        let failureReason = HLSBridgeFailureReason(
            layer: .local,
            category: .terminalStall,
            statusCode: nil,
            urlHost: streamSource.videoURL?.host?.lowercased(),
            rangeDescription: nil,
            underlyingDescription: message
        )
        PlayerMetricsLog.logger.error(
            "playbackRecoveryFailed id=\(self.metricsID, privacy: .public) reason=\(reason.logTitle, privacy: .public) attempts=\(self.recoveryAttemptCount, privacy: .public)"
        )
        recordPlaybackFailure(message: message, reason: failureReason)
        cancelDeferredBufferingIndicator()
        isPreparing = false
        isBuffering = false
        isPlaying = false
        playbackPhase = .failed(message)
        PlayerMetricsLog.record(.failed, metricsID: metricsID, title: title, message: message)
        onPlaybackFailureWithReason?(message, failureReason)
        onPlaybackFailure?(message)
        wantsAutoplay = false
    }

    private func acceptFirstFramePresentationFallback(
        currentTime playbackTime: TimeInterval?,
        source: String
    ) -> Bool {
        guard !isTerminated,
              !hasPresentedPlayback,
              !isPlaybackSurfaceReady,
              engine.hasMedia,
              errorMessage == nil,
              surfaceView != nil,
              ActivePlaybackCoordinator.shared.isActive(self)
        else { return false }

        guard let image = firstUsablePlaybackSnapshotImage(
            currentSurfaceSnapshotImage(),
            surfaceView?.makePlaybackTransitionSnapshotImage()
        ) else { return false }
        rememberUsablePlaybackSnapshotImage(image)

        let resolvedTime = max(playbackTime ?? currentTime, 0)
        if resolvedTime > 0 {
            _ = updatePlaybackTime(resolvedTime, force: currentTime <= 0, countsAsNaturalPlayback: false)
        }
        markPlaybackSurfaceReady()
        recordFirstFrameIfNeeded(currentTime: resolvedTime, source: source)
        return true
    }

    private func scheduleDeferredBufferingIndicator() {
        guard deferredBufferingIndicatorTask == nil else { return }
        let baselineTime = currentTime
        let baselineAttempt = recoveryAttemptCount
        let baselineMediaPreparationGeneration = mediaPreparationGeneration
        let baselineSurfaceGeneration = surfaceAttachmentGeneration
        deferredBufferingIndicatorTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.deferredBufferingIndicatorDelayNanoseconds)
            guard !Task.isCancelled,
                  !self.isTerminated,
                  self.hasPresentedPlayback,
                  self.wantsAutoplay,
                  self.engine.hasMedia,
                  self.recoveryAttemptCount == baselineAttempt,
                  self.mediaPreparationGeneration == baselineMediaPreparationGeneration,
                  self.hasCurrentSurface(generation: baselineSurfaceGeneration)
            else {
                self.deferredBufferingIndicatorTask = nil
                return
            }

            let snapshot = self.engine.snapshot(durationHint: self.durationHint)
            if let snapshotTime = snapshot.currentTime,
               snapshotTime > baselineTime + 0.18 {
                _ = self.updatePlaybackTime(snapshotTime)
                self.playbackPhase = snapshot.isPlaying ? .playing : self.playbackPhase
                self.deferredBufferingIndicatorTask = nil
                return
            }

            if !self.isBuffering {
                self.bufferingCount += 1
                self.lastBufferingElapsedMilliseconds = self.elapsedMilliseconds()
                self.notifyBufferingPressureIfNeeded()
            }
            self.isPreparing = false
            self.isBuffering = true
            self.playbackPhase = .buffering
            PlayerMetricsLog.record(.buffering, metricsID: self.metricsID, title: self.title, message: self.elapsedMessage())
            self.schedulePlaybackRecoveryWatchdog(reason: .stall)
            self.deferredBufferingIndicatorTask = nil
        }
    }

    private func cancelDeferredBufferingIndicator() {
        deferredBufferingIndicatorTask?.cancel()
        deferredBufferingIndicatorTask = nil
    }

    private func clearMediaPreparationTaskIfCurrent(_ generation: Int) {
        guard generation == mediaPreparationGeneration else { return }
        mediaPreparationTask = nil
    }

    private func rebuildMediaAfterPlaybackInterruption(allowsDetachedSurface: Bool = false) {
        guard !isTerminated else { return }
        guard mediaPreparationTask == nil else { return }
        cancelAppBackgroundResumeRecovery()
        let baselineSurfaceGeneration = surfaceAttachmentGeneration
        guard (allowsDetachedSurface || hasCurrentSurface(generation: baselineSurfaceGeneration)),
              ActivePlaybackCoordinator.shared.isActive(self)
        else { return }
        let restoreTime = currentTime
        isPreparing = false
        mediaPreparationGeneration &+= 1
        let preparationGeneration = mediaPreparationGeneration
        mediaPreparationTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                try await self.engine.prepare(source: self.streamSourceForPreparation())
                guard !Task.isCancelled,
                      !self.isTerminated,
                      preparationGeneration == self.mediaPreparationGeneration,
                      (allowsDetachedSurface || self.hasCurrentSurface(generation: baselineSurfaceGeneration)),
                      ActivePlaybackCoordinator.shared.isActive(self)
                else {
                    self.clearMediaPreparationTaskIfCurrent(preparationGeneration)
                    return
                }
                self.clearMediaPreparationTaskIfCurrent(preparationGeneration)
                if restoreTime > 0, let time = self.engine.seek(toTime: restoreTime) {
                    self.updatePlaybackTime(time, force: true, countsAsNaturalPlayback: false)
                }
                if self.wantsAutoplay {
                    self.startPreparedPlayback()
                } else {
                    self.refreshPlaybackState()
                }
            } catch {
                guard !Task.isCancelled,
                      !self.isTerminated,
                      preparationGeneration == self.mediaPreparationGeneration,
                      (allowsDetachedSurface || self.hasCurrentSurface(generation: baselineSurfaceGeneration)),
                      ActivePlaybackCoordinator.shared.isActive(self)
                else {
                    self.clearMediaPreparationTaskIfCurrent(preparationGeneration)
                    return
                }
                self.clearMediaPreparationTaskIfCurrent(preparationGeneration)
                self.recordPlaybackFailure(message: error.localizedDescription, reason: self.engine.lastFailureReason)
                self.isPreparing = false
                self.onPlaybackFailureWithReason?(self.errorMessage, self.lastFailureReason)
                self.onPlaybackFailure?(self.errorMessage)
            }
        }
    }

    func play() {
        guard !isTerminated else { return }
        syncPictureInPictureState()
        guard allowsPlaybackInCurrentApplicationState else {
            _ = pauseForAppBackground()
            return
        }
        let isRestartingStoppedBackgroundPlayback = isPlaybackStoppedForAppBackground
        let stoppedBackgroundResumeTime: TimeInterval? = isRestartingStoppedBackgroundPlayback
            ? max(
                appBackgroundPlaybackRestoreTime
                    ?? engine.snapshot(durationHint: durationHint).currentTime
                    ?? currentTime,
                0
            )
            : nil
        if isRestartingStoppedBackgroundPlayback {
            _ = prepareStoppedPlaybackAfterAppBackgroundIfNeeded()
        }
        shouldResumePlaybackAfterAppBackground = false
        appBackgroundPlaybackRestoreTime = nil
        isPlaybackStoppedForAppBackground = false
        didPrepareStoppedAppBackgroundPlayback = false
        if !isRestartingStoppedBackgroundPlayback {
            cancelAppBackgroundSurfaceRecovery()
        }
        cancelAppBackgroundResumeRecovery()
        if showsExplicitPlaybackStartControl {
            isAwaitingInitialManualPlayback = false
            isAwaitingRelatedVideoReturnPlayback = false
            onExplicitPlaybackStartRequested?()
        }
        restoreAudioAfterCancelledNavigation()
        ActivePlaybackCoordinator.shared.activate(self)
        wantsAutoplay = true
        errorMessage = nil
        lastFailureReason = nil
        syncRemotePlaybackControls()
        let hasPlayableSource = playbackContentMode == .audioOnly
            ? streamSource.audioURL != nil
            : streamSource.videoURL != nil
        guard hasPlayableSource else {
            recordPlaybackFailure(
                message: (playbackContentMode == .audioOnly
                    ? PlayerEngineError.missingAudioURL
                    : PlayerEngineError.missingVideoURL).localizedDescription,
                reason: nil
            )
            isPreparing = false
            syncRemotePlaybackControls()
            return
        }

        if !engine.hasMedia {
            prepareMediaAndPlay()
            return
        }
        if mediaPreparationTask != nil {
            isPreparing = true
            isBuffering = hasPresentedPlayback
            playbackPhase = hasPresentedPlayback ? .buffering : .preparing
            return
        }

        startPreparedPlayback()
        if let stoppedBackgroundResumeTime {
            scheduleStoppedAppBackgroundResumeRecovery(from: stoppedBackgroundResumeTime)
        }
    }

    func startSeamlessPlaybackHandoff(from source: PlayerStateViewModel) {
        guard !isTerminated,
              source !== self,
              !source.isTerminated,
              ActivePlaybackCoordinator.shared.isActive(source)
        else {
            play()
            return
        }

        seamlessPlaybackHandoffSource = source
        wantsAutoplay = true
        errorMessage = nil
        lastFailureReason = nil
        engine.setTemporaryAudioSuppressed(true)
        syncRemotePlaybackControls()

        let hasPlayableSource = playbackContentMode == .audioOnly
            ? streamSource.audioURL != nil
            : streamSource.videoURL != nil
        guard hasPlayableSource else {
            seamlessPlaybackHandoffSource = nil
            play()
            return
        }

        if !engine.hasMedia {
            prepareMediaAndPlay()
            return
        }

        refreshSeamlessPlaybackHandoffResumeTarget()
        if !applyPendingStartupResumeIfPossible() {
            startPreparedPlayback()
        }
    }

    private func refreshSeamlessPlaybackHandoffResumeTarget() {
        guard let source = seamlessPlaybackHandoffSource,
              source !== self,
              !source.isTerminated
        else { return }
        let sourceSnapshot = source.playbackSnapshot()
        let sourceTime = max(sourceSnapshot.currentTime ?? 0, source.currentTime)
        guard sourceTime.isFinite, sourceTime > 0.25 else { return }

        pendingStartupResume = PendingStartupResume(
            time: sourceTime,
            reason: "seamlessPlaybackHandoff"
        )
        didApplyResumeTime = true
        cancelStartupResumeRetryTask()
        PlayerMetricsLog.record(
            .resumeDecision,
            metricsID: metricsID,
            title: title,
            message: "player handoff aligned target=\(String(format: "%.2fs", sourceTime))"
        )
    }

    private func completeSeamlessPlaybackHandoffIfNeeded() {
        guard let source = seamlessPlaybackHandoffSource else { return }
        seamlessPlaybackHandoffSource = nil
        ActivePlaybackCoordinator.shared.activate(self)
        engine.play()
        engine.setPlaybackRate(playbackRate.rawValue)
        syncRemotePlaybackControls(forceNowPlayingTimeUpdate: true)
        PlayerMetricsLog.record(
            .playbackRecovery,
            metricsID: metricsID,
            title: title,
            message: "playbackHandoff completed from=\(source.playbackContentMode.rawValue) to=\(playbackContentMode.rawValue)"
        )
    }

    func resumePlaybackAfterUserSeek() {
        guard !isTerminated else { return }
        guard canActivatePlayback() else { return }
        wantsAutoplay = true
        errorMessage = nil
        guard engine.hasMedia else {
            play()
            return
        }
        resumePreparedPlaybackAfterSeek()
    }

    @discardableResult
    func applyStartupResumeTime(_ time: TimeInterval, reason: String) -> Bool {
        guard !isTerminated, time > 0.25 else { return false }
        PlayerMetricsLog.signpostEvent(
            "PlayerStartupResume",
            message: "request reason=\(reason) target=\(String(format: "%.2f", time))"
        )
        cancelStartupResumeRecoveryTracking()
        pendingStartupResume = PendingStartupResume(time: time, reason: reason)
        didApplyResumeTime = true
        cancelStartupResumeRetryTask()
        let didApply = applyPendingStartupResumeIfPossible()
        if !didApply {
            schedulePendingStartupResumeRetry()
        }
        PlayerMetricsLog.record(
            .resumeDecision,
            metricsID: metricsID,
            title: title,
            message: "player \(didApply ? "applied" : "queued") reason=\(reason) target=\(String(format: "%.2fs", time))"
        )
        return didApply
    }

    private func schedulePendingStartupResumeRetry() {
        cancelStartupResumeRetryTask()
        let retryGeneration = advanceStartupResumeRetryGeneration()
        startupResumeRetryTask = Task { @MainActor [weak self] in
            let retryDelays: [UInt64] = [
                90_000_000,
                180_000_000,
                320_000_000,
                520_000_000,
                850_000_000,
                1_300_000_000
            ]
            for delay in retryDelays {
                try? await Task.sleep(nanoseconds: delay)
                guard let self,
                      !Task.isCancelled,
                      !self.isTerminated,
                      self.startupResumeRetryGeneration == retryGeneration,
                      self.canActivatePlayback()
                else { return }
                if self.applyPendingStartupResumeIfPossible() {
                    self.clearStartupResumeRetryTaskIfCurrent(retryGeneration)
                    return
                }
            }
            self?.clearStartupResumeRetryTaskIfCurrent(retryGeneration)
        }
    }

    func pause() {
        cancelSeamlessPlaybackHandoffForExplicitPause()
        if audioInterruptionState.isActive {
            audioInterruptionState.cancelAutomaticResume()
            recordAudioSessionEvent("interruption=userPause action=cancelAutoResume")
        }
        isPlaybackStoppedForAppBackground = false
        didPrepareStoppedAppBackgroundPlayback = false
        pause(retainingAppBackgroundResumeIntent: false)
    }

    private func cancelSeamlessPlaybackHandoffForExplicitPause() {
        guard let source = seamlessPlaybackHandoffSource else { return }
        seamlessPlaybackHandoffSource = nil
        source.pause()
        ActivePlaybackCoordinator.shared.activate(self)
        engine.setTemporaryAudioSuppressed(false)
    }

    private func pause(
        retainingAppBackgroundResumeIntent: Bool,
        usesAppBackgroundPause: Bool = false,
        preservesAppBackgroundSurfaceRecovery: Bool = false
    ) {
        guard !isTerminated else { return }
        if !retainingAppBackgroundResumeIntent {
            shouldResumePlaybackAfterAppBackground = false
            if !preservesAppBackgroundSurfaceRecovery {
                appBackgroundPlaybackRestoreTime = nil
                cancelAppBackgroundSurfaceRecovery()
            }
        }
        cancelAppBackgroundResumeRecovery()
        cancelScrubSeekTasks(resetUserSeeking: true)
        wantsAutoplay = false
        cancelDeferredBufferingIndicator()
        cancelStartupResumeRecoveryTracking()
        cancelSeekRecoveryTracking()
        playbackRecoveryWatchdogTask?.cancel()
        playbackRecoveryWatchdogTask = nil
        if retainingAppBackgroundResumeIntent || usesAppBackgroundPause {
            engine.pauseForAppBackground()
        } else {
            engine.pause()
        }
        isPlaying = false
        isBuffering = false
        playbackPhase = .paused
        invalidatePictureInPicturePlaybackState()
        syncRemotePlaybackControls()
        rescheduleTimeObserverIfNeeded()
    }

    func pauseForNavigation() {
        guard !isTerminated else { return }
        isPlaybackStoppedForAppBackground = false
        didPrepareStoppedAppBackgroundPlayback = false
        shouldResumePlaybackAfterAppBackground = false
        appBackgroundPlaybackRestoreTime = nil
        cancelAppBackgroundSurfaceRecovery()
        cancelAppBackgroundResumeRecovery()
        silenceAudioForNavigationIfNeeded()
        cancelScrubSeekTasks(resetUserSeeking: true)
        mediaPreparationTask?.cancel()
        mediaPreparationTask = nil
        mediaPreparationGeneration &+= 1
        wantsAutoplay = false
        cancelDeferredBufferingIndicator()
        cancelStartupResumeRecoveryTracking()
        cancelSeekRecoveryTracking()
        playbackRecoveryWatchdogTask?.cancel()
        playbackRecoveryWatchdogTask = nil
        engine.suspendForNavigation()
        isPlaying = false
        isBuffering = false
        playbackPhase = .paused
        invalidatePictureInPicturePlaybackState()
        syncRemotePlaybackControls()
        rescheduleTimeObserverIfNeeded()
    }

    func pendingNavigationResumeState() -> (resumeTime: TimeInterval, shouldResumePlayback: Bool)? {
        guard let navigationAudioSuspension else { return nil }
        return (
            navigationAudioSuspension.resumeTime,
            navigationAudioSuspension.shouldResumePlayback
        )
    }

    func prepareForVisualPlaybackTransition() {
        guard !isTerminated else { return }
        shouldResumePlaybackAfterAppBackground = false
        appBackgroundPlaybackRestoreTime = nil
        cancelAppBackgroundSurfaceRecovery()
        silenceAudioForNavigationIfNeeded()
        cancelScrubSeekTasks(resetUserSeeking: true)
        ActivePlaybackCoordinator.shared.deactivate(self)
        PlayerRemoteControlSession.shared.clearIfCurrent(self)
        wantsAutoplay = false
        cancelDeferredBufferingIndicator()
        cancelStartupResumeRecoveryTracking()
        cancelSeekRecoveryTracking()
        playbackRecoveryWatchdogTask?.cancel()
        playbackRecoveryWatchdogTask = nil
        isPreparing = false
        isBuffering = false
        if engine.hasMedia {
            let snapshot = engine.snapshot(durationHint: durationHint)
            isPlaying = snapshot.isPlaying
            playbackPhase = snapshot.isPlaying ? .playing : .paused
        } else {
            isPlaying = false
            playbackPhase = .idle
        }
        invalidatePictureInPicturePlaybackState()
        rescheduleTimeObserverIfNeeded()
    }

    @discardableResult
    func restoreAudioAfterCancelledNavigation() -> Bool {
        guard !isTerminated, let navigationAudioSuspension else { return false }
        self.navigationAudioSuspension = nil
        guard surfaceView != nil else { return false }
        ActivePlaybackCoordinator.shared.activate(self)
        engine.setVolume(navigationAudioSuspension.volume)
        engine.setMuted(navigationAudioSuspension.isMuted)
        if navigationAudioSuspension.resumeTime > 0.25 {
            applyStartupResumeTime(navigationAudioSuspension.resumeTime, reason: "cancelledNavigation")
        }
        if navigationAudioSuspension.shouldResumePlayback {
            wantsAutoplay = true
            if engine.hasMedia, canActivatePlayback() {
                resumePreparedPlaybackAfterSeek()
            }
        }
        return true
    }

    func setPlaybackIntent(_ shouldAutoplay: Bool) {
        guard !isTerminated else { return }
        if !shouldAutoplay, audioInterruptionState.isActive {
            audioInterruptionState.cancelAutomaticResume()
            recordAudioSessionEvent("interruption=explicitPauseIntent action=cancelAutoResume")
        }
        wantsAutoplay = shouldAutoplay
        if !shouldAutoplay {
            cancelScrubSeekTasks(resetUserSeeking: true)
            cancelDeferredBufferingIndicator()
            cancelStartupResumeRecoveryTracking()
            cancelSeekRecoveryTracking()
            playbackRecoveryWatchdogTask?.cancel()
            playbackRecoveryWatchdogTask = nil
            isPlaying = false
            isBuffering = false
            playbackPhase = engine.hasMedia ? .paused : .idle
            syncRemotePlaybackControls()
            rescheduleTimeObserverIfNeeded()
        }
    }

    func setInitialManualPlaybackPrompt(_ isAwaitingManualPlayback: Bool) {
        guard !isTerminated else { return }
        isAwaitingInitialManualPlayback = isAwaitingManualPlayback
    }

    func setRelatedVideoReturnPlaybackPrompt(_ isAwaitingPlayback: Bool) {
        guard !isTerminated else { return }
        isAwaitingRelatedVideoReturnPlayback = isAwaitingPlayback
    }

    var showsExplicitPlaybackStartControl: Bool {
        isAwaitingInitialManualPlayback || isAwaitingRelatedVideoReturnPlayback
    }

    func suspendForNavigation() {
        guard !isTerminated else { return }
        mediaPreparationTask?.cancel()
        mediaPreparationTask = nil
        startupMediaWarmupTask?.cancel()
        startupMediaWarmupTask = nil
        deferredStartupResumeTask?.cancel()
        deferredStartupResumeTask = nil
        cancelTransientInteractionTasks()
        pauseForNavigation()
    }

    func stop(reason: PlayerStopReason = .navigation) {
        guard !isStopping else { return }
        if isTerminated {
            ActivePlaybackCoordinator.shared.deactivate(self)
            return
        }
        isStopping = true
        isTerminated = true
        isPlaybackStoppedForAppBackground = false
        didPrepareStoppedAppBackgroundPlayback = false
        shouldResumePlaybackAfterAppBackground = false
        appBackgroundPlaybackRestoreTime = nil
        cancelAppBackgroundSurfaceRecovery()
        engineCallbackGeneration &+= 1
        mediaPreparationGeneration &+= 1
        cancelAppBackgroundResumeRecovery()
        cancelScrubSeekTasks(resetUserSeeking: true)
        cancelDeferredBufferingIndicator()
        mediaPreparationTask?.cancel()
        mediaPreparationTask = nil
        startupMediaWarmupTask?.cancel()
        startupMediaWarmupTask = nil
        deferredStartupResumeTask?.cancel()
        deferredStartupResumeTask = nil
        cancelTransientInteractionTasks()
        cancelStartupResumeRecoveryTracking()
        cancelSeekRecoveryTracking()
        cancelStartupResumeRetryTask()
        playbackRecoveryWatchdogTask?.cancel()
        playbackRecoveryWatchdogTask = nil
        cancelPictureInPictureStartRetryTask()
        pictureInPictureInlineRecoveryTask?.cancel()
        pictureInPictureInlineRecoveryTask = nil
        audioSessionCancellables.removeAll()
        audioInterruptionState.reset()
        sponsorBlockSkipReportTasks.values.forEach { $0.cancel() }
        sponsorBlockSkipReportTasks.removeAll()
        navigationAudioSuspension = nil
        seamlessPlaybackHandoffSource = nil
        timeObserver?.invalidate()
        timeObserver = nil
        wantsAutoplay = false
        onPlaybackFailure = nil
        onPlaybackFailureWithReason = nil
        onBufferingPressure = nil
        onFirstFramePresented = nil
        onSponsorBlockSegmentSkipped = nil
        engine.onPlaybackStateChange = nil
        engine.onPlaybackIntentChange = nil
        engine.onLoadingProgressChange = nil
        engine.onFirstFrame = nil
        engine.stop()
        engine.setViewModel(nil)
        ActivePlaybackCoordinator.shared.unregister(self)
        isPlaying = false
        isPreparing = false
        isBuffering = false
        errorMessage = nil
        loadingProgress = 0
        hasPresentedPlayback = false
        isPlaybackSurfaceReady = false
        currentPlaybackSurfaceReadyGeneration = nil
        isCurrentPlaybackSurfaceReadyForDisplay = false
        currentTime = 0
        playbackClock.reset()
        playbackPhase = .idle
        PlayerRemoteControlSession.shared.clearIfCurrent(self)
        recoveryAttemptCount = 0
        lastBufferingPressureNotificationCount = 0
        forcedPlaybackTimeGuard = nil
        lastSeekBufferReadyMetricID = nil
        clearPendingUserSeekRevealTarget()
        didRecordFirstFrameEvent = false
        pendingEngineFirstFrameTime = nil
        invalidatePictureInPicturePlaybackState()
        isStopping = false
    }

    private func cancelTransientInteractionTasks() {
        speedBoostRecoveryTask?.cancel()
        speedBoostRecoveryTask = nil
    }

    private func cancelScrubSeekTasks(resetUserSeeking: Bool) {
        scrubSeekGeneration &+= 1
        scrubSeekTask?.cancel()
        scrubSeekTask = nil
        if resetUserSeeking, isUserSeeking {
            isUserSeeking = false
            shouldResumePlaybackAfterUserScrub = false
            clearPendingUserSeekRevealTarget()
            engine.setTemporaryAudioSuppressed(false)
        }
        clearActiveUserScrubInteraction()
    }

    private func clearActiveUserScrubInteraction() {
        activeUserScrubSource = nil
        activeUserScrubStartedAt = nil
    }

    private func recordScrubInteraction(
        source: PlayerScrubInteractionSource,
        result: String,
        progress: Double? = nil,
        elapsedMilliseconds: Double? = nil
    ) {
        var parts = ["scrub", "source=\(source.rawValue)", "result=\(result)"]
        if let progress {
            parts.append("progress=\(String(format: "%.3f", min(max(progress, 0), 1)))")
        }
        if let elapsedMilliseconds {
            parts.append("elapsed=\(String(format: "%.0fms", elapsedMilliseconds))")
        }
        PlayerMetricsLog.record(
            .seek,
            metricsID: metricsID,
            title: title,
            message: parts.joined(separator: " ")
        )
    }

    @discardableResult
    func togglePlayback() -> Bool {
        guard !isTerminated else { return false }
        let snapshot = engine.snapshot(durationHint: durationHint)
        let shouldPause = wantsAutoplay
            || isPlaying
            || (snapshot.isPlaying && playbackPhase != .paused)
        if shouldPause {
            pause()
            return false
        } else {
            play()
            return wantsAutoplay && errorMessage == nil
        }
    }

    @discardableResult
    func jumpToLiveEdge() -> Bool {
        guard !isTerminated, isLiveStream else { return false }
        guard engine.hasMedia else {
            play()
            return false
        }

        restoreAudioAfterCancelledNavigation()
        ActivePlaybackCoordinator.shared.activate(self)
        wantsAutoplay = true
        errorMessage = nil
        lastFailureReason = nil
        engine.play()

        guard let time = engine.seekToLiveEdge() else {
            refreshPlaybackState()
            return false
        }

        updatePlaybackTime(time, force: true, countsAsNaturalPlayback: false)
        PlayerMetricsLog.record(
            .seek,
            metricsID: metricsID,
            title: title,
            message: "liveEdge target=\(String(format: "%.2fs", time))"
        )
        invalidatePictureInPicturePlaybackState()
        syncRemotePlaybackControls()
        rescheduleTimeObserverIfNeeded(force: true)
        return true
    }

    func seek(to progress: Double) {
        guard !isTerminated else { return }
        guard engine.hasMedia else { return }
        markUserSeekIntent()
        let signpostState = PlayerMetricsLog.beginSignpostedInterval(
            "PlayerSeek",
            message: "mode=tap target=\(String(format: "%.3f", progress))"
        )
        let userSeekStart = CACurrentMediaTime()
        var signpostMessage = "mode=tap pending"
        defer {
            PlayerMetricsLog.endSignpostedInterval(
                "PlayerSeek",
                signpostState,
                message: signpostMessage
            )
        }
        if let time = engine.seek(toProgress: progress, duration: duration) {
            updatePlaybackTime(time, force: true, countsAsNaturalPlayback: false)
            beginSeekRecoveryTracking(
                reason: "tap",
                targetTime: time,
                targetProgress: progress,
                startedAt: userSeekStart,
                engineElapsedMilliseconds: nil
            )
            self.recordSeekTransition(
                reason: "tap",
                targetTime: time,
                targetProgress: progress,
                totalElapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: userSeekStart),
                engineElapsedMilliseconds: nil
            )
            signpostMessage = "mode=tap target=\(String(format: "%.3f", progress)) applied=\(String(format: "%.2f", time))"
        } else {
            signpostMessage = "mode=tap target=\(String(format: "%.3f", progress)) skipped"
        }
        invalidatePictureInPicturePlaybackState()
    }

    func seekAfterSliderCommit(to progress: Double) {
        guard !isTerminated else { return }
        guard engine.hasMedia else { return }
        markUserSeekIntent()
        cancelStartupResumeCorrectionAfterUserSeek()
        cancelSeekRecoveryTracking()
        cancelDeferredBufferingIndicator()
        playbackRecoveryWatchdogTask?.cancel()
        playbackRecoveryWatchdogTask = nil
        let initialSnapshot = engine.snapshot(durationHint: durationHint)
        let shouldResumeAfterSeek = shouldResumePlaybackAfterUserScrub
            || wantsAutoplay
            || isPlaying
            || initialSnapshot.isPlaying
        shouldResumePlaybackAfterUserScrub = shouldResumeAfterSeek
        wantsAutoplay = false
        scrubSeekGeneration &+= 1
        let generation = scrubSeekGeneration
        let targetProgress = min(max(progress, 0), 1)
        let resolvedDuration = duration ?? durationHint ?? playbackClock.duration ?? initialSnapshot.duration ?? 0
        let optimisticTargetTime = resolvedDuration > 0 ? targetProgress * resolvedDuration : nil
        let userSeekStart = CACurrentMediaTime()
        let scrubSource = activeUserScrubSource
        let scrubElapsed = activeUserScrubStartedAt.map {
            PlayerMetricsLog.elapsedMilliseconds(since: $0)
        }
        clearActiveUserScrubInteraction()
        if let scrubSource {
            recordScrubInteraction(
                source: scrubSource,
                result: "commit",
                progress: targetProgress,
                elapsedMilliseconds: scrubElapsed
            )
        }
        let signpostState = PlayerMetricsLog.beginSignpostedInterval(
            "PlayerSeek",
            message: "mode=slider target=\(String(format: "%.3f", targetProgress))"
        )
        isUserSeeking = true
        isPreparing = false
        isBuffering = true
        loadingProgress = hasPresentedPlayback ? max(loadingProgress, 0.22) : max(loadingProgress, 0.78)
        playbackPhase = .seeking
        engine.setTemporaryAudioSuppressed(true)
        isPlaying = false
        if let optimisticTargetTime {
            setPendingUserSeekRevealTarget(optimisticTargetTime)
            _ = updatePlaybackTime(optimisticTargetTime, force: true, countsAsNaturalPlayback: false)
        }
        engine.pause()
        rescheduleTimeObserverIfNeeded(force: true)
        scrubSeekTask?.cancel()
        scrubSeekTask = Task(priority: .userInitiated) { @MainActor [weak self] in
            guard let self else {
                PlayerMetricsLog.endSignpostedInterval(
                    "PlayerSeek",
                    signpostState,
                    message: "mode=slider cancelled"
                )
                return
            }
            var signpostMessage = "mode=slider waiting"
            defer {
                if self.scrubSeekGeneration == generation {
                    self.scrubSeekTask = nil
                    self.rescheduleTimeObserverIfNeeded(force: true)
                }
                PlayerMetricsLog.endSignpostedInterval(
                    "PlayerSeek",
                    signpostState,
                    message: signpostMessage
                )
            }
            let engineSeekStart = CACurrentMediaTime()
            let seekDuration = resolvedDuration > 0 ? resolvedDuration : self.duration
            var appliedTime: TimeInterval?
            var seekReason: String
            appliedTime = await self.engine.seekAfterUserScrub(
                toProgress: targetProgress,
                duration: seekDuration
            )
            seekReason = shouldResumeAfterSeek ? "slider-engine-resume" : "slider-engine"
            if appliedTime == nil,
               let fallbackTarget = optimisticTargetTime ?? (self.currentTime > 0 ? self.currentTime : nil) {
                appliedTime = self.engine.seek(toTime: fallbackTarget)
                if appliedTime != nil {
                    seekReason = "slider-fallback"
                }
            }
            let totalElapsed = PlayerMetricsLog.elapsedMilliseconds(since: userSeekStart)
            let engineElapsed = PlayerMetricsLog.elapsedMilliseconds(since: engineSeekStart)
            guard !Task.isCancelled,
                  !self.isTerminated,
                  self.scrubSeekGeneration == generation
            else {
                signpostMessage = "mode=slider cancelled"
                return
            }
            guard let appliedTime else {
                signpostMessage = "mode=slider target=\(String(format: "%.3f", targetProgress)) skipped"
                self.isUserSeeking = false
                self.isBuffering = false
                self.shouldResumePlaybackAfterUserScrub = false
                self.clearPendingUserSeekRevealTarget()
                self.refreshPlaybackState()
                self.engine.setTemporaryAudioSuppressed(false)
                return
            }
            self.setPendingUserSeekRevealTarget(appliedTime)
            self.updatePlaybackTime(appliedTime, force: true, countsAsNaturalPlayback: false)
            self.beginSeekRecoveryTracking(
                reason: seekReason,
                targetTime: appliedTime,
                targetProgress: targetProgress,
                startedAt: userSeekStart,
                engineElapsedMilliseconds: engineElapsed
            )
            self.recordSeekTransition(
                reason: seekReason,
                targetTime: appliedTime,
                targetProgress: targetProgress,
                totalElapsedMilliseconds: totalElapsed,
                engineElapsedMilliseconds: engineElapsed
            )
            signpostMessage = "mode=slider target=\(String(format: "%.3f", targetProgress)) applied=\(String(format: "%.2f", appliedTime)) total=\(String(format: "%.1f", totalElapsed))ms engine=\(String(format: "%.1f", engineElapsed))ms reason=\(seekReason)"
            self.isPreparing = false
            if shouldResumeAfterSeek {
                self.isBuffering = true
                self.loadingProgress = max(self.loadingProgress, 0.86)
                self.playbackPhase = .seeking
                self.shouldResumePlaybackAfterUserScrub = false
                self.resumePlaybackAfterUserSeek()
            } else {
                self.isUserSeeking = false
                self.isBuffering = false
                self.wantsAutoplay = false
                self.isPlaying = false
                self.playbackPhase = .paused
                self.clearPendingUserSeekRevealTarget()
                self.refreshPlaybackState()
                self.engine.setTemporaryAudioSuppressed(false)
            }
        }
        invalidatePictureInPicturePlaybackState()
    }

    func seekAfterUserScrub(to progress: Double) {
        guard !isTerminated else { return }
        guard engine.hasMedia else { return }
        markUserSeekIntent()
        cancelStartupResumeCorrectionAfterUserSeek()
        let initialSnapshot = engine.snapshot(durationHint: durationHint)
        let shouldResumeAfterSeek = shouldResumePlaybackAfterUserScrub
            || wantsAutoplay
            || isPlaying
            || initialSnapshot.isPlaying
        shouldResumePlaybackAfterUserScrub = shouldResumeAfterSeek
        wantsAutoplay = false
        scrubSeekGeneration &+= 1
        let generation = scrubSeekGeneration
        let targetProgress = min(max(progress, 0), 1)
        let userSeekStart = CACurrentMediaTime()
        let resolvedDuration = duration ?? durationHint ?? playbackClock.duration ?? engine.snapshot(durationHint: durationHint).duration ?? 0
        let optimisticTargetTime = resolvedDuration > 0 ? targetProgress * resolvedDuration : nil
        let signpostState = PlayerMetricsLog.beginSignpostedInterval(
            "PlayerSeek",
            message: "mode=scrub target=\(String(format: "%.3f", targetProgress))"
        )
        var signpostMessage = "mode=scrub waiting"
        isUserSeeking = true
        isBuffering = true
        loadingProgress = hasPresentedPlayback ? 0.22 : max(loadingProgress, 0.78)
        playbackPhase = .seeking
        engine.pause()
        engine.setTemporaryAudioSuppressed(true)
        rescheduleTimeObserverIfNeeded(force: true)
        scrubSeekTask?.cancel()
        scrubSeekTask = Task(priority: .userInitiated) { @MainActor [weak self] in
            guard let self else {
                PlayerMetricsLog.endSignpostedInterval(
                    "PlayerSeek",
                    signpostState,
                    message: "mode=scrub cancelled"
                )
                return
            }
            defer {
                if self.scrubSeekGeneration == generation {
                    self.scrubSeekTask = nil
                    self.rescheduleTimeObserverIfNeeded(force: true)
                }
                PlayerMetricsLog.endSignpostedInterval(
                    "PlayerSeek",
                    signpostState,
                    message: signpostMessage
                )
            }
            try? await Task.sleep(nanoseconds: self.seekCoalescingDelayNanoseconds)
            guard !Task.isCancelled,
                  !self.isTerminated,
                  self.scrubSeekGeneration == generation
            else {
                signpostMessage = "mode=scrub cancelled"
                return
            }
            let engineSeekStart = CACurrentMediaTime()
            var appliedTime = await self.engine.seekAfterUserScrub(
                toProgress: targetProgress,
                duration: resolvedDuration > 0 ? resolvedDuration : self.duration
            )
            var seekReason = "scrub-engine"
            if appliedTime == nil,
               let fallbackTarget = optimisticTargetTime ?? (self.currentTime > 0 ? self.currentTime : nil) {
                appliedTime = self.engine.seek(toTime: fallbackTarget)
                if appliedTime != nil {
                    seekReason = "scrub-fallback"
                }
            }
            let totalElapsed = PlayerMetricsLog.elapsedMilliseconds(since: userSeekStart)
            let engineElapsed = PlayerMetricsLog.elapsedMilliseconds(since: engineSeekStart)
            guard !Task.isCancelled,
                  !self.isTerminated,
                  self.scrubSeekGeneration == generation
            else {
                signpostMessage = "mode=scrub cancelled"
                return
            }
            if let appliedTime {
                self.setPendingUserSeekRevealTarget(appliedTime)
                self.updatePlaybackTime(appliedTime, force: true, countsAsNaturalPlayback: false)
                self.beginSeekRecoveryTracking(
                    reason: seekReason,
                    targetTime: appliedTime,
                    targetProgress: targetProgress,
                    startedAt: userSeekStart,
                    engineElapsedMilliseconds: engineElapsed
                )
            }
            self.recordSeekTransition(
                reason: seekReason,
                targetTime: appliedTime,
                targetProgress: targetProgress,
                totalElapsedMilliseconds: totalElapsed,
                engineElapsedMilliseconds: engineElapsed
            )
            signpostMessage = "mode=scrub target=\(String(format: "%.3f", targetProgress)) applied=\(String(format: "%.2f", appliedTime ?? 0)) total=\(String(format: "%.1f", totalElapsed))ms engine=\(String(format: "%.1f", engineElapsed))ms reason=\(seekReason)"
            self.playbackRecoveryWatchdogTask?.cancel()
            self.playbackRecoveryWatchdogTask = nil
            self.isPreparing = false
            if shouldResumeAfterSeek {
                self.isBuffering = true
                self.loadingProgress = max(self.loadingProgress, 0.86)
                self.playbackPhase = .seeking
                self.shouldResumePlaybackAfterUserScrub = false
                self.resumePlaybackAfterUserSeek()
            } else {
                if self.isUserSeeking {
                    self.isUserSeeking = false
                }
                self.isBuffering = false
                self.shouldResumePlaybackAfterUserScrub = false
                self.wantsAutoplay = false
                self.isPlaying = false
                self.playbackPhase = .paused
                self.clearPendingUserSeekRevealTarget()
                self.refreshPlaybackState()
                self.engine.setTemporaryAudioSuppressed(false)
            }
        }
    }

    func beginUserScrubInteraction(source: PlayerScrubInteractionSource = .nativeProgress) {
        guard !isTerminated else { return }
        guard engine.hasMedia else { return }
        markUserSeekIntent()
        guard hasPresentedPlayback else { return }
        shouldResumePlaybackAfterUserScrub = wantsAutoplay || isPlaying || playbackPhase == .playing
        if activeUserScrubSource == nil {
            activeUserScrubSource = source
            activeUserScrubStartedAt = CACurrentMediaTime()
            recordScrubInteraction(
                source: source,
                result: "begin",
                progress: playbackClock.progress
            )
        }
        wantsAutoplay = false
        if !isUserSeeking {
            isUserSeeking = true
        }
        isPlaying = false
        isBuffering = true
        loadingProgress = max(loadingProgress, 0.22)
        playbackPhase = .seeking
        engine.pauseForUserScrub()
        engine.setTemporaryAudioSuppressed(true)
    }

    var shouldHoldSeekSnapshotAtInteractionStart: Bool {
        activeUserScrubSource == .pinnedProgress
    }

    func cancelUserScrubInteraction() {
        guard !isTerminated else { return }
        guard isUserSeeking else {
            clearActiveUserScrubInteraction()
            shouldResumePlaybackAfterUserScrub = false
            return
        }

        let shouldResume = shouldResumePlaybackAfterUserScrub
        let scrubSource = activeUserScrubSource
        let scrubElapsed = activeUserScrubStartedAt.map {
            PlayerMetricsLog.elapsedMilliseconds(since: $0)
        }
        cancelScrubSeekTasks(resetUserSeeking: false)
        cancelDeferredBufferingIndicator()
        cancelSeekRecoveryTracking()
        playbackRecoveryWatchdogTask?.cancel()
        playbackRecoveryWatchdogTask = nil
        isUserSeeking = false
        isBuffering = false
        shouldResumePlaybackAfterUserScrub = false
        clearActiveUserScrubInteraction()
        engine.setTemporaryAudioSuppressed(false)

        if let scrubSource {
            recordScrubInteraction(
                source: scrubSource,
                result: "cancel",
                elapsedMilliseconds: scrubElapsed
            )
        }

        if shouldResume {
            resumePlaybackAfterUserSeek()
        } else {
            wantsAutoplay = false
            isPlaying = false
            playbackPhase = .paused
            refreshPlaybackState()
            invalidatePictureInPicturePlaybackState()
        }
        syncRemotePlaybackControls()
        rescheduleTimeObserverIfNeeded(force: true)
    }

    func seek(by interval: TimeInterval) {
        guard !isTerminated else { return }
        guard engine.hasMedia else { return }
        markUserSeekIntent()
        let signpostState = PlayerMetricsLog.beginSignpostedInterval(
            "PlayerSeek",
            message: "mode=step delta=\(String(format: "%.2f", interval))"
        )
        let userSeekStart = CACurrentMediaTime()
        var signpostMessage = "mode=step pending"
        defer {
            PlayerMetricsLog.endSignpostedInterval(
                "PlayerSeek",
                signpostState,
                message: signpostMessage
            )
        }
        if let time = engine.seek(by: interval, from: currentTime, duration: duration ?? durationHint) {
            updatePlaybackTime(time, force: true, countsAsNaturalPlayback: false)
            let reason = interval < 0 ? "step-back" : "step-forward"
            beginSeekRecoveryTracking(
                reason: reason,
                targetTime: time,
                targetProgress: nil,
                startedAt: userSeekStart,
                engineElapsedMilliseconds: nil
            )
            recordSeekTransition(
                reason: reason,
                targetTime: time,
                targetProgress: nil,
                totalElapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: userSeekStart),
                engineElapsedMilliseconds: nil
            )
            signpostMessage = "mode=step delta=\(String(format: "%.2f", interval)) applied=\(String(format: "%.2f", time))"
        } else {
            signpostMessage = "mode=step delta=\(String(format: "%.2f", interval)) skipped"
        }
        invalidatePictureInPicturePlaybackState()
    }

    func setPlaybackRate(_ rate: BiliPlaybackRate) {
        guard !isTerminated else { return }
        guard playbackRate != rate else { return }
        speedBoostRecoveryTask?.cancel()
        speedBoostRecoveryTask = nil
        playbackRate = rate
        engine.setPlaybackRate(rate.rawValue)
        syncRemotePlaybackControls()
        rescheduleTimeObserverIfNeeded()
        invalidatePictureInPicturePlaybackState()
    }

    func recordSpeedBoostMetric(_ message: String) {
        PlayerMetricsLog.signpostEvent("PlayerSpeedBoost", message: message)
        PlayerMetricsLog.record(
            .speedBoost,
            metricsID: metricsID,
            title: title,
            message: message
        )
    }

    func stabilizePlaybackAfterSpeedBoost(restoredRate: BiliPlaybackRate, reason: String) {
        speedBoostRecoveryTask?.cancel()
        let initialSnapshot = engine.snapshot(durationHint: durationHint)
        let shouldKeepPlaying = wantsAutoplay
            || isPlaying
            || initialSnapshot.isPlaying
        recordSpeedBoostMetric("stabilize reason=\(reason) restore=\(restoredRate.title) keepPlaying=\(shouldKeepPlaying)")
        if shouldKeepPlaying,
           !initialSnapshot.isPlaying,
           canActivatePlayback() {
            engine.play()
        }
        engine.setPlaybackRate(restoredRate.rawValue)
        rescheduleTimeObserverIfNeeded(force: true)

        speedBoostRecoveryTask = Task { @MainActor [weak self] in
            let delays: [UInt64] = [180_000_000, 460_000_000]
            for delay in delays {
                try? await Task.sleep(nanoseconds: delay)
                guard let self,
                      !Task.isCancelled,
                      !self.isTerminated,
                      self.playbackRate == restoredRate,
                      self.canActivatePlayback()
                else { return }

                let snapshot = self.engine.snapshot(durationHint: self.durationHint)
                let shouldResume = self.wantsAutoplay || self.isPlaying || snapshot.isPlaying
                if shouldResume, !snapshot.isPlaying {
                    self.engine.play()
                }
                self.engine.setPlaybackRate(restoredRate.rawValue)
                if let snapshotTime = snapshot.currentTime {
                    _ = self.updatePlaybackTime(snapshotTime)
                }
            }
            self?.speedBoostRecoveryTask = nil
        }
    }

    func setVolume(_ value: Float) {
        guard !isTerminated else { return }
        let normalizedVolume = min(max(value, 0), 1)
        volume = normalizedVolume
        engine.setVolume(normalizedVolume)
        if normalizedVolume > 0, isMuted {
            isMuted = false
            engine.setMuted(false)
        }
        invalidatePictureInPicturePlaybackState()
    }

    func setMuted(_ muted: Bool) {
        guard !isTerminated else { return }
        isMuted = muted
        engine.setMuted(muted)
        invalidatePictureInPicturePlaybackState()
    }

    private func silenceAudioForNavigationIfNeeded() {
        if navigationAudioSuspension == nil {
            let snapshot = engine.snapshot(durationHint: durationHint)
            let resumeTime = max(snapshot.currentTime ?? 0, currentTime)
            navigationAudioSuspension = NavigationAudioSuspension(
                volume: engine.volume,
                isMuted: engine.isMuted,
                resumeTime: resumeTime.isFinite ? max(resumeTime, 0) : 0,
                shouldResumePlayback: wantsAutoplay || isPlaying || snapshot.isPlaying
            )
        }
        engine.setTemporaryAudioSuppressed(true)
    }

    func setSponsorBlockSegments(
        _ segments: [SponsorBlockSegment],
        isEnabled: Bool,
        onSegmentSkipped: (@Sendable (SponsorBlockSkipEvent) async -> Void)? = nil
    ) {
        sponsorBlockSegments = segments
            .filter(\.isSkippable)
            .sorted { $0.startTime < $1.startTime }
        sponsorBlockEnabled = isEnabled
        self.onSponsorBlockSegmentSkipped = onSegmentSkipped
        skippedSponsorBlockIDs.removeAll()
        sponsorBlockReportedIDs.removeAll()
        sponsorBlockSearchIndex = 0
        activeSponsorBlockSegment = nil
    }

    func setSponsorBlockEnabled(_ isEnabled: Bool) {
        sponsorBlockEnabled = isEnabled
        if !isEnabled {
            activeSponsorBlockSegment = nil
        }
    }

    func togglePictureInPicture() {
        guard isPictureInPictureEnabled else {
            stopPictureInPictureIfNeeded()
            return
        }
        configurePictureInPictureIfNeeded()
        if pictureInPictureController == nil, engine.supportsPictureInPicture {
            engine.togglePictureInPicture()
            isPictureInPictureActive = engine.isPictureInPictureActive
            return
        }
        guard let pictureInPictureController else { return }
        if pictureInPictureController.isPictureInPictureActive {
            cancelPictureInPictureStartRetryTask()
            pictureInPictureController.stopPictureInPicture()
        } else {
            if pictureInPictureController.isPictureInPicturePossible {
                pictureInPictureController.startPictureInPicture()
            } else {
                cancelPictureInPictureStartRetryTask()
                let retryGeneration = advancePictureInPictureStartRetryGeneration()
                let controller = pictureInPictureController
                pictureInPictureStartRetryTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    guard let self,
                          !Task.isCancelled,
                          !self.isTerminated,
                          self.pictureInPictureStartRetryGeneration == retryGeneration,
                          self.pictureInPictureController === controller,
                          ActivePlaybackCoordinator.shared.isActive(self)
                    else { return }
                    if controller.isPictureInPicturePossible {
                        controller.startPictureInPicture()
                    }
                    self.clearPictureInPictureStartRetryTaskIfCurrent(retryGeneration)
                }
            }
        }
    }

    func setPictureInPictureEnabled(_ isEnabled: Bool) {
        let effectiveIsEnabled = isEnabled && playbackContentMode == .video
        guard isPictureInPictureEnabled != effectiveIsEnabled else {
            return
        }
        isPictureInPictureEnabled = effectiveIsEnabled
        engine.setPictureInPictureEnabled(effectiveIsEnabled)
        pictureInPictureController?.canStartPictureInPictureAutomaticallyFromInline = effectiveIsEnabled
        surfaceView?.setPictureInPictureEnabled(effectiveIsEnabled)
        applyPictureInPicturePreferenceToNativePlaybackController()
        if !effectiveIsEnabled {
            let wasCustomPictureInPictureActive = pictureInPictureController?.isPictureInPictureActive == true
            stopPictureInPictureIfNeeded()
            if !wasCustomPictureInPictureActive {
                releasePictureInPictureControllerIfDisabled()
            }
        } else {
            configurePictureInPictureIfNeeded()
        }
        invalidatePictureInPicturePlaybackState()
    }

    func stopPictureInPictureIfNeeded() {
        cancelPictureInPictureStartRetryTask()
        if pictureInPictureController?.isPictureInPictureActive == true {
            pictureInPictureController?.stopPictureInPicture()
        }
        engine.stopPictureInPictureIfNeeded()
        syncPictureInPictureState()
    }

    private var isAppInBackground: Bool {
        UIApplication.shared.applicationState == .background
    }

    private func handlePictureInPictureWillStop() {
        shouldPausePlaybackAfterPictureInPictureStops = isAppInBackground
        guard shouldPausePlaybackAfterPictureInPictureStops else { return }

        // A user dismissed PiP while the app is still backgrounded. Do not let the
        // normal inline-recovery path turn that explicit dismissal into audio-only playback.
        pictureInPictureInlineRecoveryTask?.cancel()
        pictureInPictureInlineRecoveryTask = nil
        cancelTransientSystemOverlayPlaybackPreservation()
        pause()
    }

    private func handlePictureInPictureDidStop(isNativeController: Bool) {
        if isNativeController {
            isNativePictureInPictureActive = false
        }

        let shouldPause = shouldPausePlaybackAfterPictureInPictureStops || isAppInBackground
        shouldPausePlaybackAfterPictureInPictureStops = false
        syncPictureInPictureState()
        releasePictureInPictureControllerIfDisabled()

        guard !shouldPause else {
            pictureInPictureInlineRecoveryTask?.cancel()
            pictureInPictureInlineRecoveryTask = nil
            cancelTransientSystemOverlayPlaybackPreservation()
            pause()
            return
        }
        schedulePictureInPictureInlineRecovery()
    }

    private func restoreUserInterfaceAfterPictureInPictureStopIfNeeded() async -> Bool {
        if shouldPausePlaybackAfterPictureInPictureStops || isAppInBackground {
            shouldPausePlaybackAfterPictureInPictureStops = true
            pictureInPictureInlineRecoveryTask?.cancel()
            pictureInPictureInlineRecoveryTask = nil
            cancelTransientSystemOverlayPlaybackPreservation()
            pause()
            return false
        }
        return await restoreUserInterfaceForPictureInPictureStop?() ?? true
    }

    func restoreInlinePlaybackFromPictureInPictureIfNeeded() async -> Bool {
        syncPictureInPictureState()
        guard isPictureInPictureActive else { return false }
        // This path is driven by the already-visible player when the app becomes active.
        // Route restoration is only needed for the system PiP restore delegate.
        stopPictureInPictureIfNeeded()
        schedulePictureInPictureInlineRecovery()
        return true
    }

    private func schedulePictureInPictureInlineRecovery(delayNanoseconds: UInt64 = 180_000_000) {
        pictureInPictureInlineRecoveryTask?.cancel()
        pictureInPictureInlineRecoveryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard let self,
                  !Task.isCancelled,
                  !self.isTerminated
            else { return }
            self.pictureInPictureInlineRecoveryTask = nil
            self.recoverInlinePlaybackAfterPictureInPictureStop()
        }
    }

    private func recoverInlinePlaybackAfterPictureInPictureStop() {
        guard !isTerminated else { return }
        syncPictureInPictureState()
        guard ActivePlaybackCoordinator.shared.isActive(self) else { return }

        if timeObserver == nil {
            startTimeObserver()
        }
        if surfaceView != nil {
            engine.recoverSurface()
            refreshSurfaceLayout()
            stabilizeSurfaceLayoutAfterGeometryChange()
        }
        configurePictureInPictureIfNeeded()

        guard engine.hasMedia else {
            if wantsAutoplay {
                prepareMediaAndPlay()
            }
            return
        }

        if wantsAutoplay {
            engine.play()
            engine.setPlaybackRate(playbackRate.rawValue)
        }

        let snapshot = engine.snapshot(durationHint: durationHint)
        if let snapshotTime = snapshot.currentTime {
            _ = updatePlaybackTime(snapshotTime, countsAsNaturalPlayback: false)
        }
        if let snapshotDuration = snapshot.duration {
            updateDuration(snapshotDuration)
        }
        if hasPresentedPlayback, surfaceView != nil {
            isPlaybackSurfaceReady = true
            currentPlaybackSurfaceReadyGeneration = surfaceAttachmentGeneration
            isCurrentPlaybackSurfaceReadyForDisplay = true
        }
        if isPreparing {
            isPreparing = false
        }
        if isBuffering,
           hasPresentedPlayback,
           snapshot.isPlaying,
           !isAwaitingAppBackgroundSurfaceRecovery {
            isBuffering = false
        }
        refreshPlaybackState()
        rescheduleTimeObserverIfNeeded(force: true)
    }

    private func prepareMediaAndPlay() {
        guard !isTerminated else { return }
        guard mediaPreparationTask == nil else { return }
        let baselineSurfaceGeneration = surfaceAttachmentGeneration
        guard canActivatePlayback(generation: baselineSurfaceGeneration)
        else { return }
        isPreparing = true
        loadingProgress = max(loadingProgress, 0.12)
        playbackPhase = .preparing
        recoveryAttemptCount = 0
        PlayerMetricsLog.logger.info(
            "prepareRequested id=\(self.metricsID, privacy: .public) elapsedMs=\(PlayerMetricsLog.elapsedMilliseconds(since: self.metricsStartTime), format: .fixed(precision: 1), privacy: .public)"
        )
        PlayerMetricsLog.record(.prepareRequested, metricsID: metricsID, title: title, message: elapsedMessage())
        mediaPreparationGeneration &+= 1
        let preparationGeneration = mediaPreparationGeneration
        pendingEngineFirstFrameTime = nil
        let preparationSource = streamSourceForPreparation()
        startStartupMediaWarmup(for: preparationSource)
        mediaPreparationTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let signpostState = PlayerMetricsLog.beginSignpostedInterval(
                "PlayerPrepare",
                message: "id=\(self.metricsID) media=\(self.engine.hasMedia)"
            )
            var signpostMessage = "id=\(self.metricsID) preparing"
            defer {
                PlayerMetricsLog.endSignpostedInterval(
                    "PlayerPrepare",
                    signpostState,
                    message: signpostMessage
                )
            }
            do {
                try await self.engine.prepare(source: preparationSource)
                guard !Task.isCancelled,
                      !self.isTerminated,
                      preparationGeneration == self.mediaPreparationGeneration,
                      self.canActivatePlayback(generation: baselineSurfaceGeneration)
                else {
                    self.clearMediaPreparationTaskIfCurrent(preparationGeneration)
                    return
                }
                PlayerMetricsLog.logger.info(
                    "prepareReturned id=\(self.metricsID, privacy: .public) elapsedMs=\(PlayerMetricsLog.elapsedMilliseconds(since: self.metricsStartTime), format: .fixed(precision: 1), privacy: .public)"
                )
                PlayerMetricsLog.record(.prepareReturned, metricsID: self.metricsID, title: self.title, message: self.elapsedMessage())
                self.prepareElapsedMilliseconds = self.elapsedMilliseconds()
                self.clearMediaPreparationTaskIfCurrent(preparationGeneration)
                self.loadingProgress = max(self.loadingProgress, 0.72)
                self.refreshSeamlessPlaybackHandoffResumeTarget()
                let didApplyPendingResume = self.applyPendingStartupResumeIfPossible()
                if didApplyPendingResume {
                    // A cloud/local resume arrived while the engine was preparing.
                } else if self.startupResumePolicy == .immediate {
                    self.applyImmediateResumeTimeIfNeeded()
                }
                if self.wantsAutoplay {
                    if !didApplyPendingResume {
                        self.startPreparedPlayback()
                    }
                } else {
                    self.isPreparing = false
                    self.refreshPlaybackState()
                }
                signpostMessage = "id=\(self.metricsID) success elapsed=\(self.elapsedMessage())"
            } catch {
                guard !Task.isCancelled,
                      !self.isTerminated,
                      preparationGeneration == self.mediaPreparationGeneration,
                      self.canActivatePlayback(generation: baselineSurfaceGeneration)
                else {
                    self.clearMediaPreparationTaskIfCurrent(preparationGeneration)
                    return
                }
                PlayerMetricsLog.logger.error(
                    "prepareFailed id=\(self.metricsID, privacy: .public) elapsedMs=\(PlayerMetricsLog.elapsedMilliseconds(since: self.metricsStartTime), format: .fixed(precision: 1), privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
                PlayerMetricsLog.record(.failed, metricsID: self.metricsID, title: self.title, message: "\(self.elapsedMessage()) \(error.localizedDescription)")
                self.prepareElapsedMilliseconds = self.elapsedMilliseconds()
                self.clearMediaPreparationTaskIfCurrent(preparationGeneration)
                self.recordPlaybackFailure(message: error.localizedDescription, reason: self.engine.lastFailureReason)
                self.isPreparing = false
                self.onPlaybackFailureWithReason?(self.errorMessage, self.lastFailureReason)
                self.onPlaybackFailure?(self.errorMessage)
                signpostMessage = "id=\(self.metricsID) failed \(error.localizedDescription)"
            }
        }
    }

    private func startStartupMediaWarmup(for source: PlayerStreamSource) {
        startupMediaWarmupTask?.cancel()
        startupMediaWarmupTask = nil
        let playbackTime = source.resumeTime > 0.25 ? source.resumeTime : nil
        guard let videoURL = source.videoURL,
              let audioURL = source.audioURL,
              let videoStream = source.videoStream,
              let audioStream = source.audioStream,
              videoStream.segmentBase?.indexByteRange != nil,
              audioStream.segmentBase?.indexByteRange != nil
        else { return }

        let videoTracks = [
            HLSBridgeTrack(
                url: videoURL,
                fallbackURLs: videoStream.backupPlayURLs(cdnPreference: source.cdnPreference),
                stream: videoStream,
                mediaType: .video,
                dynamicRange: source.dynamicRange
            )
        ]
        let audioTrack = HLSBridgeTrack(
            url: audioURL,
            fallbackURLs: audioStream.fallbackPlayURLs(
                cdnPreference: source.cdnPreference,
                selectedURL: audioURL
            ),
            stream: audioStream,
            mediaType: .audio
        )
        let headers = source.httpHeaders
        let metricsID = source.metricsID
        let title = source.title
        let targetDescription = playbackTime.map { String(format: "%.2fs", $0) } ?? "startup"
        PlayerMetricsLog.record(
            .manifestStage,
            metricsID: metricsID,
            title: title,
            message: "prepareWarm=queued target=\(targetDescription) video=\(videoTracks.count)"
        )

        startupMediaWarmupTask = Task.detached(priority: .utility) { [videoTracks, audioTrack, headers, metricsID, title, playbackTime] in
            let start = CACurrentMediaTime()
            let didWarm = await LocalHLSBridge.warmup(
                videoTracks: videoTracks,
                audioTrack: audioTrack,
                headers: headers,
                around: playbackTime
            )
            guard !Task.isCancelled else { return }
            let elapsed = PlayerMetricsLog.elapsedMilliseconds(since: start)
            await PlayerMetricsLog.record(
                .manifestStage,
                metricsID: metricsID,
                title: title,
                message: "prepareWarm=\(didWarm ? "ok" : "skip") target=\(targetDescription) elapsed=\(String(format: "%.0fms", elapsed))"
            )
        }
    }

    private func streamSourceForPreparation() -> PlayerStreamSource {
        let pendingResumeTime = pendingStartupResume?.time ?? 0
        let currentResumeTime = currentTime.isFinite ? max(currentTime, 0) : 0
        let resumeTarget: TimeInterval
        if currentResumeTime > 0.25 {
            resumeTarget = currentResumeTime
        } else if pendingResumeTime > 0.25 {
            resumeTarget = pendingResumeTime
        } else {
            resumeTarget = streamSource.resumeTime
        }
        guard resumeTarget.isFinite, resumeTarget > 0.25 else { return streamSource }
        return streamSource.withResumeTime(resumeTarget)
    }

    private func seekRecoveryPreparationSource(targetTime: TimeInterval?) -> PlayerStreamSource {
        guard let targetTime,
              targetTime.isFinite,
              targetTime > 0.25
        else {
            return streamSourceForPreparation()
        }
        return streamSourceForPreparation().withResumeTime(targetTime)
    }

    private func startPreparedPlayback() {
        guard !isTerminated else { return }
        guard engine.hasMedia else { return }
        guard canActivatePlayback() else { return }
        wantsAutoplay = true
        isPreparing = false
        isBuffering = !hasPresentedPlayback || isAwaitingAppBackgroundSurfaceRecovery
        playbackPhase = hasPresentedPlayback && !isAwaitingAppBackgroundSurfaceRecovery
            ? .playing
            : (hasPresentedPlayback ? .buffering : .waitingForFirstFrame)
        loadingProgress = max(loadingProgress, 0.78)
        isPlaying = true
        if !hasPresentedPlayback {
            engine.setTemporaryAudioSuppressed(true)
        }
        PlayerMetricsLog.signpostEvent(
            "PlayerPlayback",
            message: "id=\(metricsID) start hasPresented=\(hasPresentedPlayback)"
        )
        PlayerMetricsLog.logger.info(
            "playRequested id=\(self.metricsID, privacy: .public) elapsedMs=\(PlayerMetricsLog.elapsedMilliseconds(since: self.metricsStartTime), format: .fixed(precision: 1), privacy: .public)"
        )
        PlayerMetricsLog.record(.playRequested, metricsID: metricsID, title: title, message: elapsedMessage())
        engine.play()
        engine.setPlaybackRate(playbackRate.rawValue)
        if startupResumePolicy == .deferred {
            applyResumeTimeIfNeeded()
        } else {
            scheduleImmediateResumeCorrectionIfNeeded()
        }
        refreshPlaybackState()
        invalidatePictureInPicturePlaybackState()
        schedulePlaybackRecoveryWatchdog(reason: hasPresentedPlayback ? .stall : .firstFrame)
    }

    @discardableResult
    private func applyPendingStartupResumeIfPossible() -> Bool {
        guard let pendingResume = pendingStartupResume, engine.hasMedia else { return false }
        guard canActivatePlayback() else { return false }
        let signpostState = PlayerMetricsLog.beginSignpostedInterval(
            "PlayerStartupResume",
            message: "reason=\(pendingResume.reason) target=\(String(format: "%.2f", pendingResume.time))"
        )
        var signpostMessage = "reason=\(pendingResume.reason) pending"
        defer {
            PlayerMetricsLog.endSignpostedInterval(
                "PlayerStartupResume",
                signpostState,
                message: signpostMessage
            )
        }
        let snapshot = engine.snapshot(durationHint: durationHint)
        let currentPlaybackTime = max(snapshot.currentTime ?? 0, currentTime)
        guard pendingResume.time > currentPlaybackTime + forcedPlaybackTimeGuardTolerance
                || currentPlaybackTime <= forcedPlaybackTimeGuardTolerance
        else {
            PlayerMetricsLog.record(
                .resumeDecision,
                metricsID: metricsID,
                title: title,
                message: "player skipped reason=\(pendingResume.reason) target=\(String(format: "%.2fs", pendingResume.time)) current=\(String(format: "%.2fs", currentPlaybackTime))"
            )
            self.pendingStartupResume = nil
            signpostMessage = "reason=\(pendingResume.reason) skipped current=\(String(format: "%.2f", currentPlaybackTime))"
            return false
        }
        let seekStart = CACurrentMediaTime()
        guard let time = engine.seek(toTime: pendingResume.time) else {
            signpostMessage = "reason=\(pendingResume.reason) failed no-seek"
            return false
        }
        let seekElapsed = PlayerMetricsLog.elapsedMilliseconds(since: seekStart)
        self.pendingStartupResume = nil
        updatePlaybackTime(time, force: true, countsAsNaturalPlayback: false)
        beginStartupResumeRecoveryTracking(
            reason: pendingResume.reason,
            targetTime: pendingResume.time,
            appliedTime: time,
            startedAt: seekStart,
            engineElapsedMilliseconds: seekElapsed
        )
        PlayerMetricsLog.logger.info(
            "startupResumeSeek id=\(self.metricsID, privacy: .public) reason=\(pendingResume.reason, privacy: .public) target=\(pendingResume.time, format: .fixed(precision: 2), privacy: .public) applied=\(time, format: .fixed(precision: 2), privacy: .public) engineMs=\(seekElapsed, format: .fixed(precision: 1), privacy: .public)"
        )
        PlayerMetricsLog.record(
            .resumeDecision,
            metricsID: metricsID,
            title: title,
            message: "player applied reason=\(pendingResume.reason) target=\(String(format: "%.2fs", pendingResume.time)) applied=\(String(format: "%.2fs", time)) engine=\(String(format: "%.0fms", seekElapsed))"
        )
        signpostMessage = "reason=\(pendingResume.reason) applied=\(String(format: "%.2f", time)) engine=\(String(format: "%.1f", seekElapsed))ms"
        if wantsAutoplay {
            resumePreparedPlaybackAfterSeek()
        } else {
            refreshPlaybackState()
            invalidatePictureInPicturePlaybackState()
        }
        return true
    }

    private func resumePreparedPlaybackAfterSeek() {
        guard !isTerminated else { return }
        guard engine.hasMedia else { return }
        guard canActivatePlayback() else { return }
        wantsAutoplay = true
        isPreparing = false
        isPlaying = true
        if hasPresentedPlayback {
            playbackPhase = isBuffering ? .buffering : .playing
        } else {
            isBuffering = true
            loadingProgress = max(loadingProgress, 0.78)
            playbackPhase = .waitingForFirstFrame
        }
        engine.recoverSurface()
        refreshSurfaceLayout()
        engine.play()
        engine.setPlaybackRate(playbackRate.rawValue)
        refreshPlaybackState()
        invalidatePictureInPicturePlaybackState()
        if !hasPresentedPlayback {
            schedulePlaybackRecoveryWatchdog(reason: .firstFrame)
        } else if isBuffering {
            schedulePlaybackRecoveryWatchdog(reason: .stall)
        }
    }

    private func cancelStartupResumeCorrectionAfterUserSeek() {
        deferredStartupResumeTask?.cancel()
        deferredStartupResumeTask = nil
        cancelStartupResumeRetryTask()
        cancelStartupResumeRecoveryTracking()
        if resumeTime > 0.25 {
            didApplyResumeTime = true
        }
    }

    private func beginStartupResumeRecoveryTracking(
        reason: String,
        targetTime: TimeInterval,
        appliedTime: TimeInterval,
        startedAt: CFTimeInterval,
        engineElapsedMilliseconds: Double?
    ) {
        guard targetTime > 0.25 else { return }
        cancelStartupResumeRecoveryTracking()
        let metric = PendingStartupResumeRecoveryMetric(
            reason: reason,
            targetTime: targetTime,
            appliedTime: appliedTime,
            startedAt: startedAt,
            engineElapsedMilliseconds: engineElapsedMilliseconds
        )
        pendingResumeRecoveryMetric = metric
        let baselineSurfaceGeneration = surfaceAttachmentGeneration
        resumeRecoveryWatchdogTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.resumeRecoveryWatchdogDelayNanoseconds)
            guard !Task.isCancelled,
                  !self.isTerminated,
                  let pending = self.pendingResumeRecoveryMetric,
                  pending.id == metric.id,
                  self.hasCurrentSurface(generation: baselineSurfaceGeneration)
            else { return }
            let snapshot = self.engine.snapshot(durationHint: self.durationHint)
            if let snapshotTime = snapshot.currentTime,
               (snapshot.isPlaying || self.hasPresentedPlayback),
               self.isStartupResumeRecoveryMatch(currentTime: snapshotTime, pending: pending) {
                self.finishStartupResumeRecoveryMetric(
                    pending,
                    recovered: true,
                    currentTime: snapshotTime,
                    source: "watchdog"
                )
                return
            }
            self.finishStartupResumeRecoveryMetric(
                pending,
                recovered: false,
                currentTime: snapshot.currentTime ?? self.currentTime,
                source: "watchdog"
            )
        }
    }

    private func recordStartupResumeRecoveryIfNeeded(currentTime: TimeInterval, source: String) {
        guard let pending = pendingResumeRecoveryMetric else { return }
        guard isStartupResumeRecoveryMatch(currentTime: currentTime, pending: pending) else { return }
        finishStartupResumeRecoveryMetric(
            pending,
            recovered: true,
            currentTime: currentTime,
            source: source
        )
    }

    private func finishStartupResumeRecoveryMetric(
        _ pending: PendingStartupResumeRecoveryMetric,
        recovered: Bool,
        currentTime: TimeInterval,
        source: String
    ) {
        guard pendingResumeRecoveryMetric?.id == pending.id else { return }
        resumeRecoveryWatchdogTask?.cancel()
        resumeRecoveryWatchdogTask = nil
        pendingResumeRecoveryMetric = nil
        PlayerMetricsLog.record(
            .resumeRecovery,
            metricsID: metricsID,
            title: title,
            message: startupResumeRecoveryMessage(
                reason: pending.reason,
                targetTime: pending.targetTime,
                appliedTime: pending.appliedTime,
                elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: pending.startedAt),
                engineElapsedMilliseconds: pending.engineElapsedMilliseconds,
                currentTime: currentTime,
                recovered: recovered,
                source: source
            )
        )
    }

    private func startupResumeRecoveryMessage(
        reason: String,
        targetTime: TimeInterval,
        appliedTime: TimeInterval,
        elapsedMilliseconds: Double,
        engineElapsedMilliseconds: Double?,
        currentTime: TimeInterval,
        recovered: Bool,
        source: String
    ) -> String {
        var parts = [reason, "recovered=\(recovered)"]
        parts.append("target=\(String(format: "%.2fs", targetTime))")
        parts.append("applied=\(String(format: "%.2fs", appliedTime))")
        parts.append("current=\(String(format: "%.2fs", currentTime))")
        parts.append("total=\(String(format: "%.0fms", elapsedMilliseconds))")
        if let engineElapsedMilliseconds {
            parts.append("engine=\(String(format: "%.0fms", engineElapsedMilliseconds))")
        }
        parts.append("source=\(source)")
        return parts.joined(separator: " ")
    }

    private func isStartupResumeRecoveryMatch(currentTime: TimeInterval, pending: PendingStartupResumeRecoveryMetric) -> Bool {
        let targetTime = pending.targetTime
        let toleranceBefore = max(0.9, min(targetTime * 0.03, 1.8))
        let toleranceAfter = max(4.0, min(targetTime * 0.12, 10.0))
        return currentTime >= max(targetTime - toleranceBefore, 0)
            && currentTime <= targetTime + toleranceAfter
    }

    private func cancelStartupResumeRecoveryTracking() {
        resumeRecoveryWatchdogTask?.cancel()
        resumeRecoveryWatchdogTask = nil
        pendingResumeRecoveryMetric = nil
    }

    private func bindEngine(_ engine: PlayerRenderingEngine, restoreVolumeState: Bool) {
        engineCallbackGeneration &+= 1
        let callbackGeneration = engineCallbackGeneration
        if restoreVolumeState {
            engine.setVolume(volume)
            engine.setMuted(isMuted)
            engine.setPlaybackRate(playbackRate.rawValue)
        } else {
            volume = engine.volume
            isMuted = engine.isMuted
        }
        engine.onPlaybackStateChange = { [weak self] state in
            guard let self, self.isCurrentEngineCallbackGeneration(callbackGeneration) else { return }
            self.handleEnginePlaybackState(state)
        }
        engine.onPlaybackIntentChange = { [weak self] wantsPlayback in
            guard let self, self.isCurrentEngineCallbackGeneration(callbackGeneration) else { return }
            self.handleEnginePlaybackIntentChange(wantsPlayback)
        }
        engine.onLoadingProgressChange = { [weak self] progress in
            guard let self, self.isCurrentEngineCallbackGeneration(callbackGeneration) else { return }
            self.handleEngineLoadingProgress(progress)
        }
        engine.onFirstFrame = { [weak self] currentTime in
            guard let self, self.isCurrentEngineCallbackGeneration(callbackGeneration) else { return }
            self.handleEngineFirstFrame(currentTime)
        }
        engine.setViewModel(self)
        syncEngineDiagnostics(force: true)
    }

    private func isCurrentEngineCallbackGeneration(_ generation: Int) -> Bool {
        !isTerminated && engineCallbackGeneration == generation
    }

    private func startTimeObserver() {
        timeObserver?.invalidate()
        let timer = Timer(timeInterval: playbackStateRefreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      !self.isTerminated
                else { return }
                let baselineSurfaceGeneration = self.surfaceAttachmentGeneration
                guard self.hasCurrentSurface(generation: baselineSurfaceGeneration) else { return }
                self.refreshPlaybackState()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        timeObserver = timer
    }

    private func rescheduleTimeObserverIfNeeded(force: Bool = false) {
        let desiredInterval = desiredPlaybackStateRefreshInterval()
        guard force || timeObserver == nil || abs(desiredInterval - playbackStateRefreshInterval) > 0.05 else { return }
        playbackStateRefreshInterval = desiredInterval
        startTimeObserver()
    }

    private func desiredPlaybackStateRefreshInterval() -> TimeInterval {
        if isUserSeeking {
            return 0.08
        }
        if isPreparing || isBuffering || playbackPhase == .waitingForFirstFrame || playbackPhase == .recovering || playbackPhase == .seeking {
            return 0.35
        }
        if sponsorBlockEnabled, wantsAutoplay, engine.hasMedia {
            return 0.5
        }
        if wantsAutoplay || isPlaying {
            return playbackRate.rawValue > 1.15 ? 0.9 : 1.2
        }
        return 2.4
    }

    private func refreshPlaybackState() {
        guard !isTerminated else { return }
        guard ActivePlaybackCoordinator.shared.isActive(self) || !wantsAutoplay else { return }
        let baselineSurfaceGeneration = surfaceAttachmentGeneration
        syncEngineDiagnosticsForPeriodicRefresh()
        if let playbackErrorMessage = engine.playbackErrorMessage {
            errorMessage = playbackErrorMessage
            isPreparing = false
            isPlaying = false
            wantsAutoplay = false
            playbackPhase = .failed(playbackErrorMessage)
            invalidatePictureInPicturePlaybackState()
            syncRemotePlaybackControls()
            return
        }

        let snapshot = engine.snapshot(durationHint: durationHint)
        updateSeekBufferProgressIfNeeded(snapshot)
        var acceptedSnapshotTime: TimeInterval?
        if let snapshotTime = snapshot.currentTime,
           updatePlaybackTime(snapshotTime) {
            acceptedSnapshotTime = currentTime
            if isPreparing {
                isPreparing = false
            }
            if isBuffering,
               hasPresentedPlayback,
               snapshot.isPlaying,
               !isAwaitingAppBackgroundSurfaceRecovery {
                isBuffering = false
            }
        }
        if let snapshotDuration = snapshot.duration {
            updateDuration(snapshotDuration)
        }
        if !hasPresentedPlayback,
           snapshot.isPlaying,
           hasCurrentSurface(generation: baselineSurfaceGeneration),
           acceptFirstFramePresentationFallback(
               currentTime: snapshot.currentTime,
               source: "snapshot"
           ) {
            acceptedSnapshotTime = snapshot.currentTime ?? currentTime
        }
        if wantsAutoplay,
           engine.hasMedia,
           !snapshot.isPlaying,
           errorMessage == nil,
           hasCurrentSurface(generation: baselineSurfaceGeneration) {
            engine.play()
            engine.setPlaybackRate(playbackRate.rawValue)
            if !hasPresentedPlayback {
                isBuffering = true
            }
        }
        let shouldDisplayPlaying = snapshot.isPlaying || (wantsAutoplay && engine.hasMedia && errorMessage == nil)
        if isPlaying != shouldDisplayPlaying {
            isPlaying = shouldDisplayPlaying
        }
        if !clearUserSeekOverlayAfterPlaybackStartsIfNeeded(snapshot: snapshot) {
            isPlaying = false
            isPreparing = false
            isBuffering = true
            playbackPhase = .seeking
            rescheduleTimeObserverIfNeeded(force: true)
            return
        }
        updatePhaseFromSnapshot(snapshot)
        if isSeekable != snapshot.isSeekable {
            isSeekable = snapshot.isSeekable
        }
        syncPictureInPictureState()
        if let snapshotTime = acceptedSnapshotTime {
            skipSponsorBlockSegmentIfNeeded(at: snapshotTime)
        }
        rescheduleTimeObserverIfNeeded()
    }

    private func updatePhaseFromSnapshot(_ snapshot: PlayerPlaybackSnapshot) {
        guard errorMessage == nil else {
            playbackPhase = .failed(errorMessage)
            return
        }
        if isAwaitingAppBackgroundSurfaceRecovery {
            isBuffering = true
            playbackPhase = .buffering
            return
        }
        if isPreparing {
            playbackPhase = .preparing
        } else if playbackPhase == .recovering {
            if hasPresentedPlayback, snapshot.isPlaying {
                playbackPhase = .playing
            }
        } else if isBuffering {
            playbackPhase = hasPresentedPlayback ? .buffering : .waitingForFirstFrame
        } else if snapshot.isPlaying {
            playbackPhase = hasPresentedPlayback ? .playing : .waitingForFirstFrame
        } else if engine.hasMedia {
            playbackPhase = wantsAutoplay ? .ready : .paused
        } else {
            playbackPhase = .idle
        }
    }

    private func applyResumeTimeIfNeeded() {
        guard !didApplyResumeTime, resumeTime > 0.25 else { return }
        didApplyResumeTime = true
        let milliseconds = Int32(min(resumeTime * 1000, Double(Int32.max)))
        let generation = mediaPreparationGeneration
        let baselineSurfaceGeneration = surfaceAttachmentGeneration
        let signpostState = PlayerMetricsLog.beginSignpostedInterval(
            "PlayerStartupResume",
            message: "reason=deferredStartup target=\(String(format: "%.2f", resumeTime))"
        )
        deferredStartupResumeTask?.cancel()
        deferredStartupResumeTask = Task { @MainActor [weak self] in
            guard let self else {
                PlayerMetricsLog.endSignpostedInterval(
                    "PlayerStartupResume",
                    signpostState,
                    message: "reason=deferredStartup cancelled"
                )
                return
            }
            var signpostMessage = "reason=deferredStartup waiting"
            defer {
                if self.mediaPreparationGeneration == generation {
                    self.deferredStartupResumeTask = nil
                }
                PlayerMetricsLog.endSignpostedInterval(
                    "PlayerStartupResume",
                    signpostState,
                    message: signpostMessage
                )
            }
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled,
                  !self.isTerminated,
                  self.mediaPreparationGeneration == generation,
                  self.hasCurrentSurface(generation: baselineSurfaceGeneration),
                  ActivePlaybackCoordinator.shared.isActive(self)
            else {
                signpostMessage = "reason=deferredStartup cancelled"
                return
            }
            let seekStart = CACurrentMediaTime()
            if let time = self.engine.seek(toTime: TimeInterval(milliseconds) / 1000) {
                let seekElapsed = PlayerMetricsLog.elapsedMilliseconds(since: seekStart)
                self.updatePlaybackTime(time, force: true, countsAsNaturalPlayback: false)
                self.beginStartupResumeRecoveryTracking(
                    reason: "deferredStartup",
                    targetTime: self.resumeTime,
                    appliedTime: time,
                    startedAt: seekStart,
                    engineElapsedMilliseconds: seekElapsed
                )
                PlayerMetricsLog.record(
                    .resumeDecision,
                    metricsID: self.metricsID,
                    title: self.title,
                    message: "player applied reason=deferredStartup target=\(String(format: "%.2fs", self.resumeTime)) applied=\(String(format: "%.2fs", time)) engine=\(String(format: "%.0fms", seekElapsed))"
                )
                signpostMessage = "reason=deferredStartup applied=\(String(format: "%.2f", time)) engine=\(String(format: "%.1f", seekElapsed))ms"
            } else {
                signpostMessage = "reason=deferredStartup failed no-seek"
            }
            if self.wantsAutoplay,
               self.canActivatePlayback(generation: baselineSurfaceGeneration) {
                self.engine.play()
                self.engine.setPlaybackRate(self.playbackRate.rawValue)
            }
        }
    }

    private func applyImmediateResumeTimeIfNeeded() {
        guard !didApplyResumeTime, resumeTime > 0.25 else { return }
        didApplyResumeTime = true
        seekToStartupResumeTime(reason: "prepareReturned")
        scheduleImmediateResumeCorrectionIfNeeded()
    }

    private func scheduleImmediateResumeCorrectionIfNeeded() {
        guard startupResumePolicy == .immediate, resumeTime > 0.25 else { return }
        cancelStartupResumeRetryTask()
        let targetTime = resumeTime
        let retryGeneration = advanceStartupResumeRetryGeneration()
        startupResumeRetryTask = Task { @MainActor [weak self] in
            let retryDelays: [UInt64] = [
                90_000_000,
                180_000_000,
                320_000_000,
                520_000_000,
                850_000_000
            ]
            for delay in retryDelays {
                try? await Task.sleep(nanoseconds: delay)
                guard let self,
                      !Task.isCancelled,
                      !self.isTerminated,
                      self.startupResumeRetryGeneration == retryGeneration,
                      self.canActivatePlayback()
                else { return }
                let snapshotTime = self.engine.snapshot(durationHint: self.durationHint).currentTime
                let currentPlaybackTime = max(snapshotTime ?? 0, self.currentTime)
                if self.hasReachedStartupResumeTarget(
                    currentPlaybackTime,
                    targetTime: targetTime
                ) {
                    self.recordStartupResumeRecoveryIfNeeded(currentTime: currentPlaybackTime, source: "retry")
                    PlayerMetricsLog.record(
                        .resumeDecision,
                        metricsID: self.metricsID,
                        title: self.title,
                        message: "player verified reason=retry target=\(String(format: "%.2fs", targetTime)) current=\(String(format: "%.2fs", currentPlaybackTime))"
                    )
                    self.clearStartupResumeRetryTaskIfCurrent(retryGeneration)
                    return
                }
                self.seekToStartupResumeTime(reason: "retry")
                if self.wantsAutoplay,
                   self.canActivatePlayback() {
                    self.engine.play()
                    self.engine.setPlaybackRate(self.playbackRate.rawValue)
                }
            }
            self?.clearStartupResumeRetryTaskIfCurrent(retryGeneration)
        }
    }

    @discardableResult
    private func seekToStartupResumeTime(reason: String) -> Bool {
        guard resumeTime > 0.25, engine.hasMedia else { return false }
        guard canActivatePlayback() else { return false }
        let snapshotTime = engine.snapshot(durationHint: durationHint).currentTime
        let currentPlaybackTime = max(snapshotTime ?? 0, currentTime)
        guard !hasReachedStartupResumeTarget(
            currentPlaybackTime,
            targetTime: resumeTime
        ) else {
            PlayerMetricsLog.record(
                .resumeDecision,
                metricsID: metricsID,
                title: title,
                message: "player skipped reason=\(reason) target=\(String(format: "%.2fs", resumeTime)) current=\(String(format: "%.2fs", currentPlaybackTime))"
            )
            return false
        }
        let signpostState = PlayerMetricsLog.beginSignpostedInterval(
            "PlayerStartupResume",
            message: "reason=\(reason) target=\(String(format: "%.2f", resumeTime))"
        )
        var signpostMessage = "reason=\(reason) pending"
        defer {
            PlayerMetricsLog.endSignpostedInterval(
                "PlayerStartupResume",
                signpostState,
                message: signpostMessage
            )
        }
        let seekStart = CACurrentMediaTime()
        guard let time = engine.seek(toTime: resumeTime) else {
            signpostMessage = "reason=\(reason) failed no-seek"
            return false
        }
        let seekElapsed = PlayerMetricsLog.elapsedMilliseconds(since: seekStart)
        updatePlaybackTime(time, force: true, countsAsNaturalPlayback: false)
        beginStartupResumeRecoveryTracking(
            reason: reason,
            targetTime: resumeTime,
            appliedTime: time,
            startedAt: seekStart,
            engineElapsedMilliseconds: seekElapsed
        )
        PlayerMetricsLog.logger.info(
            "startupResumeSeek id=\(self.metricsID, privacy: .public) reason=\(reason, privacy: .public) target=\(self.resumeTime, format: .fixed(precision: 2), privacy: .public) applied=\(time, format: .fixed(precision: 2), privacy: .public) engineMs=\(seekElapsed, format: .fixed(precision: 1), privacy: .public)"
        )
        PlayerMetricsLog.record(
            .resumeDecision,
            metricsID: metricsID,
            title: title,
            message: "player applied reason=\(reason) target=\(String(format: "%.2fs", resumeTime)) applied=\(String(format: "%.2fs", time)) engine=\(String(format: "%.0fms", seekElapsed))"
        )
        signpostMessage = "reason=\(reason) applied=\(String(format: "%.2f", time)) engine=\(String(format: "%.1f", seekElapsed))ms"
        return true
    }

    private func hasReachedStartupResumeTarget(
        _ currentPlaybackTime: TimeInterval,
        targetTime: TimeInterval
    ) -> Bool {
        currentPlaybackTime.isFinite
            && currentPlaybackTime >= max(targetTime - startupResumeVerificationToleranceBefore, 0)
    }

    @discardableResult
    private func updatePlaybackTime(
        _ time: TimeInterval,
        force: Bool = false,
        countsAsNaturalPlayback: Bool = true
    ) -> Bool {
        let normalizedTime = max(time, 0)
        guard force || !shouldIgnoreStalePlaybackTimeAfterForcedSeek(normalizedTime) else {
            return false
        }
        guard force || !shouldIgnoreStartupPlaybackTimeOutlier(normalizedTime) else {
            return false
        }
        if countsAsNaturalPlayback, normalizedTime > 0 {
            cancelDeferredBufferingIndicator()
            if hasPresentedPlayback, !isAwaitingAppBackgroundSurfaceRecovery {
                isBuffering = false
                loadingProgress = 1
            }
            recordStartupResumeRecoveryIfNeeded(currentTime: normalizedTime, source: "playbackTime")
            recordSeekRecoveryIfNeeded(currentTime: normalizedTime, source: "playbackTime")
        }
        if force || (currentTime <= 0 && normalizedTime > 0) || abs(currentTime - normalizedTime) >= 0.2 {
            currentTime = normalizedTime
            playbackClock.update(time: normalizedTime, duration: displayDuration, force: force)
            syncRemotePlaybackControls(forceNowPlayingTimeUpdate: force)
        } else if force {
            playbackClock.update(time: normalizedTime, duration: displayDuration, force: true)
            syncRemotePlaybackControls(forceNowPlayingTimeUpdate: true)
        }
        if force {
            installForcedPlaybackTimeGuard(for: normalizedTime)
        } else {
            clearForcedPlaybackTimeGuardIfSatisfied(by: normalizedTime)
        }
        return true
    }

    private func handleEngineFirstFrame(_ time: TimeInterval) {
        guard !isTerminated else { return }
        syncEnginePresentationSize()
        guard surfaceView != nil else {
            pendingEngineFirstFrameTime = max(time, 0)
            return
        }
        acceptEngineFirstFrame(time, source: "engine")
    }

    private func consumePendingEngineFirstFrameIfPossible() {
        guard let pendingEngineFirstFrameTime,
              !isTerminated,
              surfaceView != nil,
              engine.hasMedia,
              errorMessage == nil
        else { return }
        self.pendingEngineFirstFrameTime = nil
        acceptEngineFirstFrame(pendingEngineFirstFrameTime, source: "engine-deferred")
    }

    private func schedulePendingEngineFirstFrameConsumptionIfNeeded(generation: Int) {
        guard pendingEngineFirstFrameTime != nil else { return }
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self,
                  !self.isTerminated,
                  self.hasCurrentSurface(generation: generation)
            else { return }
            self.consumePendingEngineFirstFrameIfPossible()
        }
    }

    private func schedulePlaybackActivationAfterSurfaceAttachIfNeeded(generation: Int) {
        guard wantsAutoplay else { return }
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self,
                  !self.isTerminated,
                  self.hasCurrentSurface(generation: generation),
                  self.wantsAutoplay,
                  self.errorMessage == nil,
                  ActivePlaybackCoordinator.shared.isActive(self)
            else { return }
            if self.engine.hasMedia {
                self.startPreparedPlayback()
            } else {
                self.prepareMediaAndPlay()
            }
        }
    }

    private func acceptEngineFirstFrame(_ time: TimeInterval, source: String) {
        syncEngineDiagnostics(force: true)
        if isUserSeeking, wantsAutoplay {
            guard clearUserSeekOverlayAfterPlaybackStartsIfNeeded(
                snapshot: engine.snapshot(durationHint: durationHint)
            ) else {
                isPlaying = false
                isPreparing = false
                isBuffering = true
                playbackPhase = .seeking
                loadingProgress = max(loadingProgress, 0.22)
                rescheduleTimeObserverIfNeeded(force: true)
                return
            }
        }
        markPlaybackSurfaceReady()
        recordFirstFrameIfNeeded(currentTime: time, source: source)
        recordStartupResumeRecoveryIfNeeded(currentTime: time, source: source)
        recordSeekRecoveryIfNeeded(currentTime: time, source: source)
        if time > 0 {
            _ = updatePlaybackTime(time, force: currentTime <= 0, countsAsNaturalPlayback: false)
        }
    }

    private func recordFirstFrameIfNeeded(currentTime: TimeInterval, source: String) {
        guard !didRecordFirstFrameEvent else { return }
        didRecordFirstFrameEvent = true
        let normalizedTime = max(currentTime, 0)
        PlayerMetricsLog.signpostEvent(
            "PlayerFirstFrame",
            message: "source=\(source) current=\(String(format: "%.2f", normalizedTime))"
        )
        PlayerMetricsLog.logger.info(
            "firstFrame id=\(self.metricsID, privacy: .public) source=\(source, privacy: .public) elapsedMs=\(PlayerMetricsLog.elapsedMilliseconds(since: self.metricsStartTime), format: .fixed(precision: 1), privacy: .public) current=\(normalizedTime, format: .fixed(precision: 2), privacy: .public)"
        )
        PlayerMetricsLog.record(
            .firstFrame,
            metricsID: metricsID,
            title: title,
            message: "\(elapsedMessage()) source=\(source) time=\(String(format: "%.2f", normalizedTime))s"
        )
        firstFrameElapsedMilliseconds = elapsedMilliseconds()
    }

    private func markPlaybackSurfaceReady() {
        let shouldNotifyFirstFrame = !hasPresentedPlayback
        let wasAwaitingAppBackgroundSurfaceRecovery = isAwaitingAppBackgroundSurfaceRecovery
        cancelDeferredBufferingIndicator()
        playbackRecoveryWatchdogTask?.cancel()
        playbackRecoveryWatchdogTask = nil
        recoveryAttemptCount = 0
        isPlaybackSurfaceReady = true
        if surfaceView == nil {
            currentPlaybackSurfaceReadyGeneration = nil
            isCurrentPlaybackSurfaceReadyForDisplay = false
        } else {
            currentPlaybackSurfaceReadyGeneration = surfaceAttachmentGeneration
            isCurrentPlaybackSurfaceReadyForDisplay = true
        }
        surfaceReadinessConfirmationTask?.cancel()
        surfaceReadinessConfirmationTask = nil
        hasPresentedPlayback = true
        completeSeamlessPlaybackHandoffIfNeeded()
        engine.setTemporaryAudioSuppressed(false)
        if shouldNotifyFirstFrame {
            if startupMediaWarmupTask == nil {
                startStartupMediaWarmup(for: streamSourceForPreparation())
            }
            onFirstFramePresented?()
        }
        loadingProgress = 1
        isPreparing = false
        if wasAwaitingAppBackgroundSurfaceRecovery {
            // `AVPlayerLayer.isReadyForDisplay` can remain true after an item was
            // rebuilt following a long lock. Do not reveal the layer until the
            // video output has supplied fresh, advancing media timestamps.
            currentPlaybackSurfaceReadyGeneration = nil
            isCurrentPlaybackSurfaceReadyForDisplay = false
            isBuffering = true
            playbackPhase = .buffering
            return
        }
        isBuffering = false
        playbackPhase = .playing
    }

    private func installForcedPlaybackTimeGuard(for time: TimeInterval) {
        guard time > forcedPlaybackTimeGuardTolerance else {
            forcedPlaybackTimeGuard = nil
            return
        }
        forcedPlaybackTimeGuard = ForcedPlaybackTimeGuard(
            targetTime: time,
            expiresAt: CACurrentMediaTime() + forcedPlaybackTimeGuardDuration
        )
    }

    private func shouldIgnoreStalePlaybackTimeAfterForcedSeek(_ time: TimeInterval) -> Bool {
        guard let guardState = forcedPlaybackTimeGuard else { return false }
        guard CACurrentMediaTime() <= guardState.expiresAt else {
            forcedPlaybackTimeGuard = nil
            return false
        }
        let lowerBound = forcedPlaybackGuardLowerBound(for: guardState.targetTime)
        let upperBound = forcedPlaybackGuardUpperBound(for: guardState.targetTime)
        if isForcedPlaybackTimeSettled(time, for: guardState.targetTime) {
            forcedPlaybackTimeGuard = nil
            return false
        }

        guard currentTime >= lowerBound,
              currentTime <= upperBound
        else {
            return false
        }

        guard time < lowerBound || time > upperBound else {
            return false
        }

        PlayerMetricsLog.logger.info(
            "ignoredStalePlaybackTimeAfterSeek id=\(self.metricsID, privacy: .public) target=\(guardState.targetTime, format: .fixed(precision: 2), privacy: .public) current=\(self.currentTime, format: .fixed(precision: 2), privacy: .public) candidate=\(time, format: .fixed(precision: 2), privacy: .public)"
        )
        return true
    }

    private func clearForcedPlaybackTimeGuardIfSatisfied(by time: TimeInterval) {
        guard let guardState = forcedPlaybackTimeGuard else { return }
        if isForcedPlaybackTimeSettled(time, for: guardState.targetTime)
            || CACurrentMediaTime() > guardState.expiresAt {
            forcedPlaybackTimeGuard = nil
        }
    }

    private func isForcedPlaybackTimeSettled(_ time: TimeInterval, for targetTime: TimeInterval) -> Bool {
        let lowerBound = forcedPlaybackGuardLowerBound(for: targetTime)
        let upperBound = forcedPlaybackGuardUpperBound(for: targetTime)
        if let displayDuration,
           targetTime >= max(displayDuration - 0.35, 0) {
            return time >= lowerBound && time <= upperBound
        }
        return time >= targetTime + forcedPlaybackTimeSettleAdvance
            && time <= upperBound
    }

    private func forcedPlaybackGuardLowerBound(for targetTime: TimeInterval) -> TimeInterval {
        max(targetTime - forcedPlaybackTimeRollbackTolerance, 0)
    }

    private func forcedPlaybackGuardUpperBound(for targetTime: TimeInterval) -> TimeInterval {
        targetTime + forcedPlaybackTimeForwardJumpTolerance
    }

    private func shouldIgnoreStartupPlaybackTimeOutlier(_ time: TimeInterval) -> Bool {
        guard resumeTime < 10,
              !didApplyResumeTime,
              currentTime < 2,
              time - currentTime > 8,
              PlayerMetricsLog.elapsedMilliseconds(since: metricsStartTime) < 15_000,
              ignoredStartupPlaybackTimeOutliers < 24
        else { return false }
        ignoredStartupPlaybackTimeOutliers += 1
        PlayerMetricsLog.logger.info(
            "ignoredStartupPlaybackTimeOutlier id=\(self.metricsID, privacy: .public) current=\(self.currentTime, format: .fixed(precision: 2), privacy: .public) candidate=\(time, format: .fixed(precision: 2), privacy: .public)"
        )
        return true
    }

    private func updateDuration(_ newDuration: TimeInterval) {
        guard newDuration > 0 else { return }
        if let duration, abs(duration - newDuration) < 0.5 {
            return
        }
        duration = newDuration
        playbackClock.update(time: currentTime, duration: displayDuration, force: true)
        syncRemotePlaybackControls()
    }

    private func recordPlaybackFailure(message: String, reason: HLSBridgeFailureReason?) {
        errorMessage = message
        lastFailureReason = reason
    }

    private func syncRemotePlaybackControls(forceNowPlayingTimeUpdate: Bool = false) {
        guard shouldPublishNowPlayingMetadata else {
            PlayerRemoteControlSession.shared.clearIfCurrent(self)
            return
        }
        PlayerRemoteControlSession.shared.activate(
            for: self,
            forceNowPlayingTimeUpdate: forceNowPlayingTimeUpdate
        )
    }

    private func handleEnginePlaybackState(_ state: PlayerEnginePlaybackState) {
        guard !isTerminated else { return }
        let wasPlaybackEnded = playbackPhase == .ended
        syncEngineDiagnostics()
        switch state {
        case .idle:
            cancelDeferredBufferingIndicator()
            isBuffering = false
            playbackPhase = .idle
        case .preparing:
            cancelDeferredBufferingIndicator()
            errorMessage = nil
            lastFailureReason = nil
            isPreparing = true
            isBuffering = false
            if !hasPresentedPlayback {
                isPlaybackSurfaceReady = false
                currentPlaybackSurfaceReadyGeneration = nil
                isCurrentPlaybackSurfaceReadyForDisplay = false
            }
            loadingProgress = max(loadingProgress, 0.18)
            playbackPhase = .preparing
        case .ready:
            cancelDeferredBufferingIndicator()
            isPreparing = false
            isBuffering = false
            loadingProgress = max(loadingProgress, 0.86)
            errorMessage = nil
            lastFailureReason = nil
            playbackPhase = hasPresentedPlayback ? .ready : .waitingForFirstFrame
            if wantsAutoplay {
                schedulePlaybackRecoveryWatchdog(reason: .firstFrame)
            }
        case .buffering:
            guard !isSurfaceMigrating else {
                isPreparing = false
                isBuffering = false
                isPlaying = true
                playbackPhase = .playing
                return
            }
            isPreparing = false
            loadingProgress = max(loadingProgress, isUserSeeking && hasPresentedPlayback ? 0.22 : 0.72)
            if hasPresentedPlayback {
                if isBuffering {
                    playbackPhase = .buffering
                    schedulePlaybackRecoveryWatchdog(reason: .stall)
                } else {
                    playbackPhase = .playing
                    scheduleDeferredBufferingIndicator()
                }
            } else {
                if !isBuffering {
                    bufferingCount += 1
                    lastBufferingElapsedMilliseconds = elapsedMilliseconds()
                    notifyBufferingPressureIfNeeded()
                }
                isBuffering = true
                playbackPhase = .waitingForFirstFrame
                PlayerMetricsLog.record(.buffering, metricsID: metricsID, title: title, message: elapsedMessage())
                schedulePlaybackRecoveryWatchdog(reason: .firstFrame)
            }
        case .playing:
            if isUserSeeking {
                if wantsAutoplay {
                    guard clearUserSeekOverlayAfterPlaybackStartsIfNeeded(
                        snapshot: engine.snapshot(durationHint: durationHint)
                    ) else {
                        isPlaying = false
                        isPreparing = false
                        isBuffering = true
                        playbackPhase = .seeking
                        loadingProgress = max(loadingProgress, 0.22)
                        rescheduleTimeObserverIfNeeded(force: true)
                        return
                    }
                } else {
                    wantsAutoplay = false
                    isPlaying = false
                    isPreparing = false
                    isBuffering = true
                    playbackPhase = .seeking
                    loadingProgress = max(loadingProgress, 0.22)
                    engine.pause()
                    engine.setTemporaryAudioSuppressed(true)
                    rescheduleTimeObserverIfNeeded(force: true)
                    return
                }
            }
            cancelDeferredBufferingIndicator()
            isPlaying = true
            errorMessage = nil
            lastFailureReason = nil
            isPreparing = false
            if hasPresentedPlayback, !isAwaitingAppBackgroundSurfaceRecovery {
                markPlaybackSurfaceReady()
            } else if hasPresentedPlayback {
                isBuffering = true
                playbackPhase = .buffering
            } else {
                isBuffering = true
                loadingProgress = max(loadingProgress, 0.86)
                playbackPhase = .waitingForFirstFrame
                schedulePlaybackRecoveryWatchdog(reason: .firstFrame)
            }
        case .paused:
            guard !isSurfaceMigrating else {
                isPreparing = false
                isBuffering = false
                isPlaying = wantsAutoplay
                playbackPhase = wantsAutoplay ? .playing : .paused
                return
            }
            if shouldPreservePlaybackDuringTransientSystemOverlay {
                cancelDeferredBufferingIndicator()
                isPreparing = false
                isBuffering = false
                isPlaying = true
                playbackPhase = .playing
                engine.play()
                return
            }
            cancelDeferredBufferingIndicator()
            if isUserSeeking {
                isBuffering = true
                isPlaying = false
                playbackPhase = .seeking
            } else {
                isBuffering = false
                isPlaying = false
                playbackPhase = .paused
            }
        case .ended:
            cancelDeferredBufferingIndicator()
            isPreparing = false
            isBuffering = false
            isPlaying = false
            wantsAutoplay = false
            playbackPhase = .ended
        case .failed(let message):
            cancelDeferredBufferingIndicator()
            isPreparing = false
            isBuffering = false
            isPlaying = false
            recordPlaybackFailure(
                message: message ?? PlayerEngineError.unsupportedMedia.localizedDescription,
                reason: engine.lastFailureReason
            )
            playbackPhase = .failed(errorMessage)
            PlayerMetricsLog.record(.failed, metricsID: metricsID, title: title, message: errorMessage)
            onPlaybackFailureWithReason?(errorMessage, lastFailureReason)
            onPlaybackFailure?(errorMessage)
            wantsAutoplay = false
        }
        syncRemotePlaybackControls()
        rescheduleTimeObserverIfNeeded()
        if case .ended = state, !wasPlaybackEnded {
            Task { @MainActor [weak self] in
                guard let self,
                      !self.isTerminated,
                      self.playbackPhase == .ended
                else { return }
                self.onPlaybackEnded?()
            }
        }
    }

    private func notifyBufferingPressureIfNeeded() {
        guard bufferingCount >= 2,
              bufferingCount != lastBufferingPressureNotificationCount
        else { return }
        lastBufferingPressureNotificationCount = bufferingCount
        onBufferingPressure?(bufferingCount)
    }

    private func handleEnginePlaybackIntentChange(_ wantsPlayback: Bool) {
        guard !isTerminated else { return }
        if isUserSeeking {
            return
        }
        if !wantsPlayback, shouldPreservePlaybackDuringTransientSystemOverlay {
            wantsAutoplay = true
            if engine.hasMedia {
                engine.play()
            }
            return
        }
        wantsAutoplay = wantsPlayback
        if !wantsPlayback {
            cancelDeferredBufferingIndicator()
            cancelSeekRecoveryTracking()
            isPlaying = false
            isBuffering = false
            if playbackPhase != .idle, playbackPhase != .ended {
                playbackPhase = .paused
            }
            invalidatePictureInPicturePlaybackState()
            syncRemotePlaybackControls()
        }
    }

    @discardableResult
    private func clearUserSeekOverlayAfterPlaybackStartsIfNeeded(snapshot: PlayerPlaybackSnapshot) -> Bool {
        guard isUserSeeking,
              wantsAutoplay,
              snapshot.isPlaying,
              !shouldResumePlaybackAfterUserScrub
        else { return !isUserSeeking }
        if pendingUserSeekRevealTargetTime != nil {
            guard hasSettledPendingUserSeekReveal(snapshot: snapshot) else { return false }
        } else if let pending = pendingSeekRecoveryMetric {
            guard isSeekRecoveryFrameReadyForReveal(pending: pending, snapshot: snapshot) else { return false }
        }
        if let pending = pendingSeekRecoveryMetric {
            finishSeekRecoveryMetric(
                pending,
                recovered: true,
                currentTime: snapshot.renderedVideoTime ?? snapshot.currentTime ?? pending.targetTime ?? currentTime,
                source: "seekReveal"
            )
        }
        isUserSeeking = false
        isBuffering = false
        shouldResumePlaybackAfterUserScrub = false
        clearPendingUserSeekRevealTarget()
        playbackRecoveryWatchdogTask?.cancel()
        playbackRecoveryWatchdogTask = nil
        return true
    }

    func finishUserSeekVisualReveal() {
        guard !isTerminated else { return }
        guard !isUserSeeking else { return }
        engine.setTemporaryAudioSuppressed(false)
    }

    private var shouldPreservePlaybackDuringTransientSystemOverlay: Bool {
        shouldResumeAfterTransientSystemOverlay
            && isPictureInPictureActive
            && wantsAutoplay
            && UIApplication.shared.applicationState != .active
    }

    private func markUserSeekIntent() {
        lastUserSeekAt = Date()
    }

    private func beginSeekRecoveryTracking(
        reason: String,
        targetTime: TimeInterval?,
        targetProgress: Double?,
        startedAt: CFTimeInterval,
        engineElapsedMilliseconds: Double?
    ) {
        guard wantsAutoplay || isPlaying || isUserSeeking else { return }
        seekRecoveryWatchdogTask?.cancel()
        let metric = PendingSeekRecoveryMetric(
            reason: reason,
            targetTime: targetTime,
            targetProgress: targetProgress,
            startedAt: startedAt,
            engineElapsedMilliseconds: engineElapsedMilliseconds
        )
        pendingSeekRecoveryMetric = metric
        lastRecoveredSeekMetricID = nil
        lastSeekBufferReadyMetricID = nil
        let baselineSurfaceGeneration = surfaceAttachmentGeneration
        seekRecoveryWatchdogTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.seekRecoveryWatchdogDelayNanoseconds)
            guard !Task.isCancelled,
                  !self.isTerminated,
                  let pending = self.pendingSeekRecoveryMetric,
                  pending.id == metric.id,
                  self.hasCurrentSurface(generation: baselineSurfaceGeneration)
            else { return }
            let snapshot = self.engine.snapshot(durationHint: self.durationHint)
            if let snapshotTime = snapshot.currentTime,
               snapshot.isPlaying,
               self.isSeekRecoveryMatch(currentTime: snapshotTime, pending: pending),
               self.hasStableSeekRecoveryFrameForReveal(pending: pending, snapshot: snapshot) {
                self.finishSeekRecoveryMetric(
                    pending,
                    recovered: true,
                    currentTime: snapshot.renderedVideoTime ?? snapshotTime,
                    source: "watchdog"
                )
                return
            }
            if self.retryStalledSeekIfNeeded(
                pending: pending,
                snapshot: snapshot,
                baselineSurfaceGeneration: baselineSurfaceGeneration
            ) {
                return
            }
            if self.rebuildStalledSeekIfNeeded(
                pending: pending,
                snapshot: snapshot,
                baselineSurfaceGeneration: baselineSurfaceGeneration
            ) {
                return
            }
            self.finishSeekRecoveryMetric(
                pending,
                recovered: false,
                currentTime: snapshot.currentTime ?? self.currentTime,
                source: "watchdog"
            )
        }
    }

    private func recordSeekTransition(
        reason: String,
        targetTime: TimeInterval?,
        targetProgress: Double?,
        totalElapsedMilliseconds: Double,
        engineElapsedMilliseconds: Double?
    ) {
        PlayerMetricsLog.record(
            .seek,
            metricsID: metricsID,
            title: title,
            message: seekTransitionMessage(
                reason: reason,
                targetTime: targetTime,
                targetProgress: targetProgress,
                totalElapsedMilliseconds: totalElapsedMilliseconds,
                engineElapsedMilliseconds: engineElapsedMilliseconds
            )
        )
    }

    private func recordSeekRecoveryIfNeeded(currentTime: TimeInterval, source: String) {
        guard let pending = pendingSeekRecoveryMetric else { return }
        guard isSeekRecoveryMatch(currentTime: currentTime, pending: pending) else { return }
        let snapshot = engine.snapshot(durationHint: durationHint)
        guard hasStableSeekRecoveryFrameForReveal(pending: pending, snapshot: snapshot) else { return }
        finishSeekRecoveryMetric(
            pending,
            recovered: true,
            currentTime: snapshot.renderedVideoTime ?? currentTime,
            source: source
        )
    }

    private func finishSeekRecoveryMetric(
        _ pending: PendingSeekRecoveryMetric,
        recovered: Bool,
        currentTime: TimeInterval,
        source: String
    ) {
        guard pendingSeekRecoveryMetric?.id == pending.id else { return }
        seekRecoveryWatchdogTask?.cancel()
        seekRecoveryWatchdogTask = nil
        pendingSeekRecoveryMetric = nil
        lastRecoveredSeekMetricID = recovered ? pending.id : nil
        lastSeekBufferReadyMetricID = nil
        PlayerMetricsLog.record(
            .seekRecovery,
            metricsID: metricsID,
            title: title,
            message: seekRecoveryMessage(
                reason: pending.reason,
                targetTime: pending.targetTime,
                targetProgress: pending.targetProgress,
                elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: pending.startedAt),
                engineElapsedMilliseconds: pending.engineElapsedMilliseconds,
                currentTime: currentTime,
                recovered: recovered,
                source: source
            )
        )
    }

    private func retryStalledSeekIfNeeded(
        pending: PendingSeekRecoveryMetric,
        snapshot: PlayerPlaybackSnapshot,
        baselineSurfaceGeneration: Int
    ) -> Bool {
        guard !pending.reason.contains("-recovery"),
              wantsAutoplay,
              errorMessage == nil,
              engine.hasMedia,
              hasCurrentSurface(generation: baselineSurfaceGeneration),
              canActivatePlayback(generation: baselineSurfaceGeneration)
        else { return false }

        let recoveryStart = CACurrentMediaTime()
        let resolvedTargetTime = pending.targetTime
            ?? snapshot.currentTime
            ?? (currentTime > 0 ? currentTime : nil)

        playbackPhase = .recovering
        isPreparing = false
        isBuffering = true
        loadingProgress = max(loadingProgress, 0.28)
        engine.recoverSurface()
        refreshSurfaceLayout()

        var appliedTargetTime = resolvedTargetTime
        if let resolvedTargetTime,
           let seekTime = engine.seek(toTime: resolvedTargetTime) {
            appliedTargetTime = seekTime
            _ = updatePlaybackTime(seekTime, force: true, countsAsNaturalPlayback: false)
        }

        engine.play()
        engine.setPlaybackRate(playbackRate.rawValue)
        schedulePlaybackRecoveryWatchdog(reason: .stall)

        let recoveryReason = "\(pending.reason)-recovery"
        let recoveryElapsedMilliseconds = PlayerMetricsLog.elapsedMilliseconds(since: recoveryStart)
        recordSeekTransition(
            reason: recoveryReason,
            targetTime: appliedTargetTime,
            targetProgress: pending.targetProgress,
            totalElapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: pending.startedAt),
            engineElapsedMilliseconds: recoveryElapsedMilliseconds
        )
        beginSeekRecoveryTracking(
            reason: recoveryReason,
            targetTime: appliedTargetTime,
            targetProgress: pending.targetProgress,
            startedAt: recoveryStart,
            engineElapsedMilliseconds: recoveryElapsedMilliseconds
        )
        return true
    }

    private func rebuildStalledSeekIfNeeded(
        pending: PendingSeekRecoveryMetric,
        snapshot: PlayerPlaybackSnapshot,
        baselineSurfaceGeneration: Int
    ) -> Bool {
        guard pending.reason.contains("-recovery"),
              !pending.reason.contains("-rebuild"),
              wantsAutoplay,
              errorMessage == nil,
              mediaPreparationTask == nil,
              hasCurrentSurface(generation: baselineSurfaceGeneration),
              canActivatePlayback(generation: baselineSurfaceGeneration),
              ActivePlaybackCoordinator.shared.isActive(self)
        else { return false }

        let rebuildStart = CACurrentMediaTime()
        let resolvedTargetTime = pending.targetTime
            ?? snapshot.currentTime
            ?? (currentTime > 0 ? currentTime : nil)
        let preparationSource = seekRecoveryPreparationSource(targetTime: resolvedTargetTime)

        playbackPhase = .recovering
        isPreparing = true
        isBuffering = true
        loadingProgress = max(loadingProgress, 0.18)
        pendingEngineFirstFrameTime = nil
        if let resolvedTargetTime {
            _ = updatePlaybackTime(resolvedTargetTime, force: true, countsAsNaturalPlayback: false)
        }
        PlayerMetricsLog.record(
            .playbackRecovery,
            metricsID: metricsID,
            title: title,
            message: "stage=mediaRebuild status=started reason=\(pending.reason) target=\(String(format: "%.2fs", resolvedTargetTime ?? currentTime))"
        )

        mediaPreparationGeneration &+= 1
        let preparationGeneration = mediaPreparationGeneration
        startStartupMediaWarmup(for: preparationSource)
        mediaPreparationTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                try await self.engine.prepare(source: preparationSource)
                guard !Task.isCancelled,
                      !self.isTerminated,
                      preparationGeneration == self.mediaPreparationGeneration,
                      self.hasCurrentSurface(generation: baselineSurfaceGeneration),
                      ActivePlaybackCoordinator.shared.isActive(self)
                else {
                    self.clearMediaPreparationTaskIfCurrent(preparationGeneration)
                    return
                }

                self.clearMediaPreparationTaskIfCurrent(preparationGeneration)
                var appliedTargetTime = resolvedTargetTime
                if let resolvedTargetTime,
                   let seekTime = self.engine.seek(toTime: resolvedTargetTime) {
                    appliedTargetTime = seekTime
                    self.updatePlaybackTime(seekTime, force: true, countsAsNaturalPlayback: false)
                }

                let rebuildReason = "\(pending.reason)-rebuild"
                let rebuildElapsedMilliseconds = PlayerMetricsLog.elapsedMilliseconds(since: rebuildStart)
                self.recordSeekTransition(
                    reason: rebuildReason,
                    targetTime: appliedTargetTime,
                    targetProgress: pending.targetProgress,
                    totalElapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: pending.startedAt),
                    engineElapsedMilliseconds: rebuildElapsedMilliseconds
                )
                self.beginSeekRecoveryTracking(
                    reason: rebuildReason,
                    targetTime: appliedTargetTime,
                    targetProgress: pending.targetProgress,
                    startedAt: rebuildStart,
                    engineElapsedMilliseconds: rebuildElapsedMilliseconds
                )

                if self.wantsAutoplay {
                    self.startPreparedPlayback()
                } else {
                    self.isPreparing = false
                    self.refreshPlaybackState()
                }
            } catch {
                guard !Task.isCancelled,
                      !self.isTerminated,
                      preparationGeneration == self.mediaPreparationGeneration,
                      self.hasCurrentSurface(generation: baselineSurfaceGeneration),
                      ActivePlaybackCoordinator.shared.isActive(self)
                else {
                    self.clearMediaPreparationTaskIfCurrent(preparationGeneration)
                    return
                }

                self.clearMediaPreparationTaskIfCurrent(preparationGeneration)
                self.finishSeekRecoveryMetric(
                    pending,
                    recovered: false,
                    currentTime: resolvedTargetTime ?? snapshot.currentTime ?? self.currentTime,
                    source: "rebuild"
                )
                self.recordPlaybackFailure(message: error.localizedDescription, reason: self.engine.lastFailureReason)
                self.isPreparing = false
                self.onPlaybackFailureWithReason?(self.errorMessage, self.lastFailureReason)
                self.onPlaybackFailure?(self.errorMessage)
            }
        }
        return true
    }

    private func seekTransitionMessage(
        reason: String,
        targetTime: TimeInterval?,
        targetProgress: Double?,
        totalElapsedMilliseconds: Double,
        engineElapsedMilliseconds: Double?
    ) -> String {
        var parts = [reason]
        if let targetProgress {
            parts.append("progress=\(String(format: "%.3f", targetProgress))")
        }
        if let targetTime {
            parts.append("target=\(String(format: "%.2fs", targetTime))")
        }
        parts.append("total=\(String(format: "%.0fms", totalElapsedMilliseconds))")
        if let engineElapsedMilliseconds {
            parts.append("engine=\(String(format: "%.0fms", engineElapsedMilliseconds))")
        }
        return parts.joined(separator: " ")
    }

    private func seekRecoveryMessage(
        reason: String,
        targetTime: TimeInterval?,
        targetProgress: Double?,
        elapsedMilliseconds: Double,
        engineElapsedMilliseconds: Double?,
        currentTime: TimeInterval,
        recovered: Bool,
        source: String
    ) -> String {
        var parts = [reason, "recovered=\(recovered)"]
        if let targetProgress {
            parts.append("progress=\(String(format: "%.3f", targetProgress))")
        }
        if let targetTime {
            parts.append("target=\(String(format: "%.2fs", targetTime))")
        }
        parts.append("current=\(String(format: "%.2fs", currentTime))")
        parts.append("total=\(String(format: "%.0fms", elapsedMilliseconds))")
        if let engineElapsedMilliseconds {
            parts.append("engine=\(String(format: "%.0fms", engineElapsedMilliseconds))")
        }
        parts.append("source=\(source)")
        return parts.joined(separator: " ")
    }

    private func isSeekRecoveryMatch(currentTime: TimeInterval, pending: PendingSeekRecoveryMetric) -> Bool {
        guard let targetTime = pending.targetTime else {
            return currentTime > max(self.currentTime, 0) + 0.2
        }
        let toleranceBefore = max(0.9, min(targetTime * 0.03, 2.0))
        let toleranceAfter = max(4.5, min(targetTime * 0.12, 12.0))
        return currentTime >= max(targetTime - toleranceBefore, 0)
            && currentTime <= targetTime + toleranceAfter
    }

    private func cancelSeekRecoveryTracking() {
        seekRecoveryWatchdogTask?.cancel()
        seekRecoveryWatchdogTask = nil
        pendingSeekRecoveryMetric = nil
        lastRecoveredSeekMetricID = nil
        lastSeekBufferReadyMetricID = nil
        clearPendingUserSeekRevealTarget()
    }

    private func setPendingUserSeekRevealTarget(_ targetTime: TimeInterval) {
        guard targetTime.isFinite, targetTime >= 0 else {
            clearPendingUserSeekRevealTarget()
            return
        }
        pendingUserSeekRevealTargetTime = targetTime
        pendingUserSeekRevealReadySince = nil
        pendingUserSeekRevealStartedAt = CACurrentMediaTime()
    }

    private func clearPendingUserSeekRevealTarget() {
        pendingUserSeekRevealTargetTime = nil
        pendingUserSeekRevealReadySince = nil
        pendingUserSeekRevealStartedAt = nil
    }

    private func userSeekRevealMetric(targetTime: TimeInterval) -> PendingSeekRecoveryMetric {
        PendingSeekRecoveryMetric(
            reason: "user-seek-reveal",
            targetTime: targetTime,
            targetProgress: nil,
            startedAt: CACurrentMediaTime(),
            engineElapsedMilliseconds: nil
        )
    }

    private func hasSettledPendingUserSeekReveal(snapshot: PlayerPlaybackSnapshot) -> Bool {
        guard let targetTime = pendingUserSeekRevealTargetTime else { return true }
        let now = CACurrentMediaTime()
        if let startedAt = pendingUserSeekRevealStartedAt,
           now - startedAt >= userSeekRevealMaximumWait {
            return true
        }
        let pending = userSeekRevealMetric(targetTime: targetTime)
        guard isSeekRecoveryFrameReadyForReveal(pending: pending, snapshot: snapshot) else {
            pendingUserSeekRevealReadySince = nil
            return false
        }
        guard let readySince = pendingUserSeekRevealReadySince else {
            pendingUserSeekRevealReadySince = now
            return false
        }
        return now - readySince >= userSeekRevealSettleDelay
    }

    @discardableResult
    private func advanceStartupResumeRetryGeneration() -> Int {
        startupResumeRetryGeneration &+= 1
        return startupResumeRetryGeneration
    }

    private func cancelStartupResumeRetryTask() {
        startupResumeRetryTask?.cancel()
        startupResumeRetryTask = nil
        advanceStartupResumeRetryGeneration()
    }

    private func clearStartupResumeRetryTaskIfCurrent(_ generation: Int) {
        guard startupResumeRetryGeneration == generation else { return }
        startupResumeRetryTask = nil
    }

    @discardableResult
    private func advancePictureInPictureStartRetryGeneration() -> Int {
        pictureInPictureStartRetryGeneration &+= 1
        return pictureInPictureStartRetryGeneration
    }

    private func cancelPictureInPictureStartRetryTask() {
        pictureInPictureStartRetryTask?.cancel()
        pictureInPictureStartRetryTask = nil
        advancePictureInPictureStartRetryGeneration()
    }

    private func clearPictureInPictureStartRetryTaskIfCurrent(_ generation: Int) {
        guard pictureInPictureStartRetryGeneration == generation else { return }
        pictureInPictureStartRetryTask = nil
    }

    private func hasSeekRecoveryPausedTargetFrameForReveal(
        pending: PendingSeekRecoveryMetric,
        snapshot: PlayerPlaybackSnapshot
    ) -> Bool {
        guard !snapshot.isPlaying,
              let targetTime = pending.targetTime,
              let playbackTime = snapshot.currentTime,
              playbackTime.isFinite,
              isSeekRecoveryMatch(currentTime: playbackTime, pending: pending),
              hasVisibleSeekRecoveryFrame(pending: pending, snapshot: snapshot)
        else { return false }

        let lowerBound = max(targetTime, 0)
        let resolvedDuration = snapshot.duration ?? duration ?? durationHint
        if let resolvedDuration,
           targetTime >= max(resolvedDuration - 0.35, 0) {
            return playbackTime >= max(targetTime - 0.08, 0)
        }
        return playbackTime >= lowerBound && playbackTime <= targetTime + 0.5
    }

    private func hasStableSeekRecoveryFrameForReveal(
        pending: PendingSeekRecoveryMetric,
        snapshot: PlayerPlaybackSnapshot
    ) -> Bool {
        guard hasVisibleSeekRecoveryFrame(pending: pending, snapshot: snapshot) else {
            return false
        }
        guard let targetTime = pending.targetTime else {
            return true
        }
        let revealTime = snapshot.renderedVideoTime ?? snapshot.currentTime
        guard let revealTime, revealTime.isFinite else { return false }
        let resolvedDuration = snapshot.duration ?? duration ?? durationHint
        if let resolvedDuration,
           targetTime >= max(resolvedDuration - 0.35, 0) {
            return revealTime >= max(targetTime - 0.08, 0)
        }
        return isSeekRevealTimeNearTarget(revealTime, targetTime: targetTime, snapshot: snapshot)
    }

    private func isSeekRecoveryFrameReadyForReveal(
        pending: PendingSeekRecoveryMetric,
        snapshot: PlayerPlaybackSnapshot
    ) -> Bool {
        if hasStableSeekRecoveryFrameForReveal(pending: pending, snapshot: snapshot) {
            return true
        }
        guard snapshot.isPlaying,
              let targetTime = pending.targetTime
        else { return false }
        if let renderedVideoTime = snapshot.renderedVideoTime,
           renderedVideoTime.isFinite {
            return isSeekRevealTimeNearTarget(renderedVideoTime, targetTime: targetTime, snapshot: snapshot)
        }
        guard !snapshot.requiresRenderedVideoTimeForRecovery,
              let playbackTime = snapshot.currentTime,
              playbackTime.isFinite
        else { return false }
        return isSeekRevealTimeNearTarget(playbackTime, targetTime: targetTime, snapshot: snapshot)
    }

    private func isSeekRevealTimeNearTarget(
        _ time: TimeInterval,
        targetTime: TimeInterval,
        snapshot: PlayerPlaybackSnapshot
    ) -> Bool {
        let resolvedDuration = snapshot.duration ?? duration ?? durationHint
        let isNearEnd = resolvedDuration.map { targetTime >= max($0 - 0.35, 0) } ?? false
        let toleranceBefore: TimeInterval = isNearEnd ? 0.12 : 0.5
        let toleranceAfter: TimeInterval = isNearEnd ? 0.75 : 0.5
        return time >= max(targetTime - toleranceBefore, 0)
            && time <= targetTime + toleranceAfter
    }

    private func handleEngineLoadingProgress(_ progress: Double) {
        let normalizedProgress = min(max(progress, 0), 0.98)
        guard !isTerminated else { return }
        updateSeekBufferProgressIfNeeded(engine.snapshot(durationHint: durationHint))
        guard isPreparing
            || isBuffering
            || isUserSeeking
            || playbackPhase == .seeking
            || playbackPhase == .buffering
            || playbackPhase == .recovering
            || !isPlaybackSurfaceReady
        else { return }
        guard normalizedProgress > loadingProgress + 0.01 else { return }
        loadingProgress = normalizedProgress
    }

    private func updateSeekBufferProgressIfNeeded(_ snapshot: PlayerPlaybackSnapshot) {
        guard let pending = pendingSeekRecoveryMetric,
              let targetTime = pending.targetTime,
              targetTime.isFinite,
              isUserSeeking || playbackPhase == .seeking || playbackPhase == .buffering || isBuffering
        else { return }

        let coverage = snapshot.bufferedCoverageProgress(around: targetTime)
        let seekProgress = min(max(0.22 + coverage * 0.76, 0.22), 0.98)
        if seekProgress > loadingProgress + 0.005 {
            loadingProgress = seekProgress
        }

        guard coverage >= 0.92, lastSeekBufferReadyMetricID != pending.id else { return }
        lastSeekBufferReadyMetricID = pending.id
        PlayerMetricsLog.record(
            .seek,
            metricsID: metricsID,
            title: title,
            message: "bufferReady reason=\(pending.reason) target=\(String(format: "%.2fs", targetTime)) coverage=\(String(format: "%.0f%%", coverage * 100))"
        )
    }

    private func skipSponsorBlockSegmentIfNeeded(at time: TimeInterval) {
        guard sponsorBlockEnabled,
              engine.hasMedia,
              wantsAutoplay,
              canActivatePlayback(),
              !sponsorBlockSegments.isEmpty
        else {
            activeSponsorBlockSegment = nil
            return
        }

        guard let segment = sponsorBlockSegment(at: time) else {
            activeSponsorBlockSegment = nil
            return
        }

        activeSponsorBlockSegment = segment
        guard !skippedSponsorBlockIDs.contains(segment.id) else { return }
        guard let skippedTo = engine.seek(toTime: segment.endTime) else { return }
        skippedSponsorBlockIDs.insert(segment.id)
        updatePlaybackTime(skippedTo, force: true, countsAsNaturalPlayback: false)
        PlayerMetricsLog.logger.info(
            "sponsorBlockSkipped id=\(self.metricsID, privacy: .public) category=\(segment.category, privacy: .public) from=\(time, format: .fixed(precision: 2), privacy: .public) to=\(skippedTo, format: .fixed(precision: 2), privacy: .public)"
        )

        if wantsAutoplay {
            guard canActivatePlayback() else { return }
            engine.play()
            engine.setPlaybackRate(playbackRate.rawValue)
        }
        invalidatePictureInPicturePlaybackState()
        reportSponsorBlockSkip(segment, from: time)
    }

    private func sponsorBlockSegment(at time: TimeInterval) -> SponsorBlockSegment? {
        if sponsorBlockSearchIndex >= sponsorBlockSegments.count {
            sponsorBlockSearchIndex = max(sponsorBlockSegments.count - 1, 0)
        }
        while sponsorBlockSearchIndex > 0,
              time < max(sponsorBlockSegments[sponsorBlockSearchIndex].startTime - sponsorBlockPrerollTolerance, 0) {
            sponsorBlockSearchIndex -= 1
        }

        while sponsorBlockSearchIndex < sponsorBlockSegments.count {
            let segment = sponsorBlockSegments[sponsorBlockSearchIndex]
            let startBoundary = max(segment.startTime - sponsorBlockPrerollTolerance, 0)
            let endBoundary = max(segment.endTime - sponsorBlockTailTolerance, startBoundary)
            if time < startBoundary {
                return nil
            }
            if time < endBoundary {
                return segment
            }
            sponsorBlockSearchIndex += 1
        }
        return nil
    }

    private func reportSponsorBlockSkip(_ segment: SponsorBlockSegment, from time: TimeInterval) {
        guard !sponsorBlockReportedIDs.contains(segment.id),
              let onSponsorBlockSegmentSkipped
        else { return }
        sponsorBlockReportedIDs.insert(segment.id)
        let event = SponsorBlockSkipEvent(segment: segment, fromTime: time, skippedAt: Date())
        let taskID = UUID()
        let task = Task { [weak self] in
            guard !Task.isCancelled else { return }
            await onSponsorBlockSegmentSkipped(event)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self,
                      !self.isTerminated
                else { return }
                self.sponsorBlockSkipReportTasks[taskID] = nil
            }
        }
        sponsorBlockSkipReportTasks[taskID] = task
    }

    private func configurePictureInPictureIfNeeded() {
        guard isPictureInPictureEnabled,
              !didConfigurePictureInPicture,
              !engine.supportsPictureInPicture,
              AVPictureInPictureController.isPictureInPictureSupported(),
              let contentSource = engine.pictureInPictureContentSource()
        else { return }

        let controller = AVPictureInPictureController(contentSource: contentSource)
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        pictureInPictureController = controller
        didConfigurePictureInPicture = true
    }

    private func releasePictureInPictureControllerIfDisabled() {
        guard !isPictureInPictureEnabled,
              let controller = pictureInPictureController,
              !controller.isPictureInPictureActive
        else { return }
        controller.canStartPictureInPictureAutomaticallyFromInline = false
        controller.delegate = nil
        pictureInPictureController = nil
        didConfigurePictureInPicture = false
    }

    private func applyPictureInPicturePreferenceToNativePlaybackController() {
        guard let nativePlaybackController else { return }
        let isSupportedAndEnabled = isPictureInPictureEnabled
            && AVPictureInPictureController.isPictureInPictureSupported()
        nativePlaybackController.allowsPictureInPicturePlayback = isSupportedAndEnabled
        nativePlaybackController.canStartPictureInPictureAutomaticallyFromInline = isSupportedAndEnabled
    }

    private func invalidatePictureInPicturePlaybackState() {
        pictureInPictureController?.invalidatePlaybackState()
        engine.invalidatePictureInPicturePlaybackState()
        syncPictureInPictureState()
    }

    private func syncPictureInPictureState() {
        isPictureInPictureActive = isNativePictureInPictureActive
            || pictureInPictureController?.isPictureInPictureActive == true
            || engine.isPictureInPictureActive
    }

#if DEBUG
    var hasConfiguredPictureInPictureControllerForTesting: Bool {
        pictureInPictureController != nil
    }
#endif

    private func elapsedMessage() -> String {
        "\(elapsedMilliseconds())ms"
    }

    private func elapsedMilliseconds() -> Int {
        Int(PlayerMetricsLog.elapsedMilliseconds(since: metricsStartTime).rounded())
    }

    private func syncEngineDiagnostics(force: Bool = false) {
        syncEnginePresentationSize()
        if force {
            lastPeriodicEngineDiagnosticsSyncTime = CACurrentMediaTime()
        }
        let diagnostics = engine.diagnostics
        guard force || diagnostics != engineDiagnostics else { return }
        engineDiagnostics = diagnostics
    }

    private func syncEnginePresentationSize() {
        let nextSize = engine.presentationSize
        guard nextSize != videoPresentationSize else { return }
        videoPresentationSize = nextSize
    }

    private func syncEngineDiagnosticsForPeriodicRefresh() {
        if isPreparing || isBuffering || isUserSeeking || playbackPhase == .waitingForFirstFrame || playbackPhase == .recovering || playbackPhase == .seeking {
            syncEngineDiagnostics()
            return
        }

        let now = CACurrentMediaTime()
        let minimumInterval: TimeInterval = (wantsAutoplay || isPlaying) ? 2.5 : 4.0
        guard now - lastPeriodicEngineDiagnosticsSyncTime >= minimumInterval else { return }
        lastPeriodicEngineDiagnosticsSyncTime = now
        syncEngineDiagnostics()
    }
}

private struct ForcedPlaybackTimeGuard {
    let targetTime: TimeInterval
    let expiresAt: CFTimeInterval
}

private struct PendingStartupResume {
    let time: TimeInterval
    let reason: String
}

private struct PendingStartupResumeRecoveryMetric {
    let id = UUID()
    let reason: String
    let targetTime: TimeInterval
    let appliedTime: TimeInterval
    let startedAt: CFTimeInterval
    let engineElapsedMilliseconds: Double?
}

private struct PendingSeekRecoveryMetric {
    let id = UUID()
    let reason: String
    let targetTime: TimeInterval?
    let targetProgress: Double?
    let startedAt: CFTimeInterval
    let engineElapsedMilliseconds: Double?
}

nonisolated private final class PictureInPictureRestoreCompletion: @unchecked Sendable {
    private let handler: (Bool) -> Void

    init(_ handler: @escaping (Bool) -> Void) {
        self.handler = handler
    }

    func callAsFunction(_ didRestore: Bool) {
        handler(didRestore)
    }
}

extension PlayerStateViewModel: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor [weak self] in
            guard let self,
                  !self.isTerminated,
                  self.pictureInPictureController === pictureInPictureController,
                  self.isPictureInPictureEnabled
            else {
                pictureInPictureController.stopPictureInPicture()
                return
            }
            self.isPictureInPictureActive = true
        }
    }

    nonisolated func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor [weak self] in
            guard let self,
                  !self.isTerminated,
                  self.pictureInPictureController === pictureInPictureController
            else { return }
            self.handlePictureInPictureWillStop()
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor [weak self] in
            guard let self,
                  !self.isTerminated,
                  self.pictureInPictureController === pictureInPictureController
            else { return }
            self.handlePictureInPictureDidStop(isNativeController: false)
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        let completion = PictureInPictureRestoreCompletion(completionHandler)
        Task { @MainActor [weak self] in
            guard let self,
                  !self.isTerminated,
                  self.pictureInPictureController === pictureInPictureController
            else {
                completion(false)
                return
            }
            let didRestore = await self.restoreUserInterfaceAfterPictureInPictureStopIfNeeded()
            completion(didRestore)
        }
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self,
                  !self.isTerminated,
                  self.pictureInPictureController === pictureInPictureController
            else { return }
            self.isPictureInPictureActive = false
            self.releasePictureInPictureControllerIfDisabled()
            self.errorMessage = "画中画启动失败：\(error.localizedDescription)"
        }
    }
}

extension PlayerStateViewModel: AVPlayerViewControllerDelegate {
    nonisolated func playerViewControllerWillStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
        Task { @MainActor [weak self] in
            guard let self,
                  !self.isTerminated,
                  self.nativePlaybackController === playerViewController
            else { return }
            self.isNativePictureInPictureActive = true
            self.syncPictureInPictureState()
        }
    }

    nonisolated func playerViewControllerDidStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
        Task { @MainActor [weak self] in
            guard let self,
                  !self.isTerminated,
                  self.nativePlaybackController === playerViewController
            else { return }
            self.isNativePictureInPictureActive = true
            self.syncPictureInPictureState()
        }
    }

    nonisolated func playerViewControllerWillStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
        Task { @MainActor [weak self] in
            guard let self,
                  !self.isTerminated,
                  self.nativePlaybackController === playerViewController
            else { return }
            self.handlePictureInPictureWillStop()
        }
    }

    nonisolated func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
        Task { @MainActor [weak self] in
            guard let self,
                  !self.isTerminated,
                  self.nativePlaybackController === playerViewController
            else { return }
            self.handlePictureInPictureDidStop(isNativeController: true)
        }
    }

    nonisolated func playerViewController(
        _ playerViewController: AVPlayerViewController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        let completion = PictureInPictureRestoreCompletion(completionHandler)
        Task { @MainActor [weak self] in
            guard let self,
                  !self.isTerminated,
                  self.nativePlaybackController === playerViewController
            else {
                completion(false)
                return
            }
            let didRestore = await self.restoreUserInterfaceAfterPictureInPictureStopIfNeeded()
            completion(didRestore)
        }
    }

    nonisolated func playerViewController(
        _ playerViewController: AVPlayerViewController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        Task { @MainActor [weak self] in
            guard let self,
                  !self.isTerminated,
                  self.nativePlaybackController === playerViewController
            else { return }
            self.isNativePictureInPictureActive = false
            self.syncPictureInPictureState()
            self.errorMessage = "画中画启动失败：\(error.localizedDescription)"
        }
    }
}

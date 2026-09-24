import AVFoundation
import AVKit
import Foundation
import UIKit

enum VideoPlayerState: Equatable, Sendable {
    case idle
    case preparing
    case ready
    case buffering
    case playing
    case paused
    case ended
    case failed(String?)
}

struct VideoPlayerProgress: Equatable, Sendable {
    let currentTime: TimeInterval
    let duration: TimeInterval?
    let isPlaying: Bool
    let bufferedRanges: [PlayerBufferedRange]
}

@MainActor
protocol VideoPlayerProtocol: AnyObject {
    var state: VideoPlayerState { get }
    var diagnostics: PlayerEngineDiagnostics { get }
    var onStateChange: (@MainActor (VideoPlayerState) -> Void)? { get set }
    var onProgressUpdate: (@MainActor (VideoPlayerProgress) -> Void)? { get set }
    var onFirstFrame: (@MainActor (TimeInterval) -> Void)? { get set }

    func attachSurface(_ surface: UIView)
    func detachSurface(_ surface: UIView)
    func prepare(with videoURL: URL, audioURL: URL?) async throws
    func prepare(source: PlayerStreamSource) async throws
    func play()
    func pause()
    func seek(to time: TimeInterval)
    func stop()
}

@MainActor
class RenderingEngineVideoPlayerAdapter: VideoPlayerProtocol {
    private let engine: PlayerRenderingEngine
    private var progressTask: Task<Void, Never>?
    private var preparedSource: PlayerStreamSource?
    private(set) var state: VideoPlayerState = .idle

    var onStateChange: (@MainActor (VideoPlayerState) -> Void)?
    var onProgressUpdate: (@MainActor (VideoPlayerProgress) -> Void)?
    var onFirstFrame: (@MainActor (TimeInterval) -> Void)?

    var diagnostics: PlayerEngineDiagnostics {
        engine.diagnostics
    }

    init(engine: PlayerRenderingEngine) {
        self.engine = engine
        bindEngine()
    }

    deinit {
        progressTask?.cancel()
        Task { @MainActor [engine] in
            engine.onPlaybackStateChange = nil
            engine.onPlaybackIntentChange = nil
            engine.onLoadingProgressChange = nil
            engine.onFirstFrame = nil
            engine.stop()
        }
    }

    func attachSurface(_ surface: UIView) {
        engine.attachSurface(surface)
    }

    func detachSurface(_ surface: UIView) {
        engine.detachSurface(surface)
    }

    func prepare(with videoURL: URL, audioURL: URL?) async throws {
        let source = PlayerStreamSource(
            metricsID: UUID().uuidString,
            videoURL: videoURL,
            audioURL: audioURL,
            videoStream: nil,
            audioStream: nil,
            alternateVideoRenditions: [],
            referer: "https://www.bilibili.com",
            httpHeaders: BiliHLSManifestBuilder.httpHeaders(referer: "https://www.bilibili.com"),
            title: videoURL.lastPathComponent,
            durationHint: nil,
            isLiveStream: false,
            isLiveHLS: false,
            liveHLSFormat: nil,
            resumeTime: 0,
            dynamicRange: .sdr,
            cdnPreference: .automatic
        )
        try await prepare(source: source)
    }

    func prepare(source: PlayerStreamSource) async throws {
        preparedSource = source
        publishState(.preparing)
        try await engine.prepare(source: source)
        publishState(.ready)
    }

    func play() {
        engine.play()
        startProgressReporting()
    }

    func pause() {
        engine.pause()
        publishProgress()
    }

    func seek(to time: TimeInterval) {
        _ = engine.seek(toTime: time)
        publishProgress()
    }

    func stop() {
        progressTask?.cancel()
        progressTask = nil
        preparedSource = nil
        engine.stop()
        publishState(.idle)
    }

    private func bindEngine() {
        engine.onPlaybackStateChange = { [weak self] state in
            guard let self else { return }
            self.publishState(Self.mapEngineState(state))
        }
        engine.onFirstFrame = { [weak self] time in
            guard let self else { return }
            self.onFirstFrame?(time)
        }
    }

    private func publishState(_ nextState: VideoPlayerState) {
        guard state != nextState else { return }
        state = nextState
        onStateChange?(nextState)
        switch nextState {
        case .playing:
            startProgressReporting()
        case .idle, .ended, .failed:
            progressTask?.cancel()
            progressTask = nil
        case .preparing, .ready, .buffering, .paused:
            break
        }
    }

    private func startProgressReporting() {
        guard progressTask == nil else { return }
        progressTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.publishProgress()
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    private func publishProgress() {
        let snapshot = engine.snapshot(durationHint: preparedSource?.durationHint)
        let progress = VideoPlayerProgress(
            currentTime: snapshot.currentTime ?? 0,
            duration: snapshot.duration,
            isPlaying: snapshot.isPlaying,
            bufferedRanges: snapshot.bufferedRanges
        )
        onProgressUpdate?(progress)
    }

    private static func mapEngineState(_ state: PlayerEnginePlaybackState) -> VideoPlayerState {
        switch state {
        case .idle:
            return .idle
        case .preparing:
            return .preparing
        case .ready:
            return .ready
        case .buffering:
            return .buffering
        case .playing:
            return .playing
        case .paused:
            return .paused
        case .ended:
            return .ended
        case .failed(let message):
            return .failed(message)
        }
    }
}

@MainActor
final class AVPlayerAdapter: RenderingEngineVideoPlayerAdapter {
    init() {
        super.init(engine: AVPlayerHLSBridgeEngine())
    }
}

@MainActor
final class CoreVideoPlayerManager {
    static let shared = CoreVideoPlayerManager()

    private var activePlayer: VideoPlayerProtocol?

    func makePlayer() -> VideoPlayerProtocol {
        AVPlayerAdapter()
    }

    func makeRenderingEngine() -> PlayerRenderingEngine {
        AVPlayerHLSBridgeEngine()
    }

    func installPlayer(
        on surface: UIView? = nil
    ) -> VideoPlayerProtocol {
        let player = makePlayer()
        if let surface {
            activePlayer?.detachSurface(surface)
            player.attachSurface(surface)
        }
        activePlayer?.stop()
        activePlayer = player
        return player
    }

    nonisolated static func selectBestStream(
        from streams: [DashStream],
        preference: VideoCodecPreference,
        supportsAV1HardwareDecode: Bool = PlaybackCodecPolicy.canDecodeAV1
    ) -> DashStream? {
        DashStreamDispatcher.selectBestStream(
            from: streams,
            preference: preference,
            supportsAV1HardwareDecode: supportsAV1HardwareDecode
        )
    }
}

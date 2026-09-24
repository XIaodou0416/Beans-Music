#if DEBUG
import Combine
import Foundation
import OSLog
import QuartzCore

enum VideoDetailPlaybackDiagnosticSurfaceEvent {
    case attached(
        surfaceID: ObjectIdentifier,
        playerID: ObjectIdentifier?,
        playerItemID: ObjectIdentifier?
    )
    case detached(
        surfaceID: ObjectIdentifier,
        playerID: ObjectIdentifier?,
        playerItemID: ObjectIdentifier?
    )
}

struct VideoDetailRotationDiagnosticRecord: Codable, Equatable, Sendable {
    let target: String
    var durationMilliseconds: Double?
    var blackFrameDurationMilliseconds: Double?
    var firstPlaybackLatencyMilliseconds: Double?
    var firstFrameLatencyMilliseconds: Double?
    var playerViewModelIdentity: String?
    var avPlayerIdentity: String?
    var avPlayerItemIdentity: String?
    var surfaceIdentity: String?
    var surfaceAttachCount = 0
    var surfaceDetachCount = 0
    var playbackState = "unknown"
    var isBuffering = false
    var recoveryReason: String?
}

@MainActor
final class VideoDetailPlaybackDiagnostics {
    private var cancellables = Set<AnyCancellable>()
    private weak var observedPlayer: PlayerStateViewModel?
    private var blackFrameProbeTask: Task<Void, Never>?
    private var blackFrameProbeStartedAt: CFTimeInterval?
    private var pageStartedAt: CFTimeInterval?
    private var firstPlaybackAt: CFTimeInterval?
    private var firstFrameAt: CFTimeInterval?
    private var rotationStartedAt: CFTimeInterval?
    private var rotationSignpostState: OSSignpostIntervalState?
    private var lastSignpostedPlaybackState: String?
    private var lastPlayerID: ObjectIdentifier?
    private var lastPlayerItemID: ObjectIdentifier?
    private var lastSurfaceID: ObjectIdentifier?
    private var hasLoggedPageSummary = false
    private var activeRotationRecord: VideoDetailRotationDiagnosticRecord?
    private(set) var completedRotationRecords: [VideoDetailRotationDiagnosticRecord] = []

    func begin(metricsID: String, title: String?) {
        guard pageStartedAt == nil else { return }
        pageStartedAt = CACurrentMediaTime()
        let titleSummary = title.map(PlayerMetricsLog.shortTitle) ?? "-"
        record(
            "videoDetail.begin metricsID=\(metricsID) title=\(titleSummary)"
        )
    }

    func observe(player: PlayerStateViewModel?) {
        guard observedPlayer !== player else {
            sampleIdentities(from: player)
            return
        }
        observedPlayer?.onVideoDetailPlaybackDiagnosticSurfaceEvent = nil
        cancellables.removeAll()
        observedPlayer = player
        lastSignpostedPlaybackState = nil
        guard let player else {
            record("videoDetail.player detached")
            return
        }

        player.onVideoDetailPlaybackDiagnosticSurfaceEvent = { [weak self] event in
            self?.receiveSurfaceEvent(event)
        }
        sampleIdentities(from: player)
        record(
            "videoDetail.playerObserved viewModel=\(identifier(ObjectIdentifier(player)))"
        )

        player.$isPlaying
            .removeDuplicates()
            .sink { [weak self, weak player] isPlaying in
                guard let self, let player else { return }
                self.sampleIdentities(from: player)
                self.updateRecordPlaybackState(for: player)
                if isPlaying {
                    self.markFirstPlaybackIfNeeded()
                }
                self.record(
                    "videoDetail.playbackState isPlaying=\(isPlaying) viewModel=\(self.identifier(player.debugPlayerIdentity))"
                )
            }
            .store(in: &cancellables)

        player.$playbackPhase
            .removeDuplicates()
            .sink { [weak self, weak player] phase in
                guard let self, let player else { return }
                self.sampleIdentities(from: player)
                self.updateRecordPlaybackState(for: player)
                self.record(
                    "videoDetail.playbackPhase=\(String(describing: phase)) viewModel=\(self.identifier(player.debugPlayerIdentity))"
                )
            }
            .store(in: &cancellables)

        player.$isBuffering
            .removeDuplicates()
            .sink { [weak self, weak player] isBuffering in
                guard let self, let player else { return }
                self.sampleIdentities(from: player)
                self.updateRecordPlaybackState(for: player)
                self.record(
                    "videoDetail.buffering=\(isBuffering) viewModel=\(self.identifier(player.debugPlayerIdentity))"
                )
            }
            .store(in: &cancellables)

        player.$hasPresentedPlayback
            .removeDuplicates()
            .sink { [weak self, weak player] hasPresentedPlayback in
                guard let self, let player else { return }
                self.sampleIdentities(from: player)
                self.updateRecordPlaybackState(for: player)
                if hasPresentedPlayback {
                    self.markFirstFrameIfNeeded()
                }
                self.record(
                    "videoDetail.firstFramePresented=\(hasPresentedPlayback) viewModel=\(self.identifier(player.debugPlayerIdentity))"
                )
            }
            .store(in: &cancellables)

        player.$isCurrentPlaybackSurfaceReadyForDisplay
            .removeDuplicates()
            .sink { [weak self, weak player] isReady in
                guard let self, let player else { return }
                self.sampleIdentities(from: player)
                self.updateRecordPlaybackState(for: player)
                self.record(
                    "videoDetail.surfaceReady=\(isReady) viewModel=\(self.identifier(player.debugPlayerIdentity))"
                )
                if isReady {
                    self.finishBlackFrameProbeIfPossible(for: player)
                }
            }
            .store(in: &cancellables)

        if player.isPlaying {
            markFirstPlaybackIfNeeded()
        }
        if player.hasPresentedPlayback {
            markFirstFrameIfNeeded()
        }
    }

    func markRotationStarted(toLandscape: Bool) {
        let startedAt = CACurrentMediaTime()
        if let rotationStartedAt {
            finishRotationRecord(
                duration: startedAt - rotationStartedAt,
                recoveryReason: "superseded",
                fallbackTarget: "recovered"
            )
        }
        rotationStartedAt = startedAt
        blackFrameProbeTask?.cancel()
        blackFrameProbeTask = nil
        blackFrameProbeStartedAt = nil
        activeRotationRecord = VideoDetailRotationDiagnosticRecord(
            target: toLandscape ? "landscape" : "portrait",
            durationMilliseconds: nil,
            blackFrameDurationMilliseconds: nil,
            firstPlaybackLatencyMilliseconds: elapsedMilliseconds(
                from: pageStartedAt,
                to: firstPlaybackAt
            ),
            firstFrameLatencyMilliseconds: elapsedMilliseconds(
                from: pageStartedAt,
                to: firstFrameAt
            ),
            playerViewModelIdentity: optionalIdentifier(observedPlayer.map(ObjectIdentifier.init)),
            avPlayerIdentity: optionalIdentifier(lastPlayerID),
            avPlayerItemIdentity: optionalIdentifier(lastPlayerItemID),
            surfaceIdentity: optionalIdentifier(lastSurfaceID),
            playbackState: observedPlayer.map { $0.isPlaying ? "playing" : "paused" } ?? "unknown",
            isBuffering: observedPlayer?.isBuffering ?? false
        )
        rotationSignpostState = PlayerMetricsLog.beginSignpostedInterval(
            "VideoDetailRotation",
            message: toLandscape ? "target=landscape" : "target=portrait"
        )
        lastSignpostedPlaybackState = nil
        PlayerMetricsLog.signpostEvent(
            "VideoDetailRotationStart",
            message: toLandscape ? "target=landscape" : "target=portrait"
        )
        record(
            "videoDetail.rotationStart target=\(toLandscape ? "landscape" : "portrait") \(identitySummary)"
        )

        guard let player = observedPlayer else {
            record("videoDetail.blackFrameDuration=unavailable reason=noPlayer")
            return
        }
        guard let hasUsableVideoFrame = player.debugHasUsableVideoFrame else {
            record("videoDetail.blackFrameDuration=unavailable reason=noFrameSnapshot \(identitySummary)")
            return
        }
        guard !hasUsableVideoFrame else {
            record("videoDetail.blackFrameDuration=notObserved \(identitySummary)")
            return
        }
        let blackFrameStartedAt = CACurrentMediaTime()
        blackFrameProbeStartedAt = blackFrameStartedAt
        PlayerMetricsLog.signpostEvent("VideoDetailBlackFrameStart")
        blackFrameProbeTask = Task { @MainActor [weak self, weak player] in
            for _ in 0..<180 {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(nanoseconds: 16_000_000)
                guard let self, let player, !Task.isCancelled else { return }
                if player.debugHasUsableVideoFrame == true {
                    self.finishBlackFrameRecord(duration: CACurrentMediaTime() - blackFrameStartedAt)
                    self.blackFrameProbeTask = nil
                    self.blackFrameProbeStartedAt = nil
                    return
                }
            }
            guard let self, !Task.isCancelled else { return }
            self.finishBlackFrameRecord(duration: nil)
            self.blackFrameProbeTask = nil
            self.blackFrameProbeStartedAt = nil
        }
    }

    func markRotationFinished(toLandscape: Bool) {
        guard let startedAt = rotationStartedAt else {
            record(
                "videoDetail.rotationFinished target=\(toLandscape ? "landscape" : "portrait") duration=unavailable"
            )
            return
        }
        finishRotationRecord(
            duration: CACurrentMediaTime() - startedAt,
            recoveryReason: nil,
            fallbackTarget: toLandscape ? "landscape" : "portrait"
        )
        rotationStartedAt = nil
    }

    func markRotationRecovered(reason: String) {
        guard rotationStartedAt != nil else {
            record("videoDetail.rotationRecovered reason=\(reason) duration=unavailable")
            return
        }
        finishRotationRecord(
            duration: CACurrentMediaTime() - (rotationStartedAt ?? CACurrentMediaTime()),
            recoveryReason: reason,
            fallbackTarget: "recovered"
        )
        rotationStartedAt = nil
    }

    func markPageDisappeared() {
        guard !hasLoggedPageSummary else { return }
        hasLoggedPageSummary = true
        blackFrameProbeTask?.cancel()
        blackFrameProbeTask = nil
        blackFrameProbeStartedAt = nil
        observedPlayer?.onVideoDetailPlaybackDiagnosticSurfaceEvent = nil
        if let rotationStartedAt {
            finishRotationRecord(
                duration: CACurrentMediaTime() - rotationStartedAt,
                recoveryReason: "pageDisappeared",
                fallbackTarget: "recovered"
            )
            self.rotationStartedAt = nil
        }
        record(
            "videoDetail.end firstPlayback=\(elapsed(from: pageStartedAt, to: firstPlaybackAt)) firstFrame=\(elapsed(from: pageStartedAt, to: firstFrameAt)) \(identitySummary)"
        )
        cancellables.removeAll()
    }

    func recordSurfaceEventForTesting(_ event: VideoDetailPlaybackDiagnosticSurfaceEvent) {
        receiveSurfaceEvent(event)
    }

    private func receiveSurfaceEvent(_ event: VideoDetailPlaybackDiagnosticSurfaceEvent) {
        switch event {
        case let .attached(surfaceID, playerID, playerItemID):
            lastSurfaceID = surfaceID
            activeRotationRecord?.surfaceAttachCount += 1
            PlayerMetricsLog.signpostEvent("VideoDetailSurfaceAttach")
            updateRecordIdentities(
                playerID: playerID,
                playerItemID: playerItemID,
                surfaceID: surfaceID
            )
            record("videoDetail.surfaceAttach surface=\(identifier(surfaceID)) player=\(identifier(playerID)) item=\(identifier(playerItemID))")
        case let .detached(surfaceID, playerID, playerItemID):
            lastSurfaceID = surfaceID
            activeRotationRecord?.surfaceDetachCount += 1
            PlayerMetricsLog.signpostEvent("VideoDetailSurfaceDetach")
            updateRecordIdentities(
                playerID: playerID,
                playerItemID: playerItemID,
                surfaceID: surfaceID
            )
            record("videoDetail.surfaceDetach surface=\(identifier(surfaceID)) player=\(identifier(playerID)) item=\(identifier(playerItemID))")
        }
    }

    private func sampleIdentities(from player: PlayerStateViewModel?) {
        guard let player else { return }
        let playerID = player.debugAVPlayerIdentity
        let playerItemID = player.debugAVPlayerItemIdentity
        guard playerID != lastPlayerID || playerItemID != lastPlayerItemID else { return }
        lastPlayerID = playerID
        lastPlayerItemID = playerItemID
        updateRecordIdentities(playerID: playerID, playerItemID: playerItemID, surfaceID: nil)
        record(
            "videoDetail.identity viewModel=\(identifier(player.debugPlayerIdentity)) player=\(identifier(playerID)) item=\(identifier(playerItemID))"
        )
    }

    private func markFirstPlaybackIfNeeded() {
        guard firstPlaybackAt == nil else { return }
        firstPlaybackAt = CACurrentMediaTime()
        PlayerMetricsLog.signpostEvent("VideoDetailFirstPlayback")
        activeRotationRecord?.firstPlaybackLatencyMilliseconds = elapsedMilliseconds(
            from: pageStartedAt,
            to: firstPlaybackAt
        )
        record(
            "videoDetail.firstPlaybackLatency=\(elapsed(from: pageStartedAt, to: firstPlaybackAt)) \(identitySummary)"
        )
    }

    private func markFirstFrameIfNeeded() {
        guard firstFrameAt == nil else { return }
        firstFrameAt = CACurrentMediaTime()
        PlayerMetricsLog.signpostEvent("VideoDetailFirstFrame")
        activeRotationRecord?.firstFrameLatencyMilliseconds = elapsedMilliseconds(
            from: pageStartedAt,
            to: firstFrameAt
        )
        record(
            "videoDetail.firstFrameLatency=\(elapsed(from: pageStartedAt, to: firstFrameAt)) \(identitySummary)"
        )
    }

    private func finishBlackFrameProbeIfPossible(for player: PlayerStateViewModel) {
        guard player.debugHasUsableVideoFrame == true else { return }
        if let blackFrameProbeStartedAt {
            finishBlackFrameRecord(duration: CACurrentMediaTime() - blackFrameProbeStartedAt)
            self.blackFrameProbeStartedAt = nil
        }
        blackFrameProbeTask?.cancel()
        blackFrameProbeTask = nil
    }

    private func finishBlackFrameRecord(duration: CFTimeInterval?) {
        activeRotationRecord?.blackFrameDurationMilliseconds = duration.map {
            max($0, 0) * 1000
        }
        PlayerMetricsLog.signpostEvent("VideoDetailBlackFrameEnd")
        if let duration {
            record("videoDetail.blackFrameDuration=\(milliseconds(duration)) \(identitySummary)")
        } else {
            record("videoDetail.blackFrameDuration=unresolved \(identitySummary)")
        }
    }

    private func updateRecordIdentities(
        playerID: ObjectIdentifier?,
        playerItemID: ObjectIdentifier?,
        surfaceID: ObjectIdentifier?
    ) {
        guard activeRotationRecord != nil else { return }
        activeRotationRecord?.playerViewModelIdentity = optionalIdentifier(
            observedPlayer.map(ObjectIdentifier.init)
        )
        if let playerID {
            activeRotationRecord?.avPlayerIdentity = optionalIdentifier(playerID)
        } else if activeRotationRecord?.avPlayerIdentity == nil {
            activeRotationRecord?.avPlayerIdentity = optionalIdentifier(lastPlayerID)
        }
        if let playerItemID {
            activeRotationRecord?.avPlayerItemIdentity = optionalIdentifier(playerItemID)
        } else if activeRotationRecord?.avPlayerItemIdentity == nil {
            activeRotationRecord?.avPlayerItemIdentity = optionalIdentifier(lastPlayerItemID)
        }
        if let surfaceID {
            activeRotationRecord?.surfaceIdentity = optionalIdentifier(surfaceID)
        } else if activeRotationRecord?.surfaceIdentity == nil {
            activeRotationRecord?.surfaceIdentity = optionalIdentifier(lastSurfaceID)
        }
        if let player = observedPlayer {
            activeRotationRecord?.playbackState = player.isPlaying ? "playing" : "paused"
            activeRotationRecord?.isBuffering = player.isBuffering
        }
    }

    private func updateRecordPlaybackState(for player: PlayerStateViewModel) {
        let playbackState = player.isPlaying ? "playing" : "paused"
        activeRotationRecord?.playbackState = playbackState
        activeRotationRecord?.isBuffering = player.isBuffering
        let signpostState = "\(playbackState)|buffering=\(player.isBuffering)"
        guard lastSignpostedPlaybackState != signpostState else { return }
        lastSignpostedPlaybackState = signpostState
        PlayerMetricsLog.signpostEvent("VideoDetailPlaybackState")
    }

    private func finishRotationRecord(
        duration: CFTimeInterval,
        recoveryReason: String?,
        fallbackTarget: String
    ) {
        var record = activeRotationRecord ?? VideoDetailRotationDiagnosticRecord(
            target: fallbackTarget,
            durationMilliseconds: nil,
            blackFrameDurationMilliseconds: nil,
            firstPlaybackLatencyMilliseconds: elapsedMilliseconds(
                from: pageStartedAt,
                to: firstPlaybackAt
            ),
            firstFrameLatencyMilliseconds: elapsedMilliseconds(
                from: pageStartedAt,
                to: firstFrameAt
            ),
            playerViewModelIdentity: optionalIdentifier(observedPlayer.map(ObjectIdentifier.init)),
            avPlayerIdentity: optionalIdentifier(lastPlayerID),
            avPlayerItemIdentity: optionalIdentifier(lastPlayerItemID),
            surfaceIdentity: optionalIdentifier(lastSurfaceID),
            playbackState: observedPlayer.map { $0.isPlaying ? "playing" : "paused" } ?? "unknown",
            isBuffering: observedPlayer?.isBuffering ?? false
        )
        updateRecordIdentities(playerID: lastPlayerID, playerItemID: lastPlayerItemID, surfaceID: nil)
        if let activeRotationRecord {
            record = activeRotationRecord
        }
        record.durationMilliseconds = max(duration, 0) * 1000
        record.recoveryReason = recoveryReason
        if let player = observedPlayer {
            record.playbackState = player.isPlaying ? "playing" : "paused"
            record.isBuffering = player.isBuffering
        }
        completedRotationRecords.append(record)
        emit(record)
        if let rotationSignpostState {
            PlayerMetricsLog.endSignpostedInterval(
                "VideoDetailRotation",
                rotationSignpostState,
                message: record.recoveryReason ?? "completed"
            )
            self.rotationSignpostState = nil
        }
        PlayerMetricsLog.signpostEvent("VideoDetailRotationEnd")
        activeRotationRecord = nil
    }

    private func emit(_ record: VideoDetailRotationDiagnosticRecord) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(record),
              let payload = String(data: data, encoding: .utf8)
        else { return }
        self.record("videoDetail.rotationRecord \(payload)")
    }

    private var identitySummary: String {
        "player=\(identifier(lastPlayerID)) item=\(identifier(lastPlayerItemID))"
    }

    private func record(_ message: String) {
        PlayerMetricsLog.diagnostic(message)
    }

    private func identifier(_ identifier: ObjectIdentifier?) -> String {
        identifier.map { String(describing: $0) } ?? "nil"
    }

    private func optionalIdentifier(_ identifier: ObjectIdentifier?) -> String? {
        identifier.map { String(describing: $0) }
    }

    private func milliseconds(_ duration: CFTimeInterval) -> String {
        String(format: "%.1fms", max(duration, 0) * 1000)
    }

    private func elapsed(from start: CFTimeInterval?, to end: CFTimeInterval?) -> String {
        guard let milliseconds = elapsedMilliseconds(from: start, to: end) else {
            return "unavailable"
        }
        return String(format: "%.1fms", milliseconds)
    }

    private func elapsedMilliseconds(
        from start: CFTimeInterval?,
        to end: CFTimeInterval?
    ) -> Double? {
        guard let start, let end else { return nil }
        return max(end - start, 0) * 1000
    }
}
#else
struct VideoDetailRotationDiagnosticRecord: Codable, Equatable, Sendable {
    let target: String
    var durationMilliseconds: Double?
    var blackFrameDurationMilliseconds: Double?
    var firstPlaybackLatencyMilliseconds: Double?
    var firstFrameLatencyMilliseconds: Double?
    var playerViewModelIdentity: String?
    var avPlayerIdentity: String?
    var avPlayerItemIdentity: String?
    var surfaceIdentity: String?
    var surfaceAttachCount = 0
    var surfaceDetachCount = 0
    var playbackState = "unknown"
    var isBuffering = false
    var recoveryReason: String?
}

@MainActor
final class VideoDetailPlaybackDiagnostics {
    func begin(metricsID _: String, title _: String?) {}
    func observe(player _: PlayerStateViewModel?) {}
    func markRotationStarted(toLandscape _: Bool) {}
    func markRotationFinished(toLandscape _: Bool) {}
    func markRotationRecovered(reason _: String) {}
    func markPageDisappeared() {}
}
#endif

import Combine
import Foundation

enum PlaybackSessionPhase: Equatable {
    case idle
    case preparing
    case buffering
    case playing
    case paused
    case failed
}

struct PlaybackSessionSnapshot: Equatable {
    var playerID: ObjectIdentifier?
    var phase: PlaybackSessionPhase
    var isSeekable: Bool
    var hasPresentedPlayback: Bool
    var isPictureInPictureActive: Bool

    static let idle = PlaybackSessionSnapshot(
        playerID: nil,
        phase: .idle,
        isSeekable: false,
        hasPresentedPlayback: false,
        isPictureInPictureActive: false
    )
}

/// Mux 式分层的第一层：持有稳定播放器身份，并向上层发布小而可比较的状态快照。
/// 底层仍复用现有 PlayerStateViewModel / AVPlayer / HLS Bridge。
@MainActor
final class PlaybackSession: ObservableObject {
    @Published private(set) var activePlayer: PlayerStateViewModel?
    @Published private(set) var snapshot = PlaybackSessionSnapshot.idle

    private var stateCancellable: AnyCancellable?

    func replaceActivePlayer(with player: PlayerStateViewModel?) {
        if let activePlayer, let player, activePlayer === player {
            return
        }
        guard activePlayer != nil || player != nil else { return }

        stateCancellable = nil
        activePlayer = player
        guard let player else {
            publish(.idle)
            return
        }

        publish(Self.makeSnapshot(
            player: player,
            isPreparing: player.isPreparing,
            isPlaying: player.isPlaying,
            isBuffering: player.isBuffering,
            errorMessage: player.errorMessage,
            isSeekable: player.isSeekable,
            hasPresentedPlayback: player.hasPresentedPlayback,
            isPictureInPictureActive: player.isPictureInPictureActive
        ))

        stateCancellable = Publishers.CombineLatest4(
            player.$isPreparing,
            player.$isPlaying,
            player.$isBuffering,
            player.$errorMessage
        )
        .combineLatest(
            Publishers.CombineLatest3(
                player.$isSeekable,
                player.$hasPresentedPlayback,
                player.$isPictureInPictureActive
            )
        )
        .map { combined in
            let playback = combined.0
            let presentation = combined.1
            return Self.makeSnapshot(
                player: player,
                isPreparing: playback.0,
                isPlaying: playback.1,
                isBuffering: playback.2,
                errorMessage: playback.3,
                isSeekable: presentation.0,
                hasPresentedPlayback: presentation.1,
                isPictureInPictureActive: presentation.2
            )
        }
        .removeDuplicates()
        .sink { [weak self] snapshot in
            self?.publish(snapshot)
        }
    }

    func detach() {
        replaceActivePlayer(with: nil)
    }

    func play() {
        activePlayer?.play()
    }

    func pause() {
        activePlayer?.pause()
    }

    @discardableResult
    func togglePlayback() -> Bool {
        activePlayer?.togglePlayback() ?? false
    }

    func seek(to progress: Double) {
        activePlayer?.seek(to: progress)
    }

    func stop(reason: PlayerStopReason = .navigation) {
        activePlayer?.stop(reason: reason)
    }

    private func publish(_ next: PlaybackSessionSnapshot) {
        guard snapshot != next else { return }
        snapshot = next
    }

    private static func makeSnapshot(
        player: PlayerStateViewModel,
        isPreparing: Bool,
        isPlaying: Bool,
        isBuffering: Bool,
        errorMessage: String?,
        isSeekable: Bool,
        hasPresentedPlayback: Bool,
        isPictureInPictureActive: Bool
    ) -> PlaybackSessionSnapshot {
        PlaybackSessionSnapshot(
            playerID: ObjectIdentifier(player),
            phase: phase(
                isPreparing: isPreparing,
                isPlaying: isPlaying,
                isBuffering: isBuffering,
                hasError: errorMessage?.isEmpty == false
            ),
            isSeekable: isSeekable,
            hasPresentedPlayback: hasPresentedPlayback,
            isPictureInPictureActive: isPictureInPictureActive
        )
    }

    private static func phase(
        isPreparing: Bool,
        isPlaying: Bool,
        isBuffering: Bool,
        hasError: Bool
    ) -> PlaybackSessionPhase {
        if hasError { return .failed }
        if isPreparing { return .preparing }
        if isBuffering { return .buffering }
        return isPlaying ? .playing : .paused
    }
}

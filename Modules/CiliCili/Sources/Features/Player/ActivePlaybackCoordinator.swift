import Foundation

@MainActor
final class ActivePlaybackCoordinator {
    static let shared = ActivePlaybackCoordinator()

    private weak var activePlayer: PlayerStateViewModel?
    private var registeredPlayers: [ObjectIdentifier: WeakPlayerReference] = [:]
    private var activeGeneration = UUID()

    private init() {}

    func register(_ player: PlayerStateViewModel) {
        cleanupRegisteredPlayers()
        registeredPlayers[ObjectIdentifier(player)] = WeakPlayerReference(player)
    }

    func unregister(_ player: PlayerStateViewModel) {
        registeredPlayers[ObjectIdentifier(player)] = nil
        if activePlayer === player {
            activePlayer = nil
            activeGeneration = UUID()
        }
        cleanupRegisteredPlayers()
    }

    @discardableResult
    func activate(_ player: PlayerStateViewModel) -> UUID {
        CiliCiliRuntime.shared.onPlaybackActivation?()
        register(player)
        if let activePlayer, activePlayer !== player {
            activePlayer.pauseForNavigation()
        }
        activePlayer = player
        activeGeneration = UUID()
        return activeGeneration
    }

    func deactivate(_ player: PlayerStateViewModel) {
        guard activePlayer === player else { return }
        activePlayer = nil
        activeGeneration = UUID()
    }

    func stopActivePlayback() {
        let players = registeredPlayersIncludingActive()
        activePlayer = nil
        activeGeneration = UUID()
        players.forEach { $0.stop(reason: .navigation) }
        cleanupRegisteredPlayers()
    }

    func pauseActivePlaybackForNavigation() {
        activePlayer?.pauseForNavigation()
    }

    @discardableResult
    func pauseActivePlaybackForAppBackground() -> Bool {
        cleanupRegisteredPlayers()
        return activePlayer?.pauseForAppBackground() ?? false
    }

    @discardableResult
    func resumeActivePlaybackAfterCancelledNavigation() -> Bool {
        activePlayer?.restoreAudioAfterCancelledNavigation() ?? false
    }

    func isActive(_ player: PlayerStateViewModel) -> Bool {
        activePlayer === player
    }

    func currentActivePlayer() -> PlayerStateViewModel? {
        activePlayer
    }

    private func registeredPlayersIncludingActive() -> [PlayerStateViewModel] {
        cleanupRegisteredPlayers()
        var players = registeredPlayers.values.compactMap(\.player)
        if let activePlayer, !players.contains(where: { $0 === activePlayer }) {
            players.append(activePlayer)
        }
        return players
    }

    private func cleanupRegisteredPlayers() {
        registeredPlayers = registeredPlayers.filter { $0.value.player != nil }
    }
}

private struct WeakPlayerReference {
    weak var player: PlayerStateViewModel?

    init(_ player: PlayerStateViewModel) {
        self.player = player
    }
}

enum PlayerStopReason {
    case navigation
    case replacedByAnotherPlayer
    case deallocated
}

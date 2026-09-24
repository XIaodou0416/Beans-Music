import Foundation

struct PlaybackNetworkPlayerDiagnosticRowItem: Identifiable {
    let title: String
    let value: String

    var id: String { title }
}

struct PlaybackNetworkPlayerDiagnosticMultilineItem: Identifiable {
    let title: String
    let value: String

    var id: String { title }
}

struct PlaybackNetworkPlayerDiagnosticSnapshot {
    let rows: [PlaybackNetworkPlayerDiagnosticRowItem]
    let multilineRows: [PlaybackNetworkPlayerDiagnosticMultilineItem]

    @MainActor
    init(
        playerViewModel: PlayerStateViewModel,
        fallbackMessage: String?
    ) {
        rows = Self.rows(playerViewModel: playerViewModel)
        multilineRows = Self.multilineRows(
            playerViewModel: playerViewModel,
            fallbackMessage: fallbackMessage
        )
    }
}

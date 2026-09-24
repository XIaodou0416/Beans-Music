import Foundation

extension PlaybackNetworkPlayerDiagnosticSnapshot {
    @MainActor
    static func hlsRows(
        playerViewModel: PlayerStateViewModel
    ) -> [PlaybackNetworkPlayerDiagnosticRowItem] {
        let diagnostics = playerViewModel.engineDiagnostics
        guard diagnostics.hlsVideoVariantCount > 0 else { return [] }
        return [
            PlaybackNetworkPlayerDiagnosticRowItem(
                title: "HLS 档位",
                value: PlaybackNetworkDiagnosticFormat.hlsVariantText(diagnostics)
            )
        ]
    }
}

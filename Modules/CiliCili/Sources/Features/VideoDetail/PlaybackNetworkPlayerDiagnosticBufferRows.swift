import Foundation

extension PlaybackNetworkPlayerDiagnosticSnapshot {
    @MainActor
    static func bufferRows(
        playerViewModel: PlayerStateViewModel
    ) -> [PlaybackNetworkPlayerDiagnosticRowItem] {
        let diagnostics = playerViewModel.engineDiagnostics
        guard let forwardBuffer = diagnostics.preferredForwardBufferDuration else { return [] }
        return [
            PlaybackNetworkPlayerDiagnosticRowItem(
                title: "前向缓冲",
                value: String(format: "%.2fs", forwardBuffer)
            )
        ]
    }
}

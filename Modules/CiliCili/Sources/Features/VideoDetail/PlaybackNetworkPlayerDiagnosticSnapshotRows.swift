import Foundation

extension PlaybackNetworkPlayerDiagnosticSnapshot {
    @MainActor
    static func rows(
        playerViewModel: PlayerStateViewModel
    ) -> [PlaybackNetworkPlayerDiagnosticRowItem] {
        var rows = primaryRows(playerViewModel: playerViewModel)
        rows.append(contentsOf: hlsRows(playerViewModel: playerViewModel))
        rows.append(contentsOf: playbackRows(playerViewModel: playerViewModel))
        rows.append(contentsOf: bufferRows(playerViewModel: playerViewModel))
        return rows
    }

    @MainActor
    static func multilineRows(
        playerViewModel: PlayerStateViewModel,
        fallbackMessage: String?
    ) -> [PlaybackNetworkPlayerDiagnosticMultilineItem] {
        var rows: [PlaybackNetworkPlayerDiagnosticMultilineItem] = []
        if let errorMessage = playerViewModel.errorMessage, !errorMessage.isEmpty {
            rows.append(
                PlaybackNetworkPlayerDiagnosticMultilineItem(title: "错误", value: errorMessage)
            )
        }
        if let fallbackMessage, !fallbackMessage.isEmpty {
            rows.append(
                PlaybackNetworkPlayerDiagnosticMultilineItem(title: "降级信息", value: fallbackMessage)
            )
        }
        return rows
    }
}

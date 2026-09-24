import Foundation

extension PlaybackNetworkPlayerDiagnosticSnapshot {
    @MainActor
    static func playbackRows(
        playerViewModel: PlayerStateViewModel
    ) -> [PlaybackNetworkPlayerDiagnosticRowItem] {
        let loadingProgress = min(max(playerViewModel.loadingProgress, 0), 1)
        return [
            PlaybackNetworkPlayerDiagnosticRowItem(title: "首帧", value: playerViewModel.hasPresentedPlayback ? "已显示" : "等待中"),
            PlaybackNetworkPlayerDiagnosticRowItem(title: "缓冲", value: playerViewModel.isBuffering ? "缓冲中" : "未缓冲"),
            PlaybackNetworkPlayerDiagnosticRowItem(title: "可拖动", value: playerViewModel.canSeek ? "可用" : "等待就绪"),
            PlaybackNetworkPlayerDiagnosticRowItem(title: "恢复次数", value: "\(playerViewModel.recoveryAttemptCount)"),
            PlaybackNetworkPlayerDiagnosticRowItem(
                title: "准备耗时",
                value: PlaybackNetworkDiagnosticFormat.formattedMilliseconds(playerViewModel.prepareElapsedMilliseconds)
            ),
            PlaybackNetworkPlayerDiagnosticRowItem(
                title: "首帧耗时",
                value: PlaybackNetworkDiagnosticFormat.formattedMilliseconds(playerViewModel.firstFrameElapsedMilliseconds)
            ),
            PlaybackNetworkPlayerDiagnosticRowItem(title: "缓冲次数", value: "\(playerViewModel.bufferingCount)"),
            PlaybackNetworkPlayerDiagnosticRowItem(
                title: "最近缓冲",
                value: PlaybackNetworkDiagnosticFormat.formattedMilliseconds(playerViewModel.lastBufferingElapsedMilliseconds)
            ),
            PlaybackNetworkPlayerDiagnosticRowItem(title: "加载进度", value: "\(Int((loadingProgress * 100).rounded()))%")
        ]
    }
}

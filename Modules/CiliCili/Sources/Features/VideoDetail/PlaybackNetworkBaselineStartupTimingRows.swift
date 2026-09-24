import SwiftUI

struct PlaybackNetworkBaselineStartupTimingRows: View {
    let session: PlayerPerformanceSession

    var body: some View {
        PlaybackNetworkDiagnosticRow(
            title: "总首帧",
            value: PlaybackNetworkDiagnosticFormat.formattedMilliseconds(session.firstFrameTotalMilliseconds)
        )
        PlaybackNetworkDiagnosticRow(
            title: "播放器首帧",
            value: PlaybackNetworkDiagnosticFormat.formattedMilliseconds(session.firstFramePlayerMilliseconds)
        )
        PlaybackNetworkDiagnosticRow(
            title: "取流耗时",
            value: PlaybackNetworkDiagnosticFormat.formattedMilliseconds(session.playURLMilliseconds)
        )
        PlaybackNetworkDiagnosticRow(
            title: "取流来源",
            value: PlaybackNetworkDiagnosticFormat.startupPlayURLTitle(for: session)
        )
        PlaybackNetworkDiagnosticRow(
            title: "Prepare",
            value: PlaybackNetworkDiagnosticFormat.formattedMilliseconds(session.prepareMilliseconds)
        )
    }
}

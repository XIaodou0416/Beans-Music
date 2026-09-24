import SwiftUI

struct PlaybackNetworkBaselineStartupRouteRows: View {
    let session: PlayerPerformanceSession

    var body: some View {
        PlaybackNetworkDiagnosticRow(
            title: "启动档位",
            value: PlaybackNetworkDiagnosticFormat.startupQualityTitle(session.startupQuality)
        )
        PlaybackNetworkDiagnosticRow(
            title: "目标档位",
            value: PlaybackNetworkDiagnosticFormat.startupQualityTitle(session.startupTargetQuality)
        )
        PlaybackNetworkDiagnosticRow(
            title: "HLS Route",
            value: PlaybackNetworkDiagnosticFormat.startupRoutePlanTitle(for: session)
        )
        if session.startupRoutePrebuildState != nil {
            PlaybackNetworkDiagnosticRow(
                title: "Route 预构建",
                value: PlaybackNetworkDiagnosticFormat.startupRoutePrebuildTitle(for: session)
            )
        }
        PlaybackNetworkDiagnosticRow(
            title: "启动包",
            value: PlaybackNetworkDiagnosticFormat.startupPackageTitle(for: session)
        )
        PlaybackNetworkDiagnosticRow(
            title: "首片预热",
            value: PlaybackNetworkDiagnosticFormat.startupRangeWarmTitle(for: session)
        )
    }
}

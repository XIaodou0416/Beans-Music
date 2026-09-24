import SwiftUI

struct PlaybackNetworkDiagnosticsLifecycleConfiguration {
    let metricsID: String
    let variantID: String?
    let isAutoOptimizationEnabled: Bool
    let refreshInitialDiagnostics: @MainActor () async -> Void
    let refreshHLSBridgeSources: @MainActor () async -> Void
    let updatePerformanceContext: @MainActor (_ metricsID: String, _ isAutoOptimizationEnabled: Bool) -> Void
    let updateAutoOptimizationContext: @MainActor (_ isEnabled: Bool) -> Void
}

private struct PlaybackNetworkDiagnosticsLifecycleModifier: ViewModifier {
    let configuration: PlaybackNetworkDiagnosticsLifecycleConfiguration
    let actions: PlaybackNetworkDiagnosticsLifecycleActions

    func body(content: Content) -> some View {
        content
            .task {
                await actions.refreshInitialDiagnostics()
            }
            .task(id: configuration.refreshTaskID) {
                await actions.refreshHLSBridgeSources()
            }
            .onChange(of: configuration.metricsID) { _, metricsID in
                actions.handleMetricsChanged(metricsID)
            }
            .onChange(of: configuration.isAutoOptimizationEnabled) { _, isEnabled in
                actions.handleAutoOptimizationChanged(isEnabled)
            }
    }
}

private extension PlaybackNetworkDiagnosticsLifecycleConfiguration {
    var refreshTaskID: String {
        "\(metricsID)|\(variantID ?? "none")"
    }
}

extension View {
    func playbackNetworkDiagnosticsLifecycle(
        configuration: PlaybackNetworkDiagnosticsLifecycleConfiguration
    ) -> some View {
        modifier(
            PlaybackNetworkDiagnosticsLifecycleModifier(
                configuration: configuration,
                actions: PlaybackNetworkDiagnosticsLifecycleActions(configuration: configuration)
            )
        )
    }
}

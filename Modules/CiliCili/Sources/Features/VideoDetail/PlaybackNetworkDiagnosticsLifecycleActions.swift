import Foundation

struct PlaybackNetworkDiagnosticsLifecycleActions {
    let configuration: PlaybackNetworkDiagnosticsLifecycleConfiguration

    @MainActor
    func refreshInitialDiagnostics() async {
        await configuration.refreshInitialDiagnostics()
    }

    @MainActor
    func refreshHLSBridgeSources() async {
        await configuration.refreshHLSBridgeSources()
    }

    @MainActor
    func handleMetricsChanged(_ metricsID: String) {
        configuration.updatePerformanceContext(
            metricsID,
            configuration.isAutoOptimizationEnabled
        )
    }

    @MainActor
    func handleAutoOptimizationChanged(_ isEnabled: Bool) {
        configuration.updateAutoOptimizationContext(isEnabled)
    }
}

import Foundation

enum PlaybackNetworkDiagnosticsLifecycleAction {
    @MainActor
    static func updatePerformanceContext(
        observer: PlayerPerformanceSessionObserver,
        metricsID: String,
        isAutoOptimizationEnabled: Bool
    ) {
        observer.updateContext(
            metricsID: metricsID,
            isAutoOptimizationEnabled: isAutoOptimizationEnabled
        )
    }

    @MainActor
    static func updateAutoOptimizationContext(
        observer: PlayerPerformanceSessionObserver,
        metricsID: String,
        isEnabled: Bool
    ) {
        observer.updateContext(
            metricsID: metricsID,
            isAutoOptimizationEnabled: isEnabled
        )
    }
}

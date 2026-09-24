import Foundation

struct PlayerPerformanceOverlayLifecycleActions {
    let sessionObserver: PlayerPerformanceSessionObserver

    @MainActor
    func handleMetricsChanged(_ metricsID: String) {
        sessionObserver.updateContext(metricsID: metricsID)
    }
}

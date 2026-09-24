import SwiftUI

private struct PlayerPerformanceOverlayLifecycleModifier: ViewModifier {
    let metricsID: String
    let actions: PlayerPerformanceOverlayLifecycleActions

    func body(content: Content) -> some View {
        content
            .onChange(of: metricsID) { _, metricsID in
                actions.handleMetricsChanged(metricsID)
            }
    }
}

extension View {
    func playerPerformanceOverlayLifecycle(
        metricsID: String,
        sessionObserver: PlayerPerformanceSessionObserver
    ) -> some View {
        modifier(
            PlayerPerformanceOverlayLifecycleModifier(
                metricsID: metricsID,
                actions: PlayerPerformanceOverlayLifecycleActions(sessionObserver: sessionObserver)
            )
        )
    }
}

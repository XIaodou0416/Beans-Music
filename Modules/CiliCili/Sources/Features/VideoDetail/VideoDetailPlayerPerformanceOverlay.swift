import Foundation
import SwiftUI

struct VideoDetailPerformanceOverlayContainer: View {
    @ObservedObject var store: VideoDetailNetworkDiagnosticsRenderStore
    @ObservedObject var experimentState: VideoDetailPerformanceExperimentState
    let panelWidth: CGFloat
    let maximumHeight: CGFloat

    var body: some View {
        PlayerPerformanceOverlay(
            diagnosticsStore: store,
            playerViewModel: store.playerViewModel,
            experimentSnapshot: experimentState.snapshot,
            panelWidth: panelWidth,
            maximumHeight: maximumHeight
        )
    }
}

struct PlayerPerformanceOverlay: View {
    @StateObject private var sessionObserver: PlayerPerformanceSessionObserver
    @ObservedObject var diagnosticsStore: VideoDetailNetworkDiagnosticsRenderStore
    let playerViewModel: PlayerStateViewModel?
    let experimentSnapshot: VideoDetailPerformanceExperimentSnapshot
    let panelWidth: CGFloat
    let maximumHeight: CGFloat

    init(
        diagnosticsStore: VideoDetailNetworkDiagnosticsRenderStore,
        playerViewModel: PlayerStateViewModel?,
        experimentSnapshot: VideoDetailPerformanceExperimentSnapshot = VideoDetailPerformanceExperimentSnapshot(),
        panelWidth: CGFloat = 300,
        maximumHeight: CGFloat = 420
    ) {
        self.diagnosticsStore = diagnosticsStore
        self.playerViewModel = playerViewModel
        self.experimentSnapshot = experimentSnapshot
        self.panelWidth = panelWidth
        self.maximumHeight = maximumHeight
        _sessionObserver = StateObject(
            wrappedValue: PlayerPerformanceSessionObserver(metricsID: diagnosticsStore.metricsID)
        )
    }

    private var session: PlayerPerformanceSession? {
        sessionObserver.session
    }

    var body: some View {
        PlayerPerformanceOverlayContent(
            diagnosticsStore: diagnosticsStore,
            metricsID: diagnosticsStore.metricsID,
            session: session,
            playerViewModel: playerViewModel,
            experimentSnapshot: experimentSnapshot,
            panelWidth: panelWidth,
            maximumHeight: maximumHeight
        )
        .playerPerformanceOverlayLifecycle(
            metricsID: diagnosticsStore.metricsID,
            sessionObserver: sessionObserver
        )
    }
}

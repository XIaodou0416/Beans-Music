import Foundation

extension PlaybackNetworkDiagnosticsSheet {
    var diagnosticsText: String {
        let runtimeContext = runtimeContext
        return PlaybackNetworkDiagnosticsTextBuilder(
            diagnosticsStore: diagnosticsStore,
            libraryStore: libraryStore,
            variant: runtimeContext.variant,
            playerViewModel: runtimeContext.playerViewModel,
            playbackEnvironment: runtimeContext.playbackEnvironment,
            playbackAdaptationProfile: runtimeContext.playbackAdaptationProfile,
            performanceSession: runtimeContext.performanceSession,
            currentHostSnapshot: runtimeContext.currentHostSnapshot,
            playbackURLPreferenceSnapshots: sheetState.playbackURLPreferenceSnapshots,
            hlsBridgeSourceSnapshots: sheetState.hlsBridgeSourceSnapshots,
            cacheSummary: sheetState.cacheSummary
        )
        .text
    }
}

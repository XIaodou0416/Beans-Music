import Foundation

struct PlaybackNetworkDiagnosticsRuntimeContext {
    let variant: PlayVariant?
    let playerViewModel: PlayerStateViewModel?
    let playbackEnvironment: PlaybackEnvironment
    let performanceSession: PlayerPerformanceSession?
    let playbackAdaptationProfile: PlayerPlaybackAdaptationProfile
    let currentHostSnapshot: PlaybackURLPreferenceSnapshot?

    @MainActor
    init(
        diagnosticsStore: VideoDetailNetworkDiagnosticsRenderStore,
        performanceObserver: PlayerPerformanceSessionObserver,
        playbackURLPreferenceSnapshots: [PlaybackURLPreferenceSnapshot]
    ) {
        let variant = diagnosticsStore.selectedPlayVariant
        self.variant = variant
        playerViewModel = diagnosticsStore.playerViewModel
        playbackEnvironment = PlaybackEnvironment.current
        performanceSession = performanceObserver.session
        playbackAdaptationProfile = performanceObserver.playbackAdaptationProfile
        currentHostSnapshot = PlaybackNetworkDiagnosticsURLContext.currentHostSnapshot(
            variant: variant,
            snapshots: playbackURLPreferenceSnapshots
        )
    }
}

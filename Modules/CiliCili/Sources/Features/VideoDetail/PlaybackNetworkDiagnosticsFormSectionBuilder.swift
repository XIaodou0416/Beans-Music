import SwiftUI

struct PlaybackNetworkDiagnosticsFormSectionBuilder {
    @ObservedObject var diagnosticsStore: VideoDetailNetworkDiagnosticsRenderStore
    @ObservedObject var relatedStore: VideoDetailRelatedRenderStore
    @ObservedObject var libraryStore: LibraryStore

    let configuration: PlaybackNetworkDiagnosticsFormConfiguration
    let runtimeContext: PlaybackNetworkDiagnosticsRuntimeContext

    @ViewBuilder
    var sections: some View {
        PlaybackNetworkActionsSection(
            copiedMessage: configuration.copiedMessage,
            isProbingPlaybackCDN: configuration.isProbingPlaybackCDN,
            probeMessage: configuration.probeMessage,
            onCopyDiagnostics: configuration.onCopyDiagnostics,
            onProbePlaybackCDN: configuration.onProbePlaybackCDN
        )
        PlaybackNetworkCDNSection(
            libraryStore: libraryStore,
            variant: runtimeContext.variant,
            currentHostSnapshot: runtimeContext.currentHostSnapshot,
            playbackURLPreferenceSnapshots: configuration.playbackURLPreferenceSnapshots
        )
        PlaybackNetworkHLSBridgeSection(
            variant: runtimeContext.variant,
            snapshots: configuration.hlsBridgeSourceSnapshots
        )
        PlaybackNetworkLoadingMetricsSection(
            detailLoadElapsedMilliseconds: diagnosticsStore.detailLoadElapsedMilliseconds,
            playURLElapsedMilliseconds: diagnosticsStore.playURLElapsedMilliseconds,
            relatedElapsedMilliseconds: diagnosticsStore.relatedElapsedMilliseconds,
            playURLSource: diagnosticsStore.lastPlayURLSource,
            didRelatedLoadTimeOut: relatedStore.lastLoadTimedOut
        )
        PlaybackNetworkResumeSection(diagnostics: diagnosticsStore.resumeDiagnostics)
        PlaybackNetworkStreamSection(variant: runtimeContext.variant)
        PlaybackNetworkPlayerStatusSection(
            playerViewModel: runtimeContext.playerViewModel,
            fallbackMessage: diagnosticsStore.playbackFallbackMessage
        )
        PlaybackNetworkBaselineSection(
            profile: runtimeContext.playbackAdaptationProfile,
            session: runtimeContext.performanceSession,
            cacheSummary: configuration.cacheSummary
        )
        PlaybackNetworkEnvironmentSection(
            playbackAutoOptimizationTitle: libraryStore.playbackAutoOptimizationMode.title,
            environment: runtimeContext.playbackEnvironment
        )
        PlaybackNetworkProbeSection(libraryStore: libraryStore)
    }
}

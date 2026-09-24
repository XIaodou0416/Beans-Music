import Foundation

extension PlaybackNetworkDiagnosticsSheet {
    var formConfiguration: PlaybackNetworkDiagnosticsFormConfiguration {
        let runtimeContext = runtimeContext
        return PlaybackNetworkDiagnosticsFormConfiguration(
            runtimeContext: runtimeContext,
            copiedMessage: sheetState.copiedMessage,
            isProbingPlaybackCDN: sheetState.isProbingPlaybackCDN,
            probeMessage: sheetState.probeMessage,
            cacheSummary: sheetState.cacheSummary,
            playbackURLPreferenceSnapshots: sheetState.playbackURLPreferenceSnapshots,
            hlsBridgeSourceSnapshots: sheetState.hlsBridgeSourceSnapshots,
            onCopyDiagnostics: copyDiagnostics,
            onProbePlaybackCDN: probePlaybackCDN
        )
    }

    var lifecycleConfiguration: PlaybackNetworkDiagnosticsLifecycleConfiguration {
        PlaybackNetworkDiagnosticsLifecycleConfiguration(
            metricsID: diagnosticsStore.metricsID,
            variantID: runtimeContext.variant?.id,
            isAutoOptimizationEnabled: libraryStore.isPlaybackAutoOptimizationEnabled,
            refreshInitialDiagnostics: refreshInitialDiagnostics,
            refreshHLSBridgeSources: refreshHLSBridgeSourceSnapshots,
            updatePerformanceContext: updatePerformanceContext,
            updateAutoOptimizationContext: updateAutoOptimizationContext
        )
    }

    var stateActions: PlaybackNetworkDiagnosticsActionHandler.StateActions {
        PlaybackNetworkDiagnosticsActionHandler.StateActions(
            setCopiedMessage: setCopiedMessage,
            setIsProbing: setIsProbingPlaybackCDN,
            setProbeMessage: setProbeMessage,
            setPlaybackURLPreferenceSnapshots: setPlaybackURLPreferenceSnapshots,
            setHLSBridgeSourceSnapshots: setHLSBridgeSourceSnapshots,
            setCacheSummary: setCacheSummary
        )
    }
}

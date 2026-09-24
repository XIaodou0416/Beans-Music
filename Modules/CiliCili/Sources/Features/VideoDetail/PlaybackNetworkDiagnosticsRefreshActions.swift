import Foundation

extension PlaybackNetworkDiagnosticsActionHandler {
    static func refreshInitialDiagnostics(
        variant: PlayVariant?,
        cdnPreference: PlaybackCDNPreference,
        stateActions: StateActions
    ) async {
        refreshPlaybackURLPreferenceSnapshots(
            stateActions: stateActions
        )
        await refreshHLSBridgeSourceSnapshots(
            variant: variant,
            cdnPreference: cdnPreference,
            stateActions: stateActions
        )
        stateActions.setCacheSummary(await PlaybackNetworkDiagnosticsRefreshAction.cacheSummary())
    }

    static func refreshPlaybackURLPreferenceSnapshots(
        stateActions: StateActions
    ) {
        stateActions.setPlaybackURLPreferenceSnapshots(
            PlaybackNetworkDiagnosticsRefreshAction.playbackURLPreferenceSnapshots()
        )
    }

    static func refreshHLSBridgeSourceSnapshots(
        variant: PlayVariant?,
        cdnPreference: PlaybackCDNPreference,
        stateActions: StateActions
    ) async {
        let snapshots = await PlaybackNetworkDiagnosticsRefreshAction.hlsBridgeSourceSnapshots(
            variant: variant,
            cdnPreference: cdnPreference
        )
        stateActions.setHLSBridgeSourceSnapshots(snapshots)
    }
}

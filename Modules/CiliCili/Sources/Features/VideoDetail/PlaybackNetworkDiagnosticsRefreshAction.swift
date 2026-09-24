import Foundation

enum PlaybackNetworkDiagnosticsRefreshAction {
    static func playbackURLPreferenceSnapshots(limit: Int = 8) -> [PlaybackURLPreferenceSnapshot] {
        PlaybackURLPreferenceStore.shared.rankedSnapshots(limit: limit)
    }

    static func cacheSummary() async -> ResourceCacheSummary {
        await ResourceCacheCenter.summary()
    }

    @MainActor
    static func hlsBridgeSourceSnapshots(
        variant: PlayVariant?,
        cdnPreference: PlaybackCDNPreference
    ) async -> [HLSBridgeSourceDiagnosticsSnapshot] {
        let urls = PlaybackNetworkDiagnosticsURLContext.hlsBridgeCandidateURLs(
            variant: variant,
            cdnPreference: cdnPreference
        )
        guard !urls.isEmpty else { return [] }
        return await LocalHLSBridge.sourceDiagnostics(for: urls)
    }
}

import Foundation

extension PlaybackNetworkDiagnosticsSheet {
    @MainActor
    func setCopiedMessage(_ message: String?) {
        sheetState.copiedMessage = message
    }

    @MainActor
    func setIsProbingPlaybackCDN(_ isProbing: Bool) {
        sheetState.isProbingPlaybackCDN = isProbing
    }

    @MainActor
    func setProbeMessage(_ message: String?) {
        sheetState.probeMessage = message
    }

    @MainActor
    func setCacheSummary(_ summary: ResourceCacheSummary?) {
        sheetState.cacheSummary = summary
    }

    @MainActor
    func setPlaybackURLPreferenceSnapshots(_ snapshots: [PlaybackURLPreferenceSnapshot]) {
        sheetState.playbackURLPreferenceSnapshots = snapshots
    }

    @MainActor
    func setHLSBridgeSourceSnapshots(_ snapshots: [HLSBridgeSourceDiagnosticsSnapshot]) {
        sheetState.hlsBridgeSourceSnapshots = snapshots
    }
}

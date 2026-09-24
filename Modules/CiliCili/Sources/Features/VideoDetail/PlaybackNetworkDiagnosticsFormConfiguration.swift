import Foundation

struct PlaybackNetworkDiagnosticsFormConfiguration {
    let runtimeContext: PlaybackNetworkDiagnosticsRuntimeContext
    let copiedMessage: String?
    let isProbingPlaybackCDN: Bool
    let probeMessage: String?
    let cacheSummary: ResourceCacheSummary?
    let playbackURLPreferenceSnapshots: [PlaybackURLPreferenceSnapshot]
    let hlsBridgeSourceSnapshots: [HLSBridgeSourceDiagnosticsSnapshot]
    let onCopyDiagnostics: () -> Void
    let onProbePlaybackCDN: () -> Void
}

import Foundation

struct PlaybackNetworkDiagnosticsSheetState {
    var isProbingPlaybackCDN = false
    var playbackCDNProbeTask: Task<Void, Never>?
    var playbackCDNProbeToken: UUID?
    var probeMessage: String?
    var copiedMessageTask: Task<Void, Never>?
    var copiedMessageToken: UUID?
    var copiedMessage: String?
    var cacheSummary: ResourceCacheSummary?
    var playbackURLPreferenceSnapshots: [PlaybackURLPreferenceSnapshot] = []
    var hlsBridgeSourceSnapshots: [HLSBridgeSourceDiagnosticsSnapshot] = []
}

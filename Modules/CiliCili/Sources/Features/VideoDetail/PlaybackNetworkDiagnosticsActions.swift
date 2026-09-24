import Foundation

@MainActor
enum PlaybackNetworkDiagnosticsActionHandler {
    struct StateActions {
        let setCopiedMessage: @MainActor (String?) -> Void
        let setIsProbing: @MainActor (Bool) -> Void
        let setProbeMessage: @MainActor (String?) -> Void
        let setPlaybackURLPreferenceSnapshots: @MainActor ([PlaybackURLPreferenceSnapshot]) -> Void
        let setHLSBridgeSourceSnapshots: @MainActor ([HLSBridgeSourceDiagnosticsSnapshot]) -> Void
        let setCacheSummary: @MainActor (ResourceCacheSummary?) -> Void
    }
}

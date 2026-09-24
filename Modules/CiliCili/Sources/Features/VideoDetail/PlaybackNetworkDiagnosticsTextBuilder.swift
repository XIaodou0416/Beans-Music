import Foundation

@MainActor
struct PlaybackNetworkDiagnosticsTextBuilder {
    let diagnosticsStore: VideoDetailNetworkDiagnosticsRenderStore
    let libraryStore: LibraryStore
    let variant: PlayVariant?
    let playerViewModel: PlayerStateViewModel?
    let playbackEnvironment: PlaybackEnvironment
    let playbackAdaptationProfile: PlayerPlaybackAdaptationProfile
    let performanceSession: PlayerPerformanceSession?
    let currentHostSnapshot: PlaybackURLPreferenceSnapshot?
    let playbackURLPreferenceSnapshots: [PlaybackURLPreferenceSnapshot]
    let hlsBridgeSourceSnapshots: [HLSBridgeSourceDiagnosticsSnapshot]
    let cacheSummary: ResourceCacheSummary?

    var text: String {
        var lines = [String]()
        appendHeaderLines(to: &lines)
        appendCDNLines(to: &lines)
        appendStreamLines(to: &lines)
        appendLoadingLines(to: &lines)
        appendResumeLines(to: &lines)
        appendBaselineLines(to: &lines)
        appendPerformanceSessionLines(to: &lines)
        appendCacheLines(to: &lines)
        appendPlayerLines(to: &lines)
        appendEnvironmentLines(to: &lines)
        appendProbeLines(to: &lines)
        appendErrorLines(to: &lines)
        return lines.joined(separator: "\n")
    }
}

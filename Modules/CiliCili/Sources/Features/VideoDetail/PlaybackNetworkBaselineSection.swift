import SwiftUI

struct PlaybackNetworkBaselineSection: View {
    let profile: PlayerPlaybackAdaptationProfile
    let session: PlayerPerformanceSession?
    let cacheSummary: ResourceCacheSummary?

    var body: some View {
        Section("性能基线") {
            PlaybackNetworkBaselineProfileRows(profile: profile)
            PlaybackNetworkBaselineSessionRows(session: session)
            PlaybackNetworkBaselineCacheRows(cacheSummary: cacheSummary)
        }
    }
}

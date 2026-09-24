import SwiftUI

struct PlaybackNetworkBaselineStartupSessionRows: View {
    let session: PlayerPerformanceSession

    @ViewBuilder
    var body: some View {
        PlaybackNetworkBaselineStartupTimingRows(session: session)
        PlaybackNetworkBaselineStartupRouteRows(session: session)
        PlaybackNetworkBaselineStartupMessageRows(session: session)
    }
}

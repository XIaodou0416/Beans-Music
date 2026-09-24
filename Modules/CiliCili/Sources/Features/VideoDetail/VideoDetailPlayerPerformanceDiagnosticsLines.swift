import SwiftUI

struct PlayerPerformanceOverlayDiagnosticsLines: View {
    let session: PlayerPerformanceSession
    let playerViewModel: PlayerStateViewModel?

    var body: some View {
        PlayerPerformanceOverlayDetailAndEngineLines(
            session: session,
            playerViewModel: playerViewModel
        )
        PlayerPerformanceOverlayNetworkAndCacheLines(session: session)
        PlayerPerformanceOverlayResumeLines(session: session)
        PlayerPerformanceOverlaySeekAndSpeedLines(session: session)
        PlayerPerformanceOverlayStartupLines(session: session)
    }
}

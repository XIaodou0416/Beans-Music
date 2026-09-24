import SwiftUI

struct PlayerPerformanceOverlayDiagnosticsSection: View {
    let session: PlayerPerformanceSession
    let playerViewModel: PlayerStateViewModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PlayerPerformanceOverlayDiagnosticsLines(
                session: session,
                playerViewModel: playerViewModel
            )
        }
        .font(.caption2)
    }
}

import Foundation
import SwiftUI

struct PlaybackNetworkPlayerSection: View {
    @ObservedObject var playerViewModel: PlayerStateViewModel
    let fallbackMessage: String?

    var body: some View {
        let snapshot = PlaybackNetworkPlayerDiagnosticSnapshot(
            playerViewModel: playerViewModel,
            fallbackMessage: fallbackMessage
        )

        Section("播放器") {
            ForEach(snapshot.rows) { row in
                PlaybackNetworkDiagnosticRow(title: row.title, value: row.value)
            }

            ForEach(snapshot.multilineRows) { row in
                PlaybackNetworkDiagnosticMultilineRow(title: row.title, value: row.value)
            }
        }
    }
}

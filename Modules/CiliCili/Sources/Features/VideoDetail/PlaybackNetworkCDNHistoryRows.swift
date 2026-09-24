import SwiftUI

struct PlaybackNetworkCDNHistoryRows: View {
    let currentHostSnapshot: PlaybackURLPreferenceSnapshot?
    let playbackURLPreferenceSnapshots: [PlaybackURLPreferenceSnapshot]

    var body: some View {
        if let currentHostSnapshot {
            PlaybackNetworkDiagnosticMultilineRow(
                title: "当前 Host 历史",
                value: PlaybackNetworkDiagnosticFormat.playbackURLPreferenceSummary(currentHostSnapshot)
            )
        }

        if !playbackURLPreferenceSnapshots.isEmpty {
            DisclosureGroup {
                ForEach(playbackURLPreferenceSnapshots.prefix(6)) { snapshot in
                    PlaybackNetworkURLPreferenceRow(snapshot: snapshot)
                }
            } label: {
                Label("真实播放排行", systemImage: "list.bullet.rectangle")
            }
        }
    }
}

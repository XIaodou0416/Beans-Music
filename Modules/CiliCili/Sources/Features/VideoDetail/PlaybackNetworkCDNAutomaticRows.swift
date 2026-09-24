import SwiftUI

struct PlaybackNetworkCDNAutomaticRows: View {
    @ObservedObject var libraryStore: LibraryStore

    var body: some View {
        if libraryStore.playbackCDNPreference == .automatic {
            PlaybackNetworkDiagnosticRow(
                title: "测速参考",
                value: libraryStore.automaticPlaybackCDNRecommendation?.title ?? "暂无可用推荐"
            )
            if let avoidanceDescription = libraryStore.activePlaybackCDNAvoidanceDescription {
                PlaybackNetworkDiagnosticRow(title: "临时避让", value: avoidanceDescription)
            }
        }
    }
}

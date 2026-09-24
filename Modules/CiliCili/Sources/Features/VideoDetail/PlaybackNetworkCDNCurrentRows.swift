import SwiftUI

struct PlaybackNetworkCDNCurrentRows: View {
    @ObservedObject var libraryStore: LibraryStore

    var body: some View {
        PlaybackNetworkDiagnosticRow(
            title: "当前使用",
            value: libraryStore.effectivePlaybackCDNPreference.title
        )
        PlaybackNetworkDiagnosticRow(
            title: "设置模式",
            value: libraryStore.playbackCDNPreference.title
        )
        PlaybackNetworkDiagnosticRow(
            title: "网络协议",
            value: libraryStore.playbackNetworkAddressFamilyPreference.title
        )
    }
}

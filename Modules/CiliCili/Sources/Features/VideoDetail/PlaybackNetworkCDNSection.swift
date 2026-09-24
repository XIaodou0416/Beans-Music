import SwiftUI

struct PlaybackNetworkCDNSection: View {
    @ObservedObject var libraryStore: LibraryStore
    let variant: PlayVariant?
    let currentHostSnapshot: PlaybackURLPreferenceSnapshot?
    let playbackURLPreferenceSnapshots: [PlaybackURLPreferenceSnapshot]

    var body: some View {
        Section("CDN") {
            PlaybackNetworkCDNCurrentRows(libraryStore: libraryStore)
            PlaybackNetworkCDNAutomaticRows(libraryStore: libraryStore)
            PlaybackNetworkCDNHostRows(variant: variant)
            PlaybackNetworkCDNHistoryRows(
                currentHostSnapshot: currentHostSnapshot,
                playbackURLPreferenceSnapshots: playbackURLPreferenceSnapshots
            )
        }
    }
}

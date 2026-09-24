import SwiftUI

struct MinePlaybackSettingsView: View {
    @ObservedObject var libraryStore: LibraryStore
    @AppStorage("cc.bili.playback.showsAdvancedSettings.v1") var showsAdvancedPlaybackSettings = false
    @State var isProbingPlaybackCDN = false
    @State var playbackCDNProbeResults: [PlaybackCDNProbeResult] = []
    @State var playbackCDNProbeMessage: String?
    @State var playbackCDNProbeTask: Task<Void, Never>?
    @State var isShowingPlaybackCDNProbeDetails = false
    @State var playbackURLPreferenceSnapshots: [PlaybackURLPreferenceSnapshot] = []
    @State var isShowingPlaybackURLPreferenceDetails = false
    @State var playbackCustomCDNHostDraft = ""

    var body: some View {
        Form {
            MinePlaybackPreferenceSection(
                libraryStore: libraryStore,
                playbackPreferenceSummary: AnyView(playbackPreferenceSummary),
                playbackCDNProbeRefreshIntervalTitle: playbackCDNProbeRefreshIntervalTitle,
                isProbingPlaybackCDN: isProbingPlaybackCDN,
                playbackCDNProbeMessage: playbackCDNProbeMessage,
                probePlaybackCDN: probePlaybackCDN,
                showsAdvancedPlaybackSettings: $showsAdvancedPlaybackSettings,
                playbackCustomCDNHostDraft: $playbackCustomCDNHostDraft,
                commitPlaybackCustomCDNHost: commitPlaybackCustomCDNHost
            ) {
                playbackCDNProbeSummary
                playbackURLPreferenceSummary
            }

            MinePlaybackToolsSection(libraryStore: libraryStore)
        }
        .tint(libraryStore.appTintColor)
        .formStyle(.grouped)
        .nativeTopScrollEdgeEffect()
        .hiddenInlineNavigationTitle()
        .task {
            playbackCustomCDNHostDraft = libraryStore.playbackCustomCDNHost ?? ""
            refreshPlaybackURLPreferenceSnapshots()
            refreshPlaybackCDNProbeIfNeeded()
        }
        .onChange(of: libraryStore.playbackCustomCDNHost) { _, host in
            playbackCustomCDNHostDraft = host ?? ""
        }
        .onDisappear {
            playbackCDNProbeTask?.cancel()
            playbackCDNProbeTask = nil
            isProbingPlaybackCDN = false
        }
    }

}

extension MinePlaybackSettingsView {
    func commitPlaybackCustomCDNHost() {
        let trimmedHost = playbackCustomCDNHostDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            playbackCustomCDNHostDraft = ""
            libraryStore.setPlaybackCustomCDNHost(nil)
            return
        }
        guard let normalizedHost = PlaybackCDNPreference.normalizedCustomHost(trimmedHost) else {
            return
        }
        playbackCustomCDNHostDraft = normalizedHost
        libraryStore.setPlaybackCustomCDNHost(normalizedHost)
        libraryStore.setPlaybackCDNPreference(.custom)
    }
}

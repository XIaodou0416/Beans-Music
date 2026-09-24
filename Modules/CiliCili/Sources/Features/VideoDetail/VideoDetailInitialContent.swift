import SwiftUI

struct VideoDetailInitialContent: View {
    let seedVideo: VideoItem
    @Binding var selectedContentTab: VideoDetailContentTab
    let runtimeSettings: VideoDetailRuntimeSettingsSnapshot
    let onNavigateBack: () -> Void

    var body: some View {
        VideoDetailInitialPlaybackPage(
            seedVideo: seedVideo,
            selectedContentTab: $selectedContentTab,
            runtimeSettings: runtimeSettings,
            onNavigateBack: onNavigateBack
        )
    }
}

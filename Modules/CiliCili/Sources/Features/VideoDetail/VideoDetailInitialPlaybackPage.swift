import SwiftUI
import UIKit

struct VideoDetailInitialPlaybackPage: View {
    let seedVideo: VideoItem
    @Binding var selectedContentTab: VideoDetailContentTab
    let runtimeSettings: VideoDetailRuntimeSettingsSnapshot
    let onNavigateBack: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let layout = VideoDetailInitialPlaybackLayout(
                proxy: proxy,
                isPortraitVideo: isInitialPortraitVideo
            )

            VideoDetailInitialPlaybackStage(
                seedVideo: seedVideo,
                layout: layout,
                containerHeight: proxy.size.height,
                selectedContentTab: $selectedContentTab,
                runtimeSettings: runtimeSettings,
                onNavigateBack: onNavigateBack
            )
        }
    }

    private var isInitialPortraitVideo: Bool {
        VideoDetailInitialVideoGeometry.metadataAspectRatio(for: seedVideo).map { $0 < 0.9 } ?? false
    }
}

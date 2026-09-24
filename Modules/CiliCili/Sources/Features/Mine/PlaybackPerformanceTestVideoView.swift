import SwiftUI

struct PlaybackPerformanceTestVideoView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    let testVideo: PlaybackPerformanceTestVideo
    @State private var isReady = false

    var body: some View {
        Group {
            if isReady {
                VideoDetailView(
                    seedVideo: testVideo.seedVideo,
                    playbackOptions: .performanceTest
                )
            } else {
                ZStack {
                    Color.black.ignoresSafeArea()
                    ProgressView("正在清理测试缓存")
                        .tint(.white)
                        .foregroundStyle(.white)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            guard !isReady else { return }
            await ResourceCacheCenter.clearPlaybackPerformanceTestCache(
                bvid: testVideo.bvid,
                mediaURLs: [],
                api: dependencies.api
            )
            guard !Task.isCancelled else { return }
            PlayerMetricsLog.record(
                .routeOpen,
                metricsID: testVideo.bvid,
                title: testVideo.title,
                message: "performanceTest coldStart"
            )
            isReady = true
        }
    }
}

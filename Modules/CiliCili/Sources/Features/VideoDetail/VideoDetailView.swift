import SwiftUI

struct VideoDetailView: View {
    @EnvironmentObject private var dependencies: AppDependencies
    @Environment(\.dismiss) private var dismiss
    let seedVideo: VideoItem
    private let playbackOptions: VideoDetailPlaybackOptions
    private let onRequestClose: (() -> Void)?
    private let onPopOne: (() -> Void)?

    @StateObject private var holder = VideoDetailViewModelHolder()
    @StateObject private var runtimeSettings = VideoDetailRuntimeSettingsStore()
    @State private var presentationState = VideoDetailViewPresentationState()
    @State private var pendingCommentAnchor: VideoCommentAnchor?

    init(
        seedVideo: VideoItem,
        playbackOptions: VideoDetailPlaybackOptions = VideoDetailPlaybackOptions(),
        initialCommentAnchor: VideoCommentAnchor? = nil,
        onRequestClose: (() -> Void)? = nil,
        onPopOne: (() -> Void)? = nil
    ) {
        self.seedVideo = seedVideo
        self.playbackOptions = playbackOptions
        self.onRequestClose = onRequestClose
        self.onPopOne = onPopOne
        _pendingCommentAnchor = State(initialValue: initialCommentAnchor)
    }

    var body: some View {
        PlaybackDetailPageHost(
            hidesSystemChrome: .constant(false),
            background: .black,
            navigationBarVisibility: .hidden,
            hidesBackButton: true,
            statusBarStyle: .lightContent,
            performanceContext: .video(seedVideo),
            lifecycleActions: pageLifecycleActions
        ) {
            VideoDetailViewContent(
                seedVideo: seedVideo,
                holder: holder,
                runtimeSettings: runtimeSettings,
                selectedContentTab: $presentationState.selectedContentTab,
                sheetRoute: $presentationState.sheetRoute,
                pendingCommentAnchor: $pendingCommentAnchor,
                isShowingDanmakuSettings: $presentationState.isShowingDanmakuSettings,
                isShowingFavoriteFolders: $presentationState.isShowingFavoriteFolders,
                isShowingCoinPicker: $presentationState.isShowingCoinPicker,
                isShowingNetworkDiagnostics: $presentationState.isShowingNetworkDiagnostics,
                onNavigateBack: popOneVideoLevel,
                lifecycleActions: contentLifecycleActions
            )
            .environment(\.markRelatedVideoNavigation) {
                holder.viewModel?.markRelatedVideoNavigation()
            }
        }
    }

    private var contentLifecycleActions: VideoDetailViewContentLifecycleActions {
        VideoDetailViewContentLifecycleActions(
            configureViewModel: viewActions.configureViewModel
        )
    }

    private var pageLifecycleActions: PlaybackDetailPageLifecycleActions {
        PlaybackDetailPageLifecycleActions(
            onAppear: {
                guard let viewModel = holder.viewModel else { return }
                Task { await viewModel.resumePlaybackAfterCoveredNavigationIfNeeded() }
            },
            onDisappear: {
                let performanceTestMediaURLs = holder.viewModel?.performanceTestMediaURLs ?? []
                holder.viewModel?.stopPlaybackForNavigation()
                guard playbackOptions == .performanceTest else { return }
                clearPerformanceTestCache(
                    bvid: seedVideo.bvid,
                    mediaURLs: performanceTestMediaURLs
                )
            }
        )
    }

    private func clearPerformanceTestCache(bvid: String, mediaURLs: Set<String>) {
        let application = UIApplication.shared
        let backgroundTaskID = application.beginBackgroundTask(withName: "cc.bili.playback-performance-test-cache")
        Task(priority: .utility) {
            await ResourceCacheCenter.clearPlaybackPerformanceTestCache(
                bvid: bvid,
                mediaURLs: mediaURLs,
                api: dependencies.api
            )
            await MainActor.run {
                guard backgroundTaskID != .invalid else { return }
                application.endBackgroundTask(backgroundTaskID)
            }
        }
    }

    private var viewActions: VideoDetailViewActions {
        VideoDetailViewActionsBuilder(
            seedVideo: seedVideo,
            playbackOptions: playbackOptions,
            dependencies: dependencies,
            holder: holder,
            dismiss: dismiss,
            onRequestClose: onRequestClose,
            onPopOne: onPopOne
        )
        .actions
    }

    private func dismissVideoDetail() {
        viewActions.dismissVideoDetail(presentationState: $presentationState)
    }

    private func popOneVideoLevel() {
        viewActions.popOneVideoLevel(presentationState: $presentationState)
    }
}

import Foundation
import Combine
import OSLog
import QuartzCore
import UIKit

@MainActor
final class VideoDetailViewModel: ObservableObject {
    @Published var detail: VideoItem {
        didSet {
            refreshDetailDisplayMetrics()
            scheduleRenderStoreSync([.description, .playback, .networkDiagnostics, .danmaku])
        }
    }
    @Published var playVariants: [PlayVariant] = [] { didSet { scheduleRenderStoreSync(.playback) } }
    @Published var selectedPlayVariant: PlayVariant? {
        didSet {
            scheduleRenderStoreSync([.playback, .networkDiagnostics])
        }
    }
    let renderStores = VideoDetailViewModelRenderStores()
    var detailPresentationState = VideoDetailPresentationState()
    var relatedStateStorage = VideoDetailRelatedState()
    var commentListState = VideoDetailCommentListState()
    @Published var selectedCID: Int? { didSet { scheduleRenderStoreSync(.playback) } }
    @Published var state: LoadingState = .idle {
        didSet { scheduleRenderStoreSync(.playback) }
    }
    @Published var playURLState: LoadingState = .idle {
        didSet {
            scheduleRenderStoreSync(.playback)
            if playURLState.isLoading {
                beginPlaybackStartupAttempt()
            } else if case .failed = playURLState {
                finishPlaybackStartupWaiters(with: .failed)
            }
        }
    }
    @Published var isSwitchingPlayQuality = false { didSet { scheduleRenderStoreSync(.playback) } }
    @Published var pendingPlayVariantID: String? { didSet { scheduleRenderStoreSync(.playback) } }
    @Published var playbackContentMode: PlayerPlaybackContentMode = .video {
        didSet { scheduleRenderStoreSync([.playback, .networkDiagnostics, .danmaku]) }
    }
    @Published var isSwitchingVideoListenMode = false {
        didSet { scheduleRenderStoreSync(.playback) }
    }
    @Published var videoListenAudioVariants: [VideoListenAudioVariant] = []
    @Published var selectedVideoListenAudioPreferenceKey: String?
    var automaticVideoListenAudioVariantID: String?
    var failedVideoListenAudioVariantIDs = Set<String>()
    var pendingVideoListenPlaybackIntent: Bool?
    @Published var videoListenPgcSeasonInfo: PgcSeasonInfo?
    var videoListenPgcSeasonID: Int?
    @Published var videoListenQueueSession: VideoListenQueueSession
    var videoListenQueueTask: Task<Void, Never>?
    var videoListenQueueTaskGeneration = 0
    var videoListenContentSwitchTask: Task<Void, Never>?
    @Published var videoListenSleepTimerOption: VideoListenSleepTimerOption = .off
    @Published var videoListenSleepTimerDeadline: Date?
    var videoListenSleepTimerTask: Task<Void, Never>?
    let videoListenPlaybackSessionStore: VideoListenPlaybackSessionStore
    var pendingVideoListenPlaybackSessionState: VideoListenPlaybackSessionState?
    @Published var interactionState = VideoInteractionState() {
        didSet {
            scheduleRenderStoreSync([.interaction, .description])
        }
    }
    @Published var interactionMessage: String? {
        didSet { scheduleRenderStoreSync(.interaction) }
    }
    @Published var isMutatingInteraction = false {
        didSet {
            scheduleRenderStoreSync([.interaction, .favoriteFolder, .description])
        }
    }
    var interactionMutationState = VideoDetailInteractionMutationState()
    var interactionMutationRevision = 0
    @Published var favoriteFolders: [FavoriteFolder] = [] {
        didSet { scheduleRenderStoreSync(.favoriteFolder) }
    }
    @Published var favoriteFolderState: LoadingState = .idle {
        didSet { scheduleRenderStoreSync(.favoriteFolder) }
    }
    @Published var stablePlayerViewModel: PlayerStateViewModel? {
        didSet {
            stablePlayerState.playbackSession.replaceActivePlayer(with: stablePlayerViewModel)
            cleanupStablePlaybackBeforeDeinit = Self.makeDeinitPlaybackCleanup(for: stablePlayerViewModel)
            scheduleRenderStoreSync([.networkDiagnostics, .playerIdentity])
        }
    }
    @Published var playbackFallbackMessage: String? {
        didSet {
            scheduleRenderStoreSync([.interaction, .networkDiagnostics])
        }
    }
    @Published var danmakuItems: [DanmakuItem] = []
    @Published var danmakuItemsRevision = 0
    @Published var danmakuState: LoadingState = .idle
    @Published var isDanmakuEnabled = true {
        didSet {
            scheduleRenderStoreSync([.playback, .danmakuSettings, .danmaku])
        }
    }
    @Published var danmakuSettings: DanmakuSettings = .default {
        didSet { scheduleRenderStoreSync([.danmakuSettings, .danmaku]) }
    }
    @Published var detailLoadElapsedMilliseconds: Int? {
        didSet { scheduleRenderStoreSync(.networkDiagnostics) }
    }
    @Published var playURLElapsedMilliseconds: Int? {
        didSet { scheduleRenderStoreSync(.networkDiagnostics) }
    }
    @Published var relatedElapsedMilliseconds: Int? {
        didSet { scheduleRenderStoreSync(.networkDiagnostics) }
    }
    @Published var lastPlayURLSource: String? {
        didSet { scheduleRenderStoreSync(.networkDiagnostics) }
    }
    var currentPlayURLData: PlayURLData?
    @Published var resumeDiagnostics: PlaybackResumeDiagnostics = .none {
        didSet { scheduleRenderStoreSync(.networkDiagnostics) }
    }
    var commentThreadState = VideoDetailCommentThreadState()

    let serviceDependencies: VideoDetailViewModelDependencies
    let playbackOptions: VideoDetailPlaybackOptions
    var coreTaskState = VideoDetailCoreTaskState()
    var relatedTaskState = VideoDetailRelatedTaskState()
    var playbackWarmupTaskState = VideoDetailPlaybackWarmupTaskState()
    var lifecycleSubscriptionState = VideoDetailLifecycleSubscriptionState()
    var sponsorBlockState = VideoDetailSponsorBlockState()
    var danmakuLoadingState = VideoDetailDanmakuLoadingState()
    var stablePlayerState = VideoDetailStablePlayerState()
    var playbackTransitionState = VideoDetailPlaybackTransitionState()
    var playbackStartupWaitState = VideoDetailPlaybackStartupWaitState()
    var playbackRecoveryState = VideoDetailPlaybackRecoveryState()
    var renderStoreSyncState = VideoDetailRenderStoreSyncState()
    var navigationState = VideoDetailPlaybackNavigationState()
    var playVariantSwitchToken: UUID?
    var pendingPlaybackHistoryResumeTime: TimeInterval?
    var pendingPlaybackHistoryResumeCID: Int?
    var didResolveCloudHistoryResume = false
    var isAwaitingInitialManualPlayback = false
    var isAwaitingRelatedVideoReturnPlayback = false
    var manuallySelectedPageCID: Int?
    var uploaderInteractionLoadState = VideoDetailUploaderInteractionLoadState()
    var lastUserSeekAt: Date?
    var loadTiming = VideoDetailViewModelLoadTimingState()
    private var cleanupStablePlaybackBeforeDeinit: (@Sendable () -> Void)?
    let relatedLoadTimeoutNanoseconds: UInt64 = 5_000_000_000

    init(
        seedVideo: VideoItem,
        api: BiliAPIClient,
        libraryStore: LibraryStore,
        sessionStore: SessionStore,
        sponsorBlockService: SponsorBlockService,
        playbackOptions: VideoDetailPlaybackOptions = VideoDetailPlaybackOptions(),
        videoListenPlaybackSessionStore: VideoListenPlaybackSessionStore? = nil
    ) {
        let resolvedVideoListenPlaybackSessionStore = videoListenPlaybackSessionStore
            ?? VideoListenPlaybackSessionStore()
        self.detail = seedVideo
        self.selectedCID = seedVideo.historyCID ?? seedVideo.cid ?? seedVideo.pages?.first?.cid
        self.videoListenQueueSession = VideoListenQueueSession(seedVideo: seedVideo)
        self.videoListenPlaybackSessionStore = resolvedVideoListenPlaybackSessionStore
        self.pendingVideoListenPlaybackSessionState = nil
        self.serviceDependencies = VideoDetailViewModelDependencies(
            api: api,
            libraryStore: libraryStore,
            sessionStore: sessionStore,
            sponsorBlockService: sponsorBlockService
        )
        self.playbackOptions = playbackOptions
        if playbackOptions.resumesPlaybackHistory,
           let resumeTime = seedVideo.historyResumeTime,
           resumeTime > 0.25 {
            pendingPlaybackHistoryResumeTime = resumeTime
            pendingPlaybackHistoryResumeCID = seedVideo.historyCID ?? selectedCID
        }
        self.isDanmakuEnabled = libraryStore.danmakuEnabled
        self.danmakuSettings = libraryStore.danmakuSettings
        self.isAwaitingInitialManualPlayback = !libraryStore.videoDetailAutoplayEnabled
        refreshDetailDisplayMetrics()
        refreshUploaderFanCountText()
        configureLifecycleBindings()
        syncAllRenderStores()
    }

    deinit {
        videoListenQueueTask?.cancel()
        videoListenContentSwitchTask?.cancel()
        videoListenSleepTimerTask?.cancel()
        cleanupStablePlaybackBeforeDeinit?()
        Self.stopPlaybackBeforeDeinit(
            playbackTransitionState: &playbackTransitionState,
            navigationState: &navigationState
        )
        Self.tearDownBeforeDeinit(
            coreTaskState: &coreTaskState,
            playbackWarmupTaskState: &playbackWarmupTaskState,
            playbackRecoveryState: &playbackRecoveryState,
            playbackTransitionState: &playbackTransitionState,
            renderStoreSyncState: &renderStoreSyncState,
            playbackStartupWaitState: &playbackStartupWaitState,
            relatedTaskState: &relatedTaskState,
            uploaderInteractionLoadState: &uploaderInteractionLoadState,
            sponsorBlockState: &sponsorBlockState,
            danmakuLoadingState: &danmakuLoadingState
        )
        Self.cancelMediaWarmupsPreservingCache()
    }

}

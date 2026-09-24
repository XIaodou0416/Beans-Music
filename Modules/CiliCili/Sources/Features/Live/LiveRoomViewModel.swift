import Combine
import Foundation

@MainActor
final class LiveRoomViewModel: ObservableObject {
    @Published private(set) var roomSummary: LiveRoomSummary?
    @Published private(set) var roomInfo: LiveRoomInfo?
    @Published private(set) var anchorInfo: LiveAnchorInfoData?
    @Published var playerViewModel: PlayerStateViewModel? {
        didSet {
            playbackSession.replaceActivePlayer(with: playerViewModel)
        }
    }
    let playbackSession = PlaybackSession()
    @Published var state: LoadingState = .idle
    @Published var streamFallbackMessage: String?
    @Published var streamMenuItems: [LiveStreamMenuItem] = []
    @Published var qualityMenuItems: [LiveStreamQualityMenuItem] = []
    @Published var currentQualityTitle: String?
    @Published var isDanmakuEnabled: Bool
    @Published private(set) var danmakuSettings: DanmakuSettings
    @Published var isLiveDanmakuDiagnosticsEnabled = false
    @Published var isShowingLivePlaybackDiagnostics = false
    @Published var isShowingLiveDanmakuSettings = false
    @Published var isRefreshingLiveEdge = false
    @Published var slowStartupRouteSwitchStatus = "未运行"
    @Published private(set) var isMutatingAnchorFollow = false
    @Published private(set) var interactionMessage: String?

    let seedRoom: LiveRoom
    let liveDanmakuRenderStore: LiveDanmakuRenderStore
    let liveRotationSurfaceAlignmentState = LiveRotationSurfaceAlignmentState()
    let api: BiliAPIClient
    let libraryStore: LibraryStore
    var streamCandidates: [LiveStreamURLCandidate] = []
    var availableQualities: [LiveStreamQuality] = []
    var currentCandidateIndex = 0
    var selectedQualityQN: Int? = LiveStreamQuality.defaultPreferredQN
    private var loadingTask: Task<Void, Never>?
    private var metadataTask: Task<Void, Never>?
    private var metadataFallbackTask: Task<Void, Never>?
    var streamHTTPHeaders: [String: String] = [:]
    var qualitySwitchTask: Task<Void, Never>?
    var liveEdgeRefreshTask: Task<Void, Never>?
    var startupWatchdogTask: Task<Void, Never>?
    var slowStartupRouteSwitchTask: Task<Void, Never>?
    var playbackStallWatchdogTask: Task<Void, Never>?
    var liveDanmakuService: LiveDanmakuService?
    var liveDanmakuClockTask: Task<Void, Never>?
    var liveDanmakuHistoryTask: Task<Void, Never>?
    var liveDanmakuStartDate: Date?
    var liveDanmakuDiagnosticsDraft = LiveDanmakuDiagnosticSnapshot(roomID: 0)
    var liveDanmakuHistoryLoadedRoomID: Int?
    private var cancellables = Set<AnyCancellable>()
    private var loadGeneration = 0

    init(seedRoom: LiveRoom, api: BiliAPIClient, libraryStore: LibraryStore) {
        self.seedRoom = seedRoom
        self.api = api
        self.libraryStore = libraryStore
        self.isDanmakuEnabled = libraryStore.danmakuEnabled
        self.danmakuSettings = libraryStore.danmakuSettings
        self.isLiveDanmakuDiagnosticsEnabled = ProcessInfo.processInfo.arguments.contains(
            "--live-danmaku-diagnostics"
        )
        let initialDiagnostics = LiveDanmakuDiagnosticSnapshot(roomID: seedRoom.roomID)
        self.liveDanmakuDiagnosticsDraft = initialDiagnostics
        self.liveDanmakuRenderStore = LiveDanmakuRenderStore(
            isEnabled: libraryStore.danmakuEnabled,
            settings: libraryStore.danmakuSettings,
            diagnostics: initialDiagnostics
        )
        self.liveDanmakuRenderStore.updateSettings(self.effectiveDanmakuSettings)
        libraryStore.$danmakuEnabled
            .removeDuplicates()
            .sink { [weak self] isEnabled in
                self?.applyGlobalDanmakuEnabled(isEnabled)
            }
            .store(in: &cancellables)
        libraryStore.$danmakuSettings
            .removeDuplicates()
            .sink { [weak self] settings in
                guard let self else { return }
                self.danmakuSettings = settings.normalized
                self.liveDanmakuRenderStore.updateSettings(self.effectiveDanmakuSettings)
            }
            .store(in: &cancellables)
    }

    deinit {
        loadingTask?.cancel()
        metadataTask?.cancel()
        metadataFallbackTask?.cancel()
        qualitySwitchTask?.cancel()
        liveEdgeRefreshTask?.cancel()
        startupWatchdogTask?.cancel()
        slowStartupRouteSwitchTask?.cancel()
        playbackStallWatchdogTask?.cancel()
        liveDanmakuClockTask?.cancel()
        liveDanmakuHistoryTask?.cancel()
        liveDanmakuService?.stop()
    }

    var currentStreamTitle: String? {
        guard streamCandidates.indices.contains(currentCandidateIndex) else { return nil }
        return Self.streamTitle(for: streamCandidates[currentCandidateIndex], index: currentCandidateIndex)
    }

    var currentLoadGeneration: Int {
        loadGeneration
    }

    func startLoading() {
        guard playerViewModel == nil else { return }
        guard loadingTask == nil else { return }
        slowStartupRouteSwitchStatus = "加载中"
        let generation = nextLoadGeneration()
        loadingTask = Task { [weak self] in
            await self?.loadFromNetwork(generation: generation)
        }
    }

    func resumePlaybackAfterCoveredNavigationIfNeeded() {
        if let playerViewModel, !playerViewModel.isTerminated {
            resumeLiveDanmakuIfNeeded()
            return
        }
        playerViewModel = nil
        startLoading()
    }

    func reload() {
        stopCurrentLoadAndPlayback()
        streamCandidates = []
        availableQualities = []
        streamHTTPHeaders = [:]
        currentCandidateIndex = 0
        selectedQualityQN = LiveStreamQuality.defaultPreferredQN
        updateStreamMenuItems()
        updateQualityMenuItems()
        streamFallbackMessage = nil
        state = .idle
        startLoading()
    }

    func stopPlaybackForNavigation() {
        stopCurrentLoadAndPlayback()
        streamCandidates = []
        availableQualities = []
        streamHTTPHeaders = [:]
        currentCandidateIndex = 0
        selectedQualityQN = LiveStreamQuality.defaultPreferredQN
        updateStreamMenuItems()
        updateQualityMenuItems()
        streamFallbackMessage = nil
        if state.isLoading {
            state = .idle
        }
    }

    private func stopCurrentLoadAndPlayback() {
        loadGeneration += 1
        isShowingLivePlaybackDiagnostics = false
        isShowingLiveDanmakuSettings = false
        loadingTask?.cancel()
        metadataTask?.cancel()
        metadataFallbackTask?.cancel()
        qualitySwitchTask?.cancel()
        liveEdgeRefreshTask?.cancel()
        startupWatchdogTask?.cancel()
        slowStartupRouteSwitchTask?.cancel()
        playbackStallWatchdogTask?.cancel()
        loadingTask = nil
        metadataTask = nil
        metadataFallbackTask = nil
        qualitySwitchTask = nil
        liveEdgeRefreshTask = nil
        isRefreshingLiveEdge = false
        startupWatchdogTask = nil
        slowStartupRouteSwitchTask = nil
        playbackStallWatchdogTask = nil
        slowStartupRouteSwitchStatus = "未运行"
        playerViewModel?.onPlaybackFailure = nil
        playerViewModel?.stop()
        playerViewModel = nil
        stopLiveDanmaku(clearItems: true)
    }

    private func nextLoadGeneration() -> Int {
        loadGeneration += 1
        return loadGeneration
    }

    func isCurrentLoad(_ generation: Int) -> Bool {
        generation == loadGeneration
    }

    private func loadFromNetwork(generation: Int) async {
        guard isCurrentLoad(generation), playerViewModel == nil else {
            loadingTask = nil
            return
        }
        state = .loading
        defer {
            if isCurrentLoad(generation) {
                loadingTask = nil
            }
        }
        let api = self.api
        let roomID: Int
        if seedRoom.roomID > 0 {
            roomID = seedRoom.roomID
        } else if let uid = seedRoom.uid, uid > 0 {
            do {
                let summary = try await api.fetchLiveRoomSummary(uid: uid)
                guard !Task.isCancelled, isCurrentLoad(generation) else { return }
                roomSummary = summary
                roomID = summary.roomID
            } catch {
                guard !Task.isCancelled, isCurrentLoad(generation) else { return }
                state = .failed("没有找到这个 UP 的直播间")
                return
            }
        } else {
            state = .failed("这条直播动态缺少直播间信息")
            return
        }

        let resolvedRoomID = roomID
        let metricsID = livePlaybackMetricsID(roomID: resolvedRoomID)
        PlayerMetricsLog.record(.routeOpen, metricsID: metricsID, title: title, message: "source=live")
        PlayerMetricsLog.record(.playURLStart, metricsID: metricsID, title: title, message: "source=liveV2")

        do {
            async let streamResultTask = api.fetchLiveStreamInfo(
                roomID: resolvedRoomID,
                quality: selectedQualityQN
            )
            async let streamHTTPHeadersTask = api.livePlaybackHTTPHeaders(roomID: resolvedRoomID)
            let (streamResult, streamHTTPHeaders) = try await (streamResultTask, streamHTTPHeadersTask)
            guard !Task.isCancelled, isCurrentLoad(generation) else { return }
            let candidates = LiveStreamStartupHealthMemory.shared
                .orderedStartupCandidates(streamResult.candidates)
            guard let firstCandidate = candidates.first else {
                state = .failed("没有获取到可播放的直播流")
                return
            }
            self.streamHTTPHeaders = streamHTTPHeaders
            streamCandidates = candidates
            availableQualities = streamResult.playableQualities
            currentCandidateIndex = Self.preferredCandidateIndex(
                in: candidates,
                preferredQuality: selectedQualityQN,
                preferredSource: nil
            )
            selectedQualityQN = candidates[currentCandidateIndex].currentQN ?? selectedQualityQN
            PlayerMetricsLog.record(
                .startupScheduler,
                metricsID: metricsID,
                title: title,
                message: "liveCDN=adaptive candidateHost=\(candidates[currentCandidateIndex].url.host ?? "-")"
            )
            updateStreamMenuItems()
            updateQualityMenuItems()
            let selectedCandidate = streamCandidates.indices.contains(currentCandidateIndex)
                ? streamCandidates[currentCandidateIndex]
                : firstCandidate
            PlayerMetricsLog.record(
                .playURLLoaded,
                metricsID: metricsID,
                title: title,
                message: "source=liveV2 candidates=\(candidates.count) q=\(selectedCandidate.currentQN ?? 0)"
            )
            installPlayer(for: selectedCandidate, generation: generation)
            if let playerViewModel {
                scheduleRoomMetadataLoad(
                    roomID: resolvedRoomID,
                    playerViewModel: playerViewModel,
                    candidate: selectedCandidate,
                    generation: generation
                )
                scheduleLiveDanmakuStart(
                    roomID: resolvedRoomID,
                    playerViewModel: playerViewModel,
                    candidate: selectedCandidate,
                    generation: generation
                )
            }
            state = .loaded
        } catch {
            guard !Task.isCancelled, isCurrentLoad(generation) else { return }
            if roomInfo?.isLive == false || seedRoom.isLive == false {
                state = .failed("这个直播间当前未开播")
            } else {
                state = .failed("没有获取到可播放的直播流：\(error.localizedDescription)")
            }
        }
    }

    private func scheduleRoomMetadataLoad(
        roomID: Int,
        playerViewModel: PlayerStateViewModel,
        candidate: LiveStreamURLCandidate,
        generation: Int
    ) {
        metadataTask?.cancel()
        metadataTask = nil
        metadataFallbackTask?.cancel()

        let defersForTransportStream = LiveStartupAuxiliaryPolicy.defersUntilFirstFrame(
            streamFormat: candidate.formatName
        )

        let existingFirstFrameHandler = playerViewModel.onFirstFramePresented
        playerViewModel.onFirstFramePresented = { [weak self, weak playerViewModel] in
            existingFirstFrameHandler?()
            guard let self,
                  let playerViewModel,
                  self.isCurrentLoad(generation),
                  self.playerViewModel === playerViewModel
            else { return }
            guard defersForTransportStream else { return }
            self.startRoomMetadataLoad(roomID: roomID, generation: generation)
        }

        if defersForTransportStream {
            PlayerMetricsLog.record(
                .startupScheduler,
                metricsID: livePlaybackMetricsID(roomID: roomID),
                title: title,
                message: "liveAuxiliary=deferredTSUntilFirstFrame"
            )
            if playerViewModel.hasPresentedPlayback {
                startRoomMetadataLoad(roomID: roomID, generation: generation)
            }
            return
        }

        let metricsID = livePlaybackMetricsID(roomID: roomID)
        PlayerMetricsLog.record(
            .startupScheduler,
            metricsID: metricsID,
            title: title,
            message: "liveAuxiliary=parallel metadataDelay=180ms"
        )
        metadataFallbackTask = Task { [weak self, weak playerViewModel] in
            try? await Task.sleep(
                nanoseconds: LivePlaybackPolicy.auxiliaryLoadDelayNanoseconds
            )
            guard !Task.isCancelled,
                  let self,
                  let playerViewModel,
                  self.isCurrentLoad(generation),
                  self.playerViewModel === playerViewModel
            else { return }
            self.startRoomMetadataLoad(roomID: roomID, generation: generation)
        }
    }

    private func startRoomMetadataLoad(roomID: Int, generation: Int) {
        guard isCurrentLoad(generation), metadataTask == nil else { return }
        metadataFallbackTask?.cancel()
        metadataFallbackTask = nil
        metadataTask = Task { [weak self] in
            await self?.loadRoomMetadata(roomID: roomID, generation: generation)
            guard let self, self.isCurrentLoad(generation) else { return }
            self.metadataTask = nil
        }
    }

    private func livePlaybackMetricsID(roomID: Int) -> String {
        "live-\(roomID)"
    }

    func toggleFollowAnchor() async {
        guard !isMutatingAnchorFollow else { return }
        guard let uid = anchorUIDForFollow else {
            interactionMessage = "没有找到主播 UID，无法关注"
            return
        }

        isMutatingAnchorFollow = true
        interactionMessage = nil
        let targetState = !isFollowingAnchor
        do {
            try await api.setUploaderFollowing(mid: uid, following: targetState)
            let roomID = self.roomID
            if roomID > 0 {
                anchorInfo = try? await api.fetchLiveAnchorInfo(roomID: roomID)
            }
            interactionMessage = targetState ? "已关注主播" : "已取消关注"
        } catch {
            interactionMessage = "关注操作失败：\(error.localizedDescription)"
        }
        isMutatingAnchorFollow = false
    }

    private func loadRoomMetadata(roomID: Int, generation: Int) async {
        let api = self.api
        async let roomInfoTask: LiveRoomInfo? = optionalFetch { try await api.fetchLiveRoomInfo(roomID: roomID) }
        async let anchorInfoTask: LiveAnchorInfoData? = optionalFetch { try await api.fetchLiveAnchorInfo(roomID: roomID) }

        let loadedRoomInfo = await roomInfoTask
        let loadedAnchorInfo = await anchorInfoTask
        guard !Task.isCancelled, isCurrentLoad(generation) else { return }
        roomInfo = loadedRoomInfo
        anchorInfo = loadedAnchorInfo
    }

    private func optionalFetch<T>(_ operation: @escaping () async throws -> T) async -> T? {
        do {
            return try await operation()
        } catch {
            return nil
        }
    }

}

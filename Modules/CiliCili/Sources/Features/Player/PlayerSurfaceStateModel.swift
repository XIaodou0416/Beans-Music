import Combine
import Foundation

struct PlayerSurfaceSnapshot: Equatable {
    var isPlaying = false
    var canSeek = false
    var duration: TimeInterval?
    var playbackRate: BiliPlaybackRate = .x10
    var isPreparing = true
    var isBuffering = false
    var isUserSeeking = false
    var loadingProgress = 0.08
    var errorMessage: String?
    var hasPresentedPlayback = false
    var isCurrentPlaybackSurfaceReady = false
    var isPictureInPictureSupported = false
    var isPictureInPictureActive = false
    var usesNativePlaybackControls = false
    var showsExplicitPlaybackStartControl = false

    @MainActor
    init(viewModel: PlayerStateViewModel? = nil) {
        guard let viewModel else { return }
        isPlaying = viewModel.isPlaying
        canSeek = viewModel.canSeek
        duration = viewModel.duration
        playbackRate = viewModel.playbackRate
        isPreparing = viewModel.isPreparing
        isBuffering = viewModel.isBuffering
        isUserSeeking = viewModel.isUserSeeking
        loadingProgress = viewModel.loadingProgress
        errorMessage = viewModel.errorMessage
        hasPresentedPlayback = viewModel.hasPresentedPlayback
        isCurrentPlaybackSurfaceReady = viewModel.isCurrentPlaybackSurfaceReadyForDisplay
        isPictureInPictureSupported = viewModel.isPictureInPictureSupported
        isPictureInPictureActive = viewModel.isPictureInPictureActive
        usesNativePlaybackControls = viewModel.usesNativePlaybackControls
        showsExplicitPlaybackStartControl = viewModel.showsExplicitPlaybackStartControl
    }
}

@MainActor
final class PlayerSurfaceStateModel: ObservableObject {
    @Published private(set) var snapshot: PlayerSurfaceSnapshot

    private weak var viewModel: PlayerStateViewModel?
    private var cancellables = Set<AnyCancellable>()
    private var snapshotRefreshTask: Task<Void, Never>?
    private var snapshotRefreshGeneration = 0

    init(viewModel: PlayerStateViewModel? = nil) {
        snapshot = PlayerSurfaceSnapshot(viewModel: viewModel)
    }

    var isPlaying: Bool { snapshot.isPlaying }
    var canSeek: Bool { snapshot.canSeek }
    var duration: TimeInterval? { snapshot.duration }
    var playbackRate: BiliPlaybackRate { snapshot.playbackRate }
    var isPreparing: Bool { snapshot.isPreparing }
    var isBuffering: Bool { snapshot.isBuffering }
    var isUserSeeking: Bool { snapshot.isUserSeeking }
    var loadingProgress: Double { snapshot.loadingProgress }
    var errorMessage: String? { snapshot.errorMessage }
    var hasPresentedPlayback: Bool { snapshot.hasPresentedPlayback }
    var isCurrentPlaybackSurfaceReady: Bool { snapshot.isCurrentPlaybackSurfaceReady }
    var isPictureInPictureSupported: Bool { snapshot.isPictureInPictureSupported }
    var isPictureInPictureActive: Bool { snapshot.isPictureInPictureActive }
    var usesNativePlaybackControls: Bool { snapshot.usesNativePlaybackControls }
    var showsExplicitPlaybackStartControl: Bool { snapshot.showsExplicitPlaybackStartControl }

    func bind(viewModel: PlayerStateViewModel) {
        guard self.viewModel !== viewModel else {
            refreshSnapshot(from: viewModel)
            return
        }
        cancelSnapshotRefreshTask()
        cancellables.removeAll()
        self.viewModel = viewModel
        refreshSnapshot(from: viewModel)

        let refresh: () -> Void = { [weak self] in
            self?.scheduleSnapshotRefresh()
        }

        viewModel.$isPlaying
            .removeDuplicates()
            .sink { _ in refresh() }
            .store(in: &cancellables)

        viewModel.$isSeekable
            .removeDuplicates()
            .sink { _ in refresh() }
            .store(in: &cancellables)

        viewModel.$duration
            .removeDuplicates()
            .sink { _ in refresh() }
            .store(in: &cancellables)

        viewModel.$isAwaitingInitialManualPlayback
            .removeDuplicates()
            .sink { _ in refresh() }
            .store(in: &cancellables)

        viewModel.$isAwaitingRelatedVideoReturnPlayback
            .removeDuplicates()
            .sink { _ in refresh() }
            .store(in: &cancellables)

        viewModel.$playbackRate
            .removeDuplicates()
            .sink { _ in refresh() }
            .store(in: &cancellables)

        viewModel.$isPreparing
            .removeDuplicates()
            .sink { _ in refresh() }
            .store(in: &cancellables)

        viewModel.$isBuffering
            .removeDuplicates()
            .sink { _ in refresh() }
            .store(in: &cancellables)

        viewModel.$isUserSeeking
            .removeDuplicates()
            .sink { _ in refresh() }
            .store(in: &cancellables)

        viewModel.$loadingProgress
            .removeDuplicates { abs($0 - $1) < 0.01 }
            .sink { _ in refresh() }
            .store(in: &cancellables)

        viewModel.$errorMessage
            .removeDuplicates()
            .sink { _ in refresh() }
            .store(in: &cancellables)

        viewModel.$hasPresentedPlayback
            .removeDuplicates()
            .sink { _ in refresh() }
            .store(in: &cancellables)

        viewModel.$isCurrentPlaybackSurfaceReadyForDisplay
            .removeDuplicates()
            .sink { _ in refresh() }
            .store(in: &cancellables)

        viewModel.$isPictureInPictureActive
            .removeDuplicates()
            .sink { _ in refresh() }
            .store(in: &cancellables)

        viewModel.$isPictureInPictureEnabled
            .removeDuplicates()
            .sink { _ in refresh() }
            .store(in: &cancellables)

        viewModel.$engineDiagnostics
            .removeDuplicates()
            .sink { _ in refresh() }
            .store(in: &cancellables)
    }

    private func scheduleSnapshotRefresh() {
        guard snapshotRefreshTask == nil else { return }
        let generation = advanceSnapshotRefreshGeneration()
        snapshotRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 16_000_000)
            guard let self,
                  !Task.isCancelled,
                  self.snapshotRefreshGeneration == generation
            else { return }
            self.snapshotRefreshTask = nil
            guard let viewModel = self.viewModel else { return }
            self.refreshSnapshot(from: viewModel)
        }
    }

    private func refreshSnapshot(from viewModel: PlayerStateViewModel) {
        let nextSnapshot = PlayerSurfaceSnapshot(viewModel: viewModel)
        guard snapshot != nextSnapshot else { return }
        snapshot = nextSnapshot
    }

    @discardableResult
    private func advanceSnapshotRefreshGeneration() -> Int {
        snapshotRefreshGeneration += 1
        return snapshotRefreshGeneration
    }

    private func cancelSnapshotRefreshTask() {
        snapshotRefreshTask?.cancel()
        snapshotRefreshTask = nil
        advanceSnapshotRefreshGeneration()
    }

    deinit {
        snapshotRefreshTask?.cancel()
    }
}

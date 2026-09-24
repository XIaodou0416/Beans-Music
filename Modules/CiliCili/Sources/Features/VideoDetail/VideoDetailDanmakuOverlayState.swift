import Combine
import Foundation

@MainActor
final class VideoDetailDanmakuOverlayState: ObservableObject {
    @Published private(set) var snapshot = VideoDetailDanmakuOverlaySnapshot()

    private weak var store: VideoDetailDanmakuRenderStore?
    private weak var playerViewModel: PlayerStateViewModel?
    var cancellables = Set<AnyCancellable>()
    var allItems: [DanmakuItem] = []
    var sourceItemsRevision = 0
    var publishedSourceItemsRevision = -1
    var publishedWindowRange: Range<Int> = 0..<0
    var lastWindowCenterBucket: Int?
    let normalWindowLookBehind: TimeInterval = 12
    let normalWindowLookAhead: TimeInterval = 32
    let windowRecenterInterval: TimeInterval = 8

    func bind(store: VideoDetailDanmakuRenderStore, playerViewModel: PlayerStateViewModel) {
        guard !playerViewModel.isTerminated else {
            unbind()
            return
        }
        guard self.store !== store || self.playerViewModel !== playerViewModel else { return }
        cancellables.removeAll()
        self.store = store
        self.playerViewModel = playerViewModel

        let renderSnapshot = store.snapshot
        allItems = renderSnapshot.items
        sourceItemsRevision = renderSnapshot.itemsRevision
        publishedSourceItemsRevision = -1
        publishedWindowRange = 0..<0
        lastWindowCenterBucket = nil
        updateWindow(around: playerViewModel.playbackClock.currentTime, force: true)
        refreshSnapshot(renderSnapshot: renderSnapshot, playerViewModel: playerViewModel)

        bindRenderStoreUpdates(store: store, playerViewModel: playerViewModel)
        bindPlaybackClock(playerViewModel: playerViewModel)
        bindPlaybackFlags(playerViewModel: playerViewModel)
        bindLoadSheddingState(playerViewModel: playerViewModel)
    }

    func unbind() {
        cancellables.removeAll()
        store = nil
        playerViewModel = nil
        allItems = []
        sourceItemsRevision = 0
        publishedSourceItemsRevision = -1
        publishedWindowRange = 0..<0
        lastWindowCenterBucket = nil
        updateSnapshot {
            $0.items = []
            $0.itemsRevision &+= 1
            $0.isPlaying = false
            $0.hasPresentedPlayback = false
            $0.isLoadShedding = false
        }
    }

    func updateSnapshot(_ transform: (inout VideoDetailDanmakuOverlaySnapshot) -> Void) {
        var next = snapshot
        transform(&next)
        guard next != snapshot else { return }
        snapshot = next
    }

    static func canRenderDanmaku(for playerViewModel: PlayerStateViewModel) -> Bool {
        playerViewModel.hasPresentedPlayback
            && playerViewModel.isCurrentPlaybackSurfaceReadyForDisplay
    }
}

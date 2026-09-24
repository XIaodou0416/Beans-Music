import Combine
import Foundation

@MainActor
final class VideoDetailPlaybackRenderStore: ObservableObject {
    @Published private var snapshot = VideoDetailPlaybackRenderSnapshot()
    private var deferredSnapshot = VideoDetailDeferredValue<VideoDetailPlaybackRenderSnapshot>()
    let qualityControlStore = VideoDetailQualityControlRenderStore()
    let placeholderStore = VideoDetailPlayerPlaceholderRenderStore()
    let pageSelectorStore = VideoDetailPageSelectorRenderStore()

    var historyVideo: VideoItem? { snapshot.historyVideo }
    var historyCID: Int? { snapshot.historyCID }
    var duration: TimeInterval? { snapshot.duration }
    var playURLState: LoadingState { snapshot.playURLState }
    var selectedPlayVariant: PlayVariant? { snapshot.selectedPlayVariant }
    var isDanmakuEnabled: Bool { snapshot.isDanmakuEnabled }
    var qualityInlineButtonTitle: String { snapshot.qualityInlineButtonTitle }
    var qualityAccessoryButtonTitle: String { snapshot.qualityAccessoryButtonTitle }
    var qualityButtonSystemImage: String { snapshot.qualityButtonSystemImage }
    var qualityMenuItems: [VideoDetailPlaybackQualityMenuItem] { snapshot.qualityMenuItems }
    var isSwitchingPlayQuality: Bool { snapshot.isSwitchingPlayQuality }
    var hasQualityMenu: Bool { !snapshot.qualityMenuItems.isEmpty }

    func update(_ next: VideoDetailPlaybackRenderSnapshot) {
        guard let next = deferredSnapshot.submit(next, current: snapshot, isEquivalent: ==) else {
            return
        }
        setSnapshot(next)
    }

    func setUpdatesDeferred(_ deferred: Bool) {
        guard let next = deferredSnapshot.setDeferred(deferred) else { return }
        setSnapshot(next)
    }

    private func setSnapshot(_ next: VideoDetailPlaybackRenderSnapshot) {
        guard next != snapshot else { return }
        snapshot = next
        derivedStoreDispatcher.updateStores(with: next)
    }

    private var derivedStoreDispatcher: VideoDetailPlaybackDerivedStoreDispatcher {
        VideoDetailPlaybackDerivedStoreDispatcher(
            qualityControlStore: qualityControlStore,
            placeholderStore: placeholderStore,
            pageSelectorStore: pageSelectorStore
        )
    }
}

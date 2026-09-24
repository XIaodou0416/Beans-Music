import Combine
import Foundation

@MainActor
final class VideoDetailPageSelectorRenderStore: ObservableObject {
    @Published private var snapshot = VideoDetailPageSelectorRenderSnapshot()
    private var deferredSnapshot = VideoDetailDeferredValue<VideoDetailPageSelectorRenderSnapshot>()

    var pages: [VideoPage] { snapshot.pages }
    var selectedCID: Int? { snapshot.selectedCID }
    var pageCountText: String { snapshot.pageCountText }
    var shouldShowPageSelector: Bool { snapshot.shouldShowPageSelector }

    func update(_ next: VideoDetailPageSelectorRenderSnapshot) {
        guard let next = deferredSnapshot.submit(next, current: snapshot, isEquivalent: ==) else {
            return
        }
        snapshot = next
    }

    func setUpdatesDeferred(_ deferred: Bool) {
        guard let pending = deferredSnapshot.setDeferred(deferred), pending != snapshot else { return }
        snapshot = pending
    }
}

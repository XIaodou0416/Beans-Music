import Combine
import Foundation

@MainActor
final class VideoDetailDescriptionRenderStore: ObservableObject {
    @Published private var snapshot = VideoDetailDescriptionRenderSnapshot()
    private var deferredSnapshot = VideoDetailDeferredValue<VideoDetailDescriptionRenderSnapshot>()

    var titleText: String { snapshot.titleText }
    var owner: VideoOwner? { snapshot.owner }
    var viewCountText: String { snapshot.viewCountText }
    var fanCountText: String { snapshot.fanCountText }
    var publishDateText: String { snapshot.publishDateText }
    var publishDateSubtitleText: String? { snapshot.publishDateSubtitleText }
    var descriptionText: String { snapshot.descriptionText }
    var hasResolvedDetailMetadata: Bool { snapshot.hasResolvedDetailMetadata }
    var canFavorite: Bool { snapshot.canFavorite }
    var shareURL: URL? { snapshot.shareURL }
    var shareSubject: String { snapshot.shareSubject }
    var shareMessage: String { snapshot.shareMessage }
    var isFollowing: Bool { snapshot.isFollowing }
    var isMutatingInteraction: Bool { snapshot.isMutatingInteraction }

    func update(_ next: VideoDetailDescriptionRenderSnapshot) {
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

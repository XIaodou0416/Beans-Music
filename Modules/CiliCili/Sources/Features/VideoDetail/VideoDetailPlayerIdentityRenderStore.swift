import Combine
import Foundation

@MainActor
final class VideoDetailPlayerIdentityRenderStore: ObservableObject {
    @Published private var snapshot = VideoDetailPlayerIdentityRenderSnapshot()

    var playerViewModel: PlayerStateViewModel? { snapshot.playerViewModel }
    var transitionSnapshot: PlaybackTransitionSnapshot? { snapshot.transitionSnapshot }
    var transitionFallbackCoverURL: URL? { snapshot.transitionFallbackCoverURL }
    var transitionPlayerOpacity: Double { snapshot.transitionPlayerOpacity }
    private(set) var revision = 0

    func update(_ next: VideoDetailPlayerIdentityRenderSnapshot) {
        guard next != snapshot else { return }
        snapshot = next
        revision &+= 1
    }
}

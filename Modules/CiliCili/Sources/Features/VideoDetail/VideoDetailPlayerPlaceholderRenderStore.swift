import Combine
import Foundation

@MainActor
final class VideoDetailPlayerPlaceholderRenderStore: ObservableObject {
    @Published private var snapshot = VideoDetailPlayerPlaceholderRenderSnapshot()

    var playURLState: LoadingState { snapshot.playURLState }
    var selectedPlayVariant: PlayVariant? { snapshot.selectedPlayVariant }
    var isDetailLoading: Bool { snapshot.isDetailLoading }
    var isDetailLoaded: Bool { snapshot.isDetailLoaded }
    var failedMessage: String? { snapshot.failedMessage }

    func update(_ next: VideoDetailPlayerPlaceholderRenderSnapshot) {
        guard next != snapshot else { return }
        snapshot = next
    }
}

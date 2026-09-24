import Combine
import Foundation

@MainActor
final class VideoDetailFavoriteFolderRenderStore: ObservableObject {
    @Published private var snapshot = VideoDetailFavoriteFolderRenderSnapshot()

    var favoriteFolders: [FavoriteFolder] { snapshot.favoriteFolders }
    var favoriteFolderState: LoadingState { snapshot.favoriteFolderState }
    var isMutatingInteraction: Bool { snapshot.isMutatingInteraction }

    func update(_ next: VideoDetailFavoriteFolderRenderSnapshot) {
        guard next != snapshot else { return }
        snapshot = next
    }
}

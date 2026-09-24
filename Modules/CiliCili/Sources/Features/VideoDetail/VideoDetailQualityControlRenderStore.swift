import Combine
import Foundation

@MainActor
final class VideoDetailQualityControlRenderStore: ObservableObject {
    @Published private var snapshot = VideoDetailQualityControlRenderSnapshot()

    var qualityInlineButtonTitle: String { snapshot.qualityInlineButtonTitle }
    var qualityAccessoryButtonTitle: String { snapshot.qualityAccessoryButtonTitle }
    var qualityButtonSystemImage: String { snapshot.qualityButtonSystemImage }
    var qualityMenuItems: [VideoDetailPlaybackQualityMenuItem] { snapshot.qualityMenuItems }
    var isSwitchingPlayQuality: Bool { snapshot.isSwitchingPlayQuality }
    var hasQualityMenu: Bool { !snapshot.qualityMenuItems.isEmpty }

    func update(_ next: VideoDetailQualityControlRenderSnapshot) {
        guard next != snapshot else { return }
        snapshot = next
    }
}

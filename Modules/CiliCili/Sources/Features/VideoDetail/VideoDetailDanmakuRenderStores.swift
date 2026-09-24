import Combine
import Foundation

@MainActor
final class VideoDetailDanmakuSettingsRenderStore: ObservableObject {
    @Published private var snapshot = VideoDetailDanmakuSettingsRenderSnapshot()

    var isDanmakuEnabled: Bool { snapshot.isDanmakuEnabled }
    var danmakuSettings: DanmakuSettings { snapshot.danmakuSettings }

    func update(_ next: VideoDetailDanmakuSettingsRenderSnapshot) {
        guard next != snapshot else { return }
        snapshot = next
    }
}

@MainActor
final class VideoDetailDanmakuRenderStore: ObservableObject {
    @Published private(set) var snapshot = VideoDetailDanmakuRenderSnapshot()

    var items: [DanmakuItem] { snapshot.items }
    var itemsRevision: Int { snapshot.itemsRevision }
    var isDanmakuEnabled: Bool { snapshot.isDanmakuEnabled }
    var effectiveSettings: DanmakuSettings { snapshot.effectiveSettings }

    func update(_ next: VideoDetailDanmakuRenderSnapshot) {
        guard next != snapshot else { return }
        snapshot = next
    }
}

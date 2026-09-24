import Combine
import Foundation

@MainActor
final class VideoDetailNetworkDiagnosticsRenderStore: ObservableObject {
    @Published private var snapshot = VideoDetailNetworkDiagnosticsRenderSnapshot()

    var videoTitle: String { snapshot.videoTitle }
    var metricsID: String { snapshot.metricsID }
    var selectedPlayVariant: PlayVariant? { snapshot.selectedPlayVariant }
    var playerViewModel: PlayerStateViewModel? { snapshot.playerViewModel }
    var detailLoadElapsedMilliseconds: Int? { snapshot.detailLoadElapsedMilliseconds }
    var playURLElapsedMilliseconds: Int? { snapshot.playURLElapsedMilliseconds }
    var relatedElapsedMilliseconds: Int? { snapshot.relatedElapsedMilliseconds }
    var lastPlayURLSource: String? { snapshot.lastPlayURLSource }
    var resumeDiagnostics: PlaybackResumeDiagnostics { snapshot.resumeDiagnostics }
    var playbackFallbackMessage: String? { snapshot.playbackFallbackMessage }

    func update(_ next: VideoDetailNetworkDiagnosticsRenderSnapshot) {
        guard next != snapshot else { return }
        snapshot = next
    }
}

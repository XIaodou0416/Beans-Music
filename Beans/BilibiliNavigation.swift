import SwiftUI
import CiliCiliKit

@MainActor
final class BilibiliPresentationState: ObservableObject {
    static let shared = BilibiliPresentationState()
    @Published private(set) var activeVideoIDs = Set<String>()

    func enterVideo(_ id: String) {
        guard !activeVideoIDs.contains(id) else { return }
        activeVideoIDs.insert(id)
    }

    func leaveVideo(_ id: String) {
        guard activeVideoIDs.contains(id) else { return }
        activeVideoIDs.remove(id)
    }

    var isVideoDetailActive: Bool { !activeVideoIDs.isEmpty }
}

/// Compatibility at Beans' music boundaries, never an alternative video UI.
struct BilibiliNativeStandaloneStack: View {
    let initialRoute: BilibiliNativeRoute

    var body: some View {
        if let route = initialRoute.ciliCiliRoute {
            CiliCiliRouteHost(route: route)
        } else if case .playlist(let playlist) = initialRoute {
            BeansNavigationStack { PlaylistView(playlist: playlist) }
        }
    }
}


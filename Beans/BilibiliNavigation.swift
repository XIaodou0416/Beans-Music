import SwiftUI
import CiliCiliKit

@MainActor
final class BilibiliNavigationState: ObservableObject {
    @Published var path: [BilibiliNativeRoute] = []

    func push(_ route: BilibiliNativeRoute) {
        path.append(route)
    }

    func pop(to depth: Int) {
        guard path.count > depth else { return }
        path.removeLast(path.count - depth)
    }
}

private struct BilibiliNavigationActionKey: EnvironmentKey {
    static let defaultValue: ((BilibiliNativeRoute) -> Void)? = nil
}

extension EnvironmentValues {
    var bilibiliNavigate: ((BilibiliNativeRoute) -> Void)? {
        get { self[BilibiliNavigationActionKey.self] }
        set { self[BilibiliNavigationActionKey.self] = newValue }
    }
}

@MainActor
final class BilibiliPresentationState: ObservableObject {
    static let shared = BilibiliPresentationState()
    @Published private(set) var activeVideoIDs = Set<String>()
    @Published private(set) var activeLiveIDs = Set<String>()

    func enterVideo(_ id: String) {
        guard !activeVideoIDs.contains(id) else { return }
        activeVideoIDs.insert(id)
    }

    func leaveVideo(_ id: String) {
        guard activeVideoIDs.contains(id) else { return }
        activeVideoIDs.remove(id)
    }

    var isVideoDetailActive: Bool { !activeVideoIDs.isEmpty }

    func enterLive(_ id: String) { activeLiveIDs.insert(id) }
    func leaveLive(_ id: String) { activeLiveIDs.remove(id) }
    var shouldHideBeansChrome: Bool { isVideoDetailActive || !activeLiveIDs.isEmpty }
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

struct BilibiliAccountShortcutButton: View {
    @ObservedObject private var auth = BilibiliAuth.shared
    let action: () -> Void

    var body: some View {
        Button {
            BeansHaptics.tap()
            action()
        } label: {
            BeansAvatarView(remoteURL: auth.avatarURL, size: 32)
                .overlay { Circle().strokeBorder(Color.white.opacity(0.28), lineWidth: 0.8) }
                .frame(width: 38, height: 38)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("哔哩哔哩我的")
    }
}


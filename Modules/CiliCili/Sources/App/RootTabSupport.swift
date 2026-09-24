import Combine
import SwiftUI
import UIKit

@MainActor
final class RootHomeViewModelHolder: ObservableObject {
    @Published var viewModel: HomeViewModel?

    func configure(
        api: BiliAPIClient,
        libraryStore: LibraryStore,
        sessionStore: SessionStore,
        initialMode: HomeFeedMode
    ) {
        if viewModel == nil {
            let viewModel = HomeViewModel(
                api: api,
                libraryStore: libraryStore,
                sessionStore: sessionStore,
                initialMode: initialMode
            )
            self.viewModel = viewModel
        }
    }
}

extension View {
    func videoDestinations() -> some View {
        navigationDestination(for: VideoItem.self) { video in
            VideoDetailView(
                seedVideo: video
            )
        }
        .navigationDestination(for: VideoCommentRoute.self) { route in
            VideoDetailView(
                seedVideo: route.video,
                initialCommentAnchor: route.anchor
            )
        }
        .navigationDestination(for: PgcSeasonRoute.self) { route in
            PgcSeasonPlaybackRouteView(route: route)
        }
        .navigationDestination(for: VideoOwner.self) { owner in
            UploaderView(owner: owner)
        }
        .navigationDestination(for: LiveRoom.self) { room in
            LiveRoomDetailView(seedRoom: room)
        }
    }
}

struct RootTabBarAppearanceInstaller: UIViewControllerRepresentable {
    let tintColorHex: String
    let glassStyle: VideoDetailSegmentedPickerGlassStyle

    func makeUIViewController(context _: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context _: Context) {
        controller.tintColorHex = tintColorHex
        controller.selectedColor = AppThemeTintColor.uiColor(for: tintColorHex)
        controller.glassStyle = glassStyle
        controller.applySoon()
    }

    final class Controller: UIViewController {
        var selectedColor = AppThemeTintColor.uiColor(for: AppThemeTintColor.defaultHex)
        var tintColorHex = AppThemeTintColor.defaultHex
        var glassStyle: VideoDetailSegmentedPickerGlassStyle = .clear
        private weak var appliedTabBar: UITabBar?
        private var appliedTintColorHex: String?
        private var appliedGlassStyle: VideoDetailSegmentedPickerGlassStyle?
        private var appliedInterfaceStyle: UIUserInterfaceStyle?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            applyAppearance(force: true)
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            applyAppearance()
        }

        func applySoon() {
            DispatchQueue.main.async { [weak self] in
                self?.applyAppearance()
            }
        }

        private func applyAppearance(force: Bool = false) {
            guard let tabBar = tabBarController?.tabBar ?? enclosingTabBarController()?.tabBar else { return }
            let interfaceStyle = tabBar.traitCollection.userInterfaceStyle
            guard force
                || appliedTabBar !== tabBar
                || appliedTintColorHex != tintColorHex
                || appliedGlassStyle != glassStyle
                || appliedInterfaceStyle != interfaceStyle else {
                return
            }

            let appearance = UITabBarAppearance()
            appearance.configureWithTransparentBackground()
            switch glassStyle {
            case .clear:
                appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
            case .regular:
                appearance.backgroundEffect = UIBlurEffect(style: .systemMaterial)
            }
            appearance.backgroundColor = .clear
            appearance.shadowColor = UIColor.label.withAlphaComponent(0.04)

            let normalColor = UIColor.secondaryLabel.withAlphaComponent(0.82)
            configure(appearance.stackedLayoutAppearance, normalColor: normalColor, selectedColor: selectedColor)
            configure(appearance.inlineLayoutAppearance, normalColor: normalColor, selectedColor: selectedColor)
            configure(appearance.compactInlineLayoutAppearance, normalColor: normalColor, selectedColor: selectedColor)

            tabBar.standardAppearance = appearance
            tabBar.scrollEdgeAppearance = appearance
            tabBar.tintColor = selectedColor
            tabBar.unselectedItemTintColor = normalColor
            tabBar.isTranslucent = true
            tabBar.backgroundColor = .clear
            tabBar.layer.shadowColor = UIColor.black.cgColor
            tabBar.layer.shadowOpacity = interfaceStyle == .dark ? 0.14 : 0.05
            tabBar.layer.shadowRadius = 14
            tabBar.layer.shadowOffset = CGSize(width: 0, height: -2)

            appliedTabBar = tabBar
            appliedTintColorHex = tintColorHex
            appliedGlassStyle = glassStyle
            appliedInterfaceStyle = interfaceStyle
        }

        private func configure(
            _ itemAppearance: UITabBarItemAppearance,
            normalColor: UIColor,
            selectedColor: UIColor
        ) {
            itemAppearance.normal.iconColor = normalColor
            itemAppearance.normal.titleTextAttributes = [
                .foregroundColor: normalColor,
                .font: UIFont.systemFont(ofSize: 11.5, weight: .semibold)
            ]
            itemAppearance.selected.iconColor = selectedColor
            itemAppearance.selected.titleTextAttributes = [
                .foregroundColor: selectedColor,
                .font: UIFont.systemFont(ofSize: 11.5, weight: .bold)
            ]
        }

        private func enclosingTabBarController() -> UITabBarController? {
            var responder: UIResponder? = view
            while let current = responder {
                if let tabBarController = current as? UITabBarController {
                    return tabBarController
                }
                responder = current.next
            }
            return nil
        }
    }
}

enum RootTab: String, Hashable {
    case home
    case search
    case dynamic
    case live
    case mine

    init?(argumentValue: String) {
        guard let tab = RootTab(rawValue: argumentValue.lowercased()) else {
            return nil
        }
        self = tab
    }

    var appTab: AppTab {
        switch self {
        case .home:
            return .home
        case .search:
            return .search
        case .dynamic:
            return .dynamic
        case .live:
            return .live
        case .mine:
            return .mine
        }
    }

    var title: String {
        appTab.title
    }

    var systemImage: String {
        appTab.systemImage
    }
}

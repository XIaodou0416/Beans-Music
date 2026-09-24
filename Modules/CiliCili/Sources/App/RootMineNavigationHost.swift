import SwiftUI

struct RootMineNavigationDestination: View {
    let route: MineOverlayRoute
    @ObservedObject var holder: MineViewModelHolder
    @ObservedObject var libraryStore: LibraryStore
    @ObservedObject var sessionStore: SessionStore
    let api: BiliAPIClient

    var body: some View {
        Group {
            if route.isSettingsRoute {
                destinationContent
                    .labelStyle(.titleOnly)
            } else {
                destinationContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .background(
            VideoDetailSystemBackGestureBridge(
                onNavigationGestureBegan: {},
                allowsSingleControllerNavigation: true
            )
        )
    }

    @ViewBuilder
    private var destinationContent: some View {
        switch route {
        case .accountMessages:
            if let viewModel = holder.accountMessageViewModel {
                AccountMessageCenterView(viewModel: viewModel)
            } else {
                ProgressView()
            }
        case .multiAccountSettings:
            MultiAccountExperimentSettingsView(
                sessionStore: sessionStore,
                libraryStore: libraryStore,
                api: api
            )
        case .history:
            accountLibraryPage(kind: .history)
        case .favorites:
            accountLibraryPage(kind: .favorites)
        case .watchLater:
            accountLibraryPage(kind: .watchLater)
        case .interfaceSettings:
            MineInterfaceSettingsView(libraryStore: libraryStore)
        case .homeAndSearchSettings:
            MineHomeAndSearchSettingsView(libraryStore: libraryStore)
        case .playbackSettings:
            MinePlaybackSettingsView(libraryStore: libraryStore)
        case .contentFilterSettings:
            MineContentFilterSettingsView(libraryStore: libraryStore)
        case .privacySettings:
            MinePrivacySettingsView(libraryStore: libraryStore)
        }
    }

    @ViewBuilder
    private func accountLibraryPage(kind: AccountLibraryKind) -> some View {
        if let viewModel = holder.viewModel {
            AccountLibraryListPage(kind: kind, viewModel: viewModel)
        } else {
            ProgressView()
        }
    }
}

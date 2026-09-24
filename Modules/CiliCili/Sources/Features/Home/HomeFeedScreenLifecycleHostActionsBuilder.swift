import SwiftUI

@MainActor
struct HomeFeedScreenLifecycleHostActionsBuilder {
    let viewModel: HomeViewModel
    let runtimeSettings: HomeRuntimeSettingsStore
    let libraryStore: LibraryStore
    let detailPath: Binding<NavigationPath>
    let configuration: HomeFeedScreenLifecycleConfiguration

    var actions: HomeFeedScreenLifecycleHostActions {
        HomeFeedScreenLifecycleHostActions(
            viewModel: viewModel,
            runtimeSettings: runtimeSettings,
            libraryStore: libraryStore,
            detailPath: detailPath,
            configuration: configuration
        )
    }
}

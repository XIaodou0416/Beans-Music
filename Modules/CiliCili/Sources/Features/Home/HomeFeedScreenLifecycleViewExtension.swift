import SwiftUI

extension View {
    func homeFeedScreenLifecycle(
        viewModel: HomeViewModel,
        runtimeSettings: HomeRuntimeSettingsStore,
        libraryStore: LibraryStore,
        detailPath: Binding<NavigationPath>,
        configuration: HomeFeedScreenLifecycleConfiguration
    ) -> some View {
        modifier(
            HomeFeedScreenLifecycleModifier(
                viewModel: viewModel,
                lifecycleActions: HomeFeedScreenLifecycleModifierActions(
                    actions: HomeFeedScreenLifecycleHostActionsBuilder(
                        viewModel: viewModel,
                        runtimeSettings: runtimeSettings,
                        libraryStore: libraryStore,
                        detailPath: detailPath,
                        configuration: configuration
                    )
                    .actions
                )
            )
        )
    }
}

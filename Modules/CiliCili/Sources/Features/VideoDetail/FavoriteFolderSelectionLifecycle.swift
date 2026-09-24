import SwiftUI

private struct FavoriteFolderSelectionLifecycleModifier: ViewModifier {
    let favoriteFolders: [FavoriteFolder]
    let lifecycleActions: FavoriteFolderSelectionLifecycleActions

    func body(content: Content) -> some View {
        content
            .task {
                await lifecycleActions.load()
            }
            .onChange(of: favoriteFolders) { _, _ in
                lifecycleActions.syncSelectionIfNeeded()
            }
    }
}

extension View {
    func favoriteFolderSelectionLifecycle(
        favoriteFolders: [FavoriteFolder],
        actions: FavoriteFolderSelectionSheetActions
    ) -> some View {
        modifier(
            FavoriteFolderSelectionLifecycleModifier(
                favoriteFolders: favoriteFolders,
                lifecycleActions: FavoriteFolderSelectionLifecycleActions(actions: actions)
            )
        )
    }
}

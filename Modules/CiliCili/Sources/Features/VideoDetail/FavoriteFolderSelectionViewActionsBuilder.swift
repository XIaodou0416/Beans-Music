import SwiftUI

@MainActor
struct FavoriteFolderSelectionViewActionsBuilder {
    let store: VideoDetailFavoriteFolderRenderStore
    let loadFavoriteFolders: (Bool) async -> Void
    let saveFavoriteFolders: (Set<Int>) async -> Bool
    let dismiss: DismissAction
    let presentationState: Binding<FavoriteFolderSelectionPresentationState>

    var actions: FavoriteFolderSelectionViewActions {
        FavoriteFolderSelectionViewActions(
            store: store,
            loadFavoriteFolders: loadFavoriteFolders,
            saveFavoriteFolders: saveFavoriteFolders,
            dismiss: dismiss,
            presentationState: presentationState,
            stateActions: stateActions
        )
    }

    private var stateActions: FavoriteFolderSelectionStateActions {
        FavoriteFolderSelectionStateActions(
            store: store,
            presentationState: presentationState
        )
    }
}

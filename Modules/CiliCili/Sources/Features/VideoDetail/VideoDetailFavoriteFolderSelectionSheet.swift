import SwiftUI

struct FavoriteFolderSelectionSheet: View {
    @ObservedObject var store: VideoDetailFavoriteFolderRenderStore
    let loadFavoriteFolders: (Bool) async -> Void
    let saveFavoriteFolders: (Set<Int>) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var presentationState = FavoriteFolderSelectionPresentationState()

    var body: some View {
        NavigationStack {
            Form {
                FavoriteFolderSelectionContent(
                    folders: store.favoriteFolders,
                    state: store.favoriteFolderState,
                    selectedFolderIDs: $presentationState.selectedFolderIDs,
                    retry: viewActions.retryLoadingAction
                )
            }
            .navigationTitle("选择收藏夹")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                FavoriteFolderSelectionToolbar(
                    canSave: viewActions.canSaveFavoriteFolders,
                    cancel: viewActions.dismissFavoriteFolderSelection,
                    save: viewActions.saveFavoriteFoldersSelection
                )
            }
            .favoriteFolderSelectionLifecycle(
                favoriteFolders: store.favoriteFolders,
                actions: sheetActions
            )
        }
        .presentationDetents([.medium, .large])
        .onDisappear {
            viewActions.cancelPendingTasks()
        }
    }

    private var sheetActions: FavoriteFolderSelectionSheetActions {
        viewActions.sheetActions
    }

    private var viewActions: FavoriteFolderSelectionViewActions {
        FavoriteFolderSelectionViewActionsBuilder(
            store: store,
            loadFavoriteFolders: loadFavoriteFolders,
            saveFavoriteFolders: saveFavoriteFolders,
            dismiss: dismiss,
            presentationState: $presentationState
        )
        .actions
    }
}

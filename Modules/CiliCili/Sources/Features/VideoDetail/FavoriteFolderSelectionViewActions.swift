import SwiftUI

@MainActor
struct FavoriteFolderSelectionViewActions {
    let store: VideoDetailFavoriteFolderRenderStore
    let loadFavoriteFolders: (Bool) async -> Void
    let saveFavoriteFolders: (Set<Int>) async -> Bool
    let dismiss: DismissAction
    let presentationState: Binding<FavoriteFolderSelectionPresentationState>
    let stateActions: FavoriteFolderSelectionStateActions

    var sheetActions: FavoriteFolderSelectionSheetActions {
        FavoriteFolderSelectionSheetActions(
            loadFavoriteFolders: loadFavoriteFolders,
            saveFavoriteFolders: saveFavoriteFolders,
            initializeSelectionIfNeeded: stateActions.initializeSelectionIfNeeded
        )
    }

    var canSaveFavoriteFolders: Bool {
        !store.favoriteFolderState.isLoading && !store.isMutatingInteraction
    }

    func initializeSelectionIfNeeded(force: Bool = false) {
        stateActions.initializeSelectionIfNeeded(force: force)
    }

    func dismissFavoriteFolderSelection() {
        cancelPendingTasks()
        dismiss()
    }

    func retryLoadingAction() {
        taskActions.retryLoadingAction()
    }

    func saveFavoriteFoldersSelection() {
        taskActions.saveFavoriteFoldersSelection()
    }

    func cancelPendingTasks() {
        taskActions.cancelPendingTasks()
    }

    private func finishSavingFavoriteFolders() {
        Haptics.success()
        dismiss()
    }

    private var taskActions: FavoriteFolderSelectionTaskActions {
        FavoriteFolderSelectionTaskActions(
            loadFavoriteFolders: loadFavoriteFolders,
            sheetActions: sheetActions,
            stateActions: stateActions,
            presentationState: presentationState,
            onSaveCompleted: finishSavingFavoriteFolders
        )
    }
}

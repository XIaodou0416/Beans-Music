import SwiftUI

@MainActor
struct FavoriteFolderSelectionTaskActions {
    let loadFavoriteFolders: (Bool) async -> Void
    let sheetActions: FavoriteFolderSelectionSheetActions
    let stateActions: FavoriteFolderSelectionStateActions
    let presentationState: Binding<FavoriteFolderSelectionPresentationState>
    let onSaveCompleted: () -> Void

    func retryLoadingAction() {
        var state = presentationState.wrappedValue
        state.retryTask?.cancel()
        let token = UUID()
        state.retryTaskToken = token
        state.retryTask = Task { @MainActor in
            await loadFavoriteFolders(true)
            guard stateActions.isCurrentRetryTask(token) else { return }
            stateActions.initializeSelectionIfNeeded(force: true)
            stateActions.clearRetryTaskIfCurrent(token)
        }
        presentationState.wrappedValue = state
    }

    func saveFavoriteFoldersSelection() {
        var state = presentationState.wrappedValue
        state.saveTask?.cancel()
        let token = UUID()
        let selectedFolderIDs = state.selectedFolderIDs
        state.saveTaskToken = token
        state.saveTask = Task { @MainActor in
            let didSave = await sheetActions.save(selectedFolderIDs: selectedFolderIDs)
            guard stateActions.isCurrentSaveTask(token) else { return }
            stateActions.clearSaveTaskIfCurrent(token)
            if didSave {
                onSaveCompleted()
            }
        }
        presentationState.wrappedValue = state
    }

    func cancelPendingTasks() {
        var state = presentationState.wrappedValue
        state.retryTask?.cancel()
        state.retryTask = nil
        state.retryTaskToken = nil
        state.saveTask?.cancel()
        state.saveTask = nil
        state.saveTaskToken = nil
        presentationState.wrappedValue = state
    }
}

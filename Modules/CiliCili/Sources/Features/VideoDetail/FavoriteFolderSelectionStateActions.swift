import SwiftUI

@MainActor
struct FavoriteFolderSelectionStateActions {
    let store: VideoDetailFavoriteFolderRenderStore
    let presentationState: Binding<FavoriteFolderSelectionPresentationState>

    func initializeSelectionIfNeeded(force: Bool = false) {
        var state = presentationState.wrappedValue
        guard force || !state.didInitializeSelection else { return }
        state.selectedFolderIDs = Set(store.favoriteFolders.filter(\.isFavorited).map(\.id))
        state.didInitializeSelection = true
        presentationState.wrappedValue = state
    }

    func isCurrentRetryTask(_ token: UUID) -> Bool {
        presentationState.wrappedValue.retryTaskToken == token
    }

    func isCurrentSaveTask(_ token: UUID) -> Bool {
        presentationState.wrappedValue.saveTaskToken == token
    }

    func clearRetryTaskIfCurrent(_ token: UUID) {
        var state = presentationState.wrappedValue
        guard state.retryTaskToken == token else { return }
        state.retryTask = nil
        state.retryTaskToken = nil
        presentationState.wrappedValue = state
    }

    func clearSaveTaskIfCurrent(_ token: UUID) {
        var state = presentationState.wrappedValue
        guard state.saveTaskToken == token else { return }
        state.saveTask = nil
        state.saveTaskToken = nil
        presentationState.wrappedValue = state
    }
}

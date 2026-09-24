import SwiftUI

struct FavoriteFolderSelectionContent: View {
    let folders: [FavoriteFolder]
    let state: LoadingState
    @Binding var selectedFolderIDs: Set<Int>
    let retry: () -> Void

    var body: some View {
        if folders.isEmpty && state.isLoading {
            FavoriteFolderSelectionLoadingSection()
        } else if folders.isEmpty, case .failed(let message) = state {
            FavoriteFolderSelectionFailureSection(message: message, retry: retry)
        } else if folders.isEmpty {
            FavoriteFolderSelectionEmptySection()
        } else {
            FavoriteFolderSelectionLoadedSection(
                folders: folders,
                selectedFolderIDs: $selectedFolderIDs
            )
        }
    }
}

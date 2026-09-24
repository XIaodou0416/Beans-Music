import Foundation

@MainActor
struct FavoriteFolderSelectionSheetActions {
    let loadFavoriteFolders: (Bool) async -> Void
    let saveFavoriteFolders: (Set<Int>) async -> Bool
    let initializeSelectionIfNeeded: (Bool) -> Void

    func load() async {
        await loadFavoriteFolders(false)
        guard !Task.isCancelled else { return }
        initializeSelectionIfNeeded(false)
    }

    func save(selectedFolderIDs: Set<Int>) async -> Bool {
        await saveFavoriteFolders(selectedFolderIDs)
    }

    func syncSelectionIfNeeded() {
        initializeSelectionIfNeeded(false)
    }
}

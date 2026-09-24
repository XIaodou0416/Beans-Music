import Foundation

@MainActor
struct FavoriteFolderSelectionLifecycleActions {
    let actions: FavoriteFolderSelectionSheetActions

    func load() async {
        await actions.load()
    }

    func syncSelectionIfNeeded() {
        actions.syncSelectionIfNeeded()
    }
}

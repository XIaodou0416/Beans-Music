import Foundation

struct FavoriteFolderSelectionPresentationState {
    var selectedFolderIDs = Set<Int>()
    var didInitializeSelection = false
    var retryTask: Task<Void, Never>?
    var retryTaskToken: UUID?
    var saveTask: Task<Void, Never>?
    var saveTaskToken: UUID?
}

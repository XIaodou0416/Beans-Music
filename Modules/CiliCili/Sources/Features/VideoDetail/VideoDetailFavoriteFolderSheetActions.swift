import Foundation

@MainActor
struct VideoDetailFavoriteFolderSheetActions {
    weak var viewModel: VideoDetailViewModel?

    func loadFavoriteFolders(forceRefresh: Bool) async {
        await viewModel?.loadFavoriteFoldersForCurrentVideo(forceRefresh: forceRefresh)
    }

    func saveFavoriteFolders(selectedIDs: Set<Int>) async -> Bool {
        guard let viewModel else { return false }
        return await viewModel.setFavoriteFolders(selectedIDs: selectedIDs)
    }
}

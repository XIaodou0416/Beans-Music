import SwiftUI

@MainActor
struct VideoDetailFavoriteFolderSheetHost: View {
    @ObservedObject var viewModel: VideoDetailViewModel
    let actions: VideoDetailFavoriteFolderSheetActions

    var body: some View {
        FavoriteFolderSelectionSheet(
            store: viewModel.favoriteFolderRenderStore,
            loadFavoriteFolders: actions.loadFavoriteFolders,
            saveFavoriteFolders: actions.saveFavoriteFolders
        )
    }
}

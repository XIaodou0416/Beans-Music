import Foundation

@MainActor
private final class VideoDetailSummaryCardViewModelBox {
    weak var viewModel: VideoDetailViewModel?

    init(_ viewModel: VideoDetailViewModel) {
        self.viewModel = viewModel
    }
}

@MainActor
struct VideoDetailSummaryCardActions {
    private let viewModelBox: VideoDetailSummaryCardViewModelBox
    let showFavoriteFolders: () -> Void

    init(
        viewModel: VideoDetailViewModel,
        showFavoriteFolders: @escaping () -> Void
    ) {
        viewModelBox = VideoDetailSummaryCardViewModelBox(viewModel)
        self.showFavoriteFolders = showFavoriteFolders
    }

    func follow() {
        Haptics.light()
        Task { [weak viewModel = viewModelBox.viewModel] in
            guard let viewModel else { return }
            if await viewModel.toggleFollow() {
                Haptics.success()
            }
        }
    }

    func like() {
        Haptics.light()
        Task { [weak viewModel = viewModelBox.viewModel] in
            guard let viewModel else { return }
            if await viewModel.toggleLike() {
                Haptics.success()
            }
        }
    }

    func favorite() {
        Haptics.light()
        showFavoriteFolders()
    }

    func share() {
        Haptics.light()
    }

    func retryPlayURL() {
        Task { [weak viewModel = viewModelBox.viewModel] in
            guard let viewModel else { return }
            await viewModel.retryPlayURL()
        }
    }
}

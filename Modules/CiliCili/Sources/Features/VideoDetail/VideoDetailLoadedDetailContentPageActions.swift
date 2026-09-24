import Foundation

@MainActor
struct VideoDetailLoadedDetailContentPageActions {
    weak var viewModel: VideoDetailViewModel?

    func selectPage(_ page: VideoPage) {
        viewModel?.selectPage(page)
    }

    func selectPgcEpisode(_ video: VideoItem) {
        viewModel?.selectPgcEpisode(video)
    }

    func retryRelated() async {
        guard let viewModel else { return }
        await viewModel.retryRelated()
    }
}

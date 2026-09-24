import Foundation

extension HomeViewModel {
    func loadMoreIfNeeded(current video: VideoItem?) async {
        guard let video,
              videos.last?.id == video.id,
              !state.isLoading,
              !isRefreshing
        else { return }
        let revision = requestRevision
        state = .loading
        pageCoordinator.advanceCursor(for: mode)
        do {
            let moreVideos = try await pageCoordinator.fetchCurrentPage(
                for: mode,
                existingIDs: Set(videos.map(\.id))
            )
            guard revision == requestRevision else { return }
            appendUnique(moreVideos)
            state = .loaded
        } catch {
            guard revision == requestRevision else { return }
            pageCoordinator.rollbackCursor(for: mode)
            state = videos.isEmpty ? .failed(error.localizedDescription) : .loaded
        }
    }
}

import Foundation

struct HomeFeedExposureRecorder {
    let pageCoordinator: HomeFeedPageCoordinator

    func recordIfNeeded(_ videos: [VideoItem], mode: HomeFeedMode) {
        guard pageCoordinator.usesGuestRecommendDiversity(for: mode) else { return }
        HomeGuestRecommendState.recordExposure(Array(videos.prefix(80)))
    }
}

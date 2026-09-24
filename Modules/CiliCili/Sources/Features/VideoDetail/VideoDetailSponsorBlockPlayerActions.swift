import Foundation

extension VideoDetailViewModel {
    func resetSponsorBlockSegments() {
        cancelSponsorBlockTask()
        sponsorBlockSegments = []
        sponsorBlockIdentity = nil
        stablePlayerViewModel?.setSponsorBlockSegments([], isEnabled: false)
    }

    func applySponsorBlockSegmentsToPlayer() {
        guard !isPlaybackInvalidatedForNavigation else { return }
        stablePlayerViewModel?.setSponsorBlockSegments(
            sponsorBlockSegments,
            isEnabled: libraryStore.sponsorBlockEnabled
        ) { [sponsorBlockService] event in
            await sponsorBlockService.reportViewed(uuid: event.segment.uuid)
        }
    }
}

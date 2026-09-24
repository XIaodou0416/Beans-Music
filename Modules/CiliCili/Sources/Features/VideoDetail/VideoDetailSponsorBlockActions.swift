import Foundation

extension VideoDetailViewModel {
    func scheduleSponsorBlockSegmentsAfterFirstFrame() {
        guard !isPlaybackInvalidatedForNavigation else { return }
        guard libraryStore.sponsorBlockEnabled, let cid = selectedCID else {
            resetSponsorBlockSegments()
            return
        }

        let bvid = detail.bvid
        let identity = sponsorBlockIdentity(for: bvid, cid: cid)
        if sponsorBlockIdentity == identity {
            applySponsorBlockSegmentsToPlayer()
            return
        }

        cancelSponsorBlockTask(advancesGeneration: false)
        let generation = advanceSponsorBlockGeneration()
        sponsorBlockTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            defer {
                self.clearSponsorBlockTaskIfCurrent(generation: generation)
            }
            guard !self.isPlaybackInvalidatedForNavigation,
                  self.sponsorBlockGeneration == generation,
                  self.selectedCID == cid,
                  self.sponsorBlockIdentity(for: self.detail.bvid, cid: cid) == identity
            else { return }
            guard let release = await self.waitForPlaybackStartupRelease(acceptsFailure: false),
                  case .firstFrame = release,
                  !Task.isCancelled,
                  !self.isPlaybackInvalidatedForNavigation,
                  self.sponsorBlockGeneration == generation,
                  self.selectedCID == cid,
                  self.sponsorBlockIdentity(for: self.detail.bvid, cid: cid) == identity
            else { return }
            do {
                let segments = try await self.sponsorBlockService.fetchSkipSegments(bvid: bvid, cid: cid)
                guard !Task.isCancelled,
                      !self.isPlaybackInvalidatedForNavigation,
                      self.sponsorBlockGeneration == generation,
                      self.selectedCID == cid,
                      self.sponsorBlockIdentity(for: self.detail.bvid, cid: cid) == identity
                else { return }
                self.sponsorBlockIdentity = identity
                self.sponsorBlockSegments = segments
                self.applySponsorBlockSegmentsToPlayer()
            } catch {
                guard !Task.isCancelled,
                      !self.isPlaybackInvalidatedForNavigation,
                      self.sponsorBlockGeneration == generation,
                      self.selectedCID == cid,
                      self.sponsorBlockIdentity(for: self.detail.bvid, cid: cid) == identity
                else { return }
                self.sponsorBlockIdentity = identity
                self.sponsorBlockSegments = []
                self.applySponsorBlockSegmentsToPlayer()
            }
        }
    }

    private func sponsorBlockIdentity(for bvid: String, cid: Int) -> String {
        "\(bvid)-\(cid)"
    }
}

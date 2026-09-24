import Foundation

extension VideoDetailViewModel {
    func scheduleUploaderAndInteractionLoadIfNeeded() {
        guard !detail.isPGCEpisode else { return }
        guard !isPlaybackInvalidatedForNavigation, uploaderInteractionTask == nil else { return }
        guard let identity = currentUploaderInteractionIdentity,
              uploaderInteractionLoadIdentity != identity,
              (uploaderProfile == nil || interactionState == VideoInteractionState())
        else { return }
        uploaderInteractionLoadIdentity = identity
        let bvid = detail.bvid
        let aid = detail.aid
        let ownerMID = detail.owner?.mid
        let generation = advanceUploaderInteractionLoadGeneration()
        uploaderInteractionTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            defer {
                self.clearUploaderInteractionTaskIfCurrent(identity: identity, generation: generation)
            }
            let didLoad = await self.loadUploaderAndInteractionAfterFirstFrame(
                identity: identity,
                bvid: bvid,
                aid: aid,
                ownerMID: ownerMID,
                generation: generation
            )
            if !didLoad,
               self.uploaderInteractionLoadIdentity == identity,
               self.uploaderInteractionLoadGeneration == generation {
                self.uploaderInteractionLoadIdentity = nil
            }
        }
    }

    func loadUploaderAndInteraction(
        bvid: String? = nil,
        aid: Int? = nil,
        ownerMID: Int? = nil
    ) async {
        async let uploader: Void = loadUploaderProfile(mid: ownerMID, bvid: bvid, aid: aid)
        async let interaction: Void = loadInteractionState(aid: aid, bvid: bvid)
        _ = await (uploader, interaction)
    }

    func loadUploaderAndInteractionAfterFirstFrame(
        identity: String,
        bvid: String?,
        aid: Int?,
        ownerMID: Int?,
        generation: Int
    ) async -> Bool {
        if libraryStore.videoDetailAutoplayEnabled {
            guard let release = await waitForPlaybackStartupRelease(acceptsFailure: true),
                  !Task.isCancelled,
                  isCurrentVideoContext(aid: aid, bvid: bvid, ownerMID: ownerMID),
                  currentUploaderInteractionIdentity == identity,
                  uploaderInteractionLoadGeneration == generation
            else { return false }
            if case .firstFrame = release {
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled,
                      isCurrentVideoContext(aid: aid, bvid: bvid, ownerMID: ownerMID),
                      currentUploaderInteractionIdentity == identity,
                      uploaderInteractionLoadGeneration == generation
                else { return false }
                }
            }
        guard !Task.isCancelled,
              isCurrentVideoContext(aid: aid, bvid: bvid, ownerMID: ownerMID),
              currentUploaderInteractionIdentity == identity,
              uploaderInteractionLoadGeneration == generation
        else { return false }
        await loadUploaderAndInteraction(bvid: bvid, aid: aid, ownerMID: ownerMID)
        return !Task.isCancelled
            && isCurrentVideoContext(aid: aid, bvid: bvid, ownerMID: ownerMID)
            && currentUploaderInteractionIdentity == identity
            && uploaderInteractionLoadGeneration == generation
    }
}

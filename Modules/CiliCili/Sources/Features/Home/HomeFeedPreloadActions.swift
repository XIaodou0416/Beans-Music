import Foundation

private struct HomeFeedStableVisibleCandidate {
    let video: VideoItem
    let index: Int
}

@MainActor
final class HomeFeedPreloadActions {
    private static let stableVisiblePreloadDelayNanoseconds: UInt64 = 650_000_000
    private static let stableVisiblePreloadLimit = 3
    private static let initialFullPreloadCardCount = 2

    private var pressedPreloadVideos = Set<String>()
    private var stableVisibleCandidates = [String: HomeFeedStableVisibleCandidate]()
    private var stableVisiblePreloadedVideos = Set<String>()
    private var stableVisiblePreloadTask: Task<Void, Never>?
    private var activeStableVisibleCandidateID: String?
    private var stableVisibleFeedRootBVID = ""
    private var latestStableVisiblePreloadContext: HomeFeedPreloadContext?

    deinit {
        stableVisiblePreloadTask?.cancel()
    }

    func beginPressedPreloadIfNeeded(
        for video: VideoItem,
        context: HomeFeedPreloadContext
    ) {
        let bvid = video.bvid
        guard !bvid.isEmpty,
              !bvid.hasPrefix("av"),
              !pressedPreloadVideos.contains(bvid)
        else { return }
        pressedPreloadVideos.insert(bvid)

        Task {
            await VideoPreloadCenter.shared.updatePlaybackPreferences(
                preferredQuality: context.preferredQuality,
                cdnPreference: context.cdnPreference,
                playbackAdaptationProfile: context.playbackAdaptationProfile
            )
            await VideoPreloadCenter.shared.preloadPlayInfo(
                video,
                api: context.api,
                preferredQuality: context.preferredQuality,
                cdnPreference: context.cdnPreference,
                priority: .userInitiated,
                warmsMedia: true,
                mediaWarmupDelay: 0,
                playbackAdaptationProfile: context.playbackAdaptationProfile
            )
            await VideoPreloadCenter.shared.prioritizePlayback(for: video)
        }
    }

    func recordVisibleCard(
        _ video: VideoItem,
        index: Int,
        context: HomeFeedPreloadContext
    ) {
        let bvid = video.bvid
        guard !bvid.isEmpty else { return }

        if index == 0, stableVisibleFeedRootBVID != bvid {
            resetStableVisiblePreloads(feedRootBVID: bvid)
        }

        guard index >= Self.initialFullPreloadCardCount,
              video.cid != nil,
              !bvid.hasPrefix("av"),
              !video.isPGCEpisode
        else { return }

        stableVisibleCandidates[bvid] = HomeFeedStableVisibleCandidate(
            video: video,
            index: index
        )
        latestStableVisiblePreloadContext = context
        scheduleStableVisiblePreload(context: context)
    }

    func recordCardDisappearance(_ video: VideoItem) {
        guard !video.bvid.isEmpty else { return }
        stableVisibleCandidates.removeValue(forKey: video.bvid)
        guard let context = latestStableVisiblePreloadContext else {
            cancelStableVisiblePreload()
            return
        }
        scheduleStableVisiblePreload(context: context)
    }

    private func resetStableVisiblePreloads(feedRootBVID: String) {
        stableVisiblePreloadTask?.cancel()
        stableVisiblePreloadTask = nil
        activeStableVisibleCandidateID = nil
        stableVisibleCandidates.removeAll()
        stableVisiblePreloadedVideos.removeAll()
        stableVisibleFeedRootBVID = feedRootBVID
        latestStableVisiblePreloadContext = nil
    }

    private func scheduleStableVisiblePreload(context: HomeFeedPreloadContext) {
        guard !PlaybackEnvironment.current.shouldPreferConservativePlayback,
              stableVisiblePreloadedVideos.count < Self.stableVisiblePreloadLimit,
              let candidate = nextStableVisibleCandidate()
        else {
            cancelStableVisiblePreload()
            return
        }

        guard activeStableVisibleCandidateID != candidate.video.bvid else { return }
        cancelStableVisiblePreload()
        activeStableVisibleCandidateID = candidate.video.bvid

        let candidateBVID = candidate.video.bvid
        let feedRootBVID = stableVisibleFeedRootBVID
        stableVisiblePreloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.stableVisiblePreloadDelayNanoseconds)
            guard !Task.isCancelled,
                  let self,
                  self.activeStableVisibleCandidateID == candidateBVID,
                  self.stableVisibleFeedRootBVID == feedRootBVID,
                  self.stableVisibleCandidates[candidateBVID] != nil,
                  !PlaybackEnvironment.current.shouldPreferConservativePlayback
            else { return }

            self.stableVisiblePreloadedVideos.insert(candidateBVID)
            await VideoPreloadCenter.shared.updatePlaybackPreferences(
                preferredQuality: context.preferredQuality,
                cdnPreference: context.cdnPreference,
                playbackAdaptationProfile: context.playbackAdaptationProfile
            )
            await VideoPreloadCenter.shared.preloadPlayInfo(
                candidate.video,
                api: context.api,
                preferredQuality: context.preferredQuality,
                cdnPreference: context.cdnPreference,
                priority: .utility,
                warmsMedia: false,
                playbackAdaptationProfile: context.playbackAdaptationProfile
            )
            guard self.activeStableVisibleCandidateID == candidateBVID else { return }
            self.stableVisiblePreloadTask = nil
            self.activeStableVisibleCandidateID = nil
        }
    }

    private func nextStableVisibleCandidate() -> HomeFeedStableVisibleCandidate? {
        stableVisibleCandidates.values
            .filter { !stableVisiblePreloadedVideos.contains($0.video.bvid) }
            .min { $0.index < $1.index }
    }

    private func cancelStableVisiblePreload() {
        stableVisiblePreloadTask?.cancel()
        stableVisiblePreloadTask = nil
        activeStableVisibleCandidateID = nil
    }
}

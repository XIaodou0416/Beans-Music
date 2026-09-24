import Foundation

@MainActor
final class DynamicFeedResourcePrefetchCoordinator {
    private let api: BiliAPIClient
    private let libraryStore: LibraryStore
    private var imagePrefetchTask: Task<Void, Never>?
    private var playbackPreloadTask: Task<Void, Never>?
    private let resourcePrefetchDebouncer = TaskDebouncer()

    init(api: BiliAPIClient, libraryStore: LibraryStore) {
        self.api = api
        self.libraryStore = libraryStore
    }

    deinit {
        imagePrefetchTask?.cancel()
        playbackPreloadTask?.cancel()
    }

    func scheduleResourcePrefetch(for items: [DynamicFeedItem], initialDelay: TimeInterval) {
        if initialDelay <= 0.12 {
            Task {
                await ResourceLoadingForegroundPriorityGate.shared.beginFirstScreenPriorityWindow(for: .dynamic)
            }
        }
        let environment = PlaybackEnvironment.current
        let snapshotLimit = environment.shouldPreferConservativePlayback ? 5 : 8
        let snapshot = Array(items.prefix(snapshotLimit))
        let adaptiveDelay = environment.shouldPreferConservativePlayback ? initialDelay + 0.45 : initialDelay + 0.2
        let delayMilliseconds = max(Int64((adaptiveDelay * 1000).rounded()), 120)
        resourcePrefetchDebouncer.schedule(delay: .milliseconds(delayMilliseconds)) { [weak self] in
            guard let self else { return }
            self.scheduleImagePrefetch(for: snapshot, initialDelay: 0)
            guard !environment.shouldPreferConservativePlayback else { return }
            self.schedulePlaybackPreload(for: snapshot, initialDelay: 0.45)
        }
    }

    private func scheduleImagePrefetch(for items: [DynamicFeedItem], initialDelay: TimeInterval) {
        imagePrefetchTask?.cancel()
        let environment = PlaybackEnvironment.current
        let prefetchPlan = dynamicImagePrefetchPlan(for: items, environment: environment)

        guard !prefetchPlan.avatarSources.isEmpty
            || !prefetchPlan.compactImageSources.isEmpty
            || !prefetchPlan.expandedImageSources.isEmpty
            || !prefetchPlan.coverSources.isEmpty
        else { return }
        let avatarPrefetchSources = prefetchPlan.avatarSources
        let compactImagePrefetchSources = prefetchPlan.compactImageSources
        let expandedImagePrefetchSources = prefetchPlan.expandedImageSources
        let coverPrefetchSources = prefetchPlan.coverSources
        let compactImageTargetPixelSize = DynamicImageThumbnailSizing.targetPixelSize(
            usesExpandedImage: false,
            usesCompactImages: environment.shouldPreferConservativePlayback
        )
        let expandedImageTargetPixelSize = DynamicImageThumbnailSizing.targetPixelSize(
            usesExpandedImage: true,
            usesCompactImages: environment.shouldPreferConservativePlayback
        )
        let coverTargetPixelSize = environment.shouldPreferConservativePlayback ? 360 : 480
        imagePrefetchTask = Task(priority: .utility) {
            if initialDelay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(initialDelay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            async let avatars: Void = RemoteImageCache.shared.prefetch(
                avatarPrefetchSources,
                targetPixelSize: 96,
                maximumConcurrentLoads: 1
            )
            async let expandedImages: Void = RemoteImageCache.shared.prefetch(
                expandedImagePrefetchSources,
                targetPixelSize: expandedImageTargetPixelSize,
                maximumConcurrentLoads: 1
            )
            async let compactImages: Void = RemoteImageCache.shared.prefetch(
                compactImagePrefetchSources,
                targetPixelSize: compactImageTargetPixelSize,
                maximumConcurrentLoads: environment.shouldPreferConservativePlayback ? 1 : 2
            )
            async let covers: Void = RemoteImageCache.shared.prefetch(
                coverPrefetchSources,
                targetPixelSize: coverTargetPixelSize,
                maximumConcurrentLoads: 1
            )
            _ = await (avatars, expandedImages, compactImages, covers)
        }
    }

    private func dynamicImagePrefetchPlan(
        for items: [DynamicFeedItem],
        environment: PlaybackEnvironment
    ) -> (
        avatarSources: [RemoteImageSource],
        compactImageSources: [RemoteImageSource],
        expandedImageSources: [RemoteImageSource],
        coverSources: [RemoteImageSource]
    ) {
        var avatarSources = [RemoteImageSource]()
        var compactImageSources = [RemoteImageSource]()
        var expandedImageSources = [RemoteImageSource]()
        var coverSources = [RemoteImageSource]()
        var seenURLs = Set<String>()

        let itemLimit = environment.shouldPreferConservativePlayback ? 5 : 8
        let imagesPerItemLimit = environment.shouldPreferConservativePlayback ? 2 : 3
        let totalImageLimit = environment.shouldPreferConservativePlayback ? 4 : 6
        let coverTargetPixelSize = environment.shouldPreferConservativePlayback ? 360 : 480
        var scheduledImageCount = 0
        for item in items.prefix(itemLimit) {
            if let source = item.author?.face?.normalizedBiliURL(),
               let avatarURL = URL(string: source.biliAvatarThumbnailURL(size: 96)),
               seenURLs.insert(source).inserted {
                avatarSources.append(RemoteImageSource(url: avatarURL, fallbackURL: URL(string: source)))
            }

            for image in item.imageItems.prefix(imagesPerItemLimit) {
                guard scheduledImageCount < totalImageLimit,
                      let sourceURL = image.normalizedURL,
                      seenURLs.insert(sourceURL).inserted,
                      let request = DynamicImageThumbnailSizing.prefetchRequest(
                        for: image,
                        imageCount: item.imageItems.count,
                        usesCompactImages: environment.shouldPreferConservativePlayback
                      )
                else { continue }
                if request.targetPixelSize == DynamicImageThumbnailSizing.targetPixelSize(
                    usesExpandedImage: true,
                    usesCompactImages: environment.shouldPreferConservativePlayback
                ) {
                    expandedImageSources.append(request.source)
                } else {
                    compactImageSources.append(request.source)
                }
                scheduledImageCount += 1
            }

            if let video = item.archive?.asVideoItem(author: item.author),
               let source = video.pic?.normalizedBiliURL(),
               let coverURL = URL(string: source.biliCoverThumbnailURL(width: coverTargetPixelSize, height: Int(Double(coverTargetPixelSize) * 9 / 16))),
               seenURLs.insert(source).inserted {
                coverSources.append(RemoteImageSource(url: coverURL, fallbackURL: URL(string: source)))
            }

            if let source = item.paidContent?.normalizedCoverURL,
               let coverURL = URL(string: source.biliCoverThumbnailURL(width: coverTargetPixelSize, height: Int(Double(coverTargetPixelSize) * 9 / 16))),
               seenURLs.insert(source).inserted {
                coverSources.append(RemoteImageSource(url: coverURL, fallbackURL: URL(string: source)))
            }
        }

        return (avatarSources, compactImageSources, expandedImageSources, coverSources)
    }

    private func schedulePlaybackPreload(for items: [DynamicFeedItem], initialDelay: TimeInterval) {
        playbackPreloadTask?.cancel()
        guard !PlaybackEnvironment.current.shouldPreferConservativePlayback else {
            playbackPreloadTask = nil
            return
        }

        let videos = items
            .compactMap { $0.archive?.asVideoItem(author: $0.author) }
            .filter { !$0.bvid.isEmpty }
        let playbackAdaptationProfile = PlayerPerformanceStore.shared.playbackAdaptationProfile(
            isEnabled: libraryStore.isPlaybackAutoOptimizationEnabled
        )
        let candidateLimit = max(0, min(2, playbackAdaptationProfile.backgroundPreloadLimit))
        guard candidateLimit > 0 else {
            playbackPreloadTask = nil
            return
        }
        let candidates = Array(videos.prefix(candidateLimit))
        guard !candidates.isEmpty else {
            playbackPreloadTask = nil
            return
        }

        let preferredQuality = libraryStore.effectivePreferredVideoQuality
        let cdnPreference = libraryStore.effectivePlaybackCDNPreference
        playbackPreloadTask = Task(priority: .background) { [api, cdnPreference] in
            if initialDelay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(initialDelay * 1_000_000_000))
            }
            let foregroundDelay = await ResourceLoadingForegroundPriorityGate.shared
                .backgroundDelayNanoseconds(for: .dynamic)
            if foregroundDelay > 0 {
                try? await Task.sleep(nanoseconds: foregroundDelay)
            }
            guard !Task.isCancelled else { return }
            await VideoPreloadCenter.shared.updatePlaybackPreferences(
                preferredQuality: preferredQuality,
                cdnPreference: cdnPreference,
                playbackAdaptationProfile: playbackAdaptationProfile
            )
            for (index, video) in candidates.enumerated() {
                guard !Task.isCancelled else { return }
                let isPrimary = index == 0
                await VideoPreloadCenter.shared.preloadPlayInfo(
                    video,
                    api: api,
                    preferredQuality: preferredQuality,
                    cdnPreference: cdnPreference,
                    priority: .background,
                    warmsMedia: true,
                    mediaWarmupMode: isPrimary ? .full : .routePlanOnly,
                    mediaWarmupDelay: isPrimary ? 0.45 : 0.65,
                    playbackAdaptationProfile: playbackAdaptationProfile
                )
                if index < candidates.count - 1 {
                    try? await Task.sleep(nanoseconds: 650_000_000)
                }
            }
        }
    }
}

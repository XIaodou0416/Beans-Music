import Foundation

enum VideoListenAdvanceDirection: Equatable {
    case previous
    case next
}

enum VideoListenAdvanceReason: String {
    case playbackEnded
    case systemControl
    case queueSelection
}

enum VideoListenAudioFallbackResolver {
    static func fallback(
        automatic: VideoListenAudioVariant?,
        variants: [VideoListenAudioVariant],
        failedIDs: Set<String>
    ) -> VideoListenAudioVariant? {
        if let automatic, !failedIDs.contains(automatic.id) {
            return automatic
        }
        return variants
            .filter { !failedIDs.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.kind == .aac, rhs.kind != .aac { return true }
                if lhs.kind != .aac, rhs.kind == .aac { return false }
                return lhs.kind.sortRank < rhs.kind.sortRank
            }
            .first
    }
}

enum VideoListenSequenceResolver {
    static func page(
        in pages: [VideoPage],
        selectedCID: Int?,
        direction: VideoListenAdvanceDirection
    ) -> VideoPage? {
        guard !pages.isEmpty else { return nil }
        let currentIndex = selectedCID.flatMap { cid in pages.firstIndex { $0.cid == cid } } ?? 0
        let targetIndex = direction == .next ? currentIndex + 1 : currentIndex - 1
        guard pages.indices.contains(targetIndex) else { return nil }
        return pages[targetIndex]
    }

    static func episode(
        in season: PgcSeasonInfo,
        current detail: VideoItem,
        direction: VideoListenAdvanceDirection
    ) -> VideoItem? {
        let episodes = season.allPlayableEpisodes
        guard let currentIndex = episodes.firstIndex(where: { episode in
            if let episodeID = detail.pgcEpisodeID,
               episode.epID == episodeID || episode.idValue == episodeID {
                return true
            }
            if let cid = detail.cid, episode.cid == cid {
                return true
            }
            return episode.bvid?.trimmingCharacters(in: .whitespacesAndNewlines) == detail.bvid
        }) else { return nil }
        let targetIndex = direction == .next ? currentIndex + 1 : currentIndex - 1
        guard episodes.indices.contains(targetIndex) else { return nil }
        return episodes[targetIndex].videoItem(in: season)
    }
}

extension VideoDetailViewModel {
    var isVideoListenModeEnabled: Bool {
        playbackContentMode == .audioOnly
    }

    var canUseVideoListenMode: Bool {
        resolvedVideoListenAudioVariant != nil
    }

    var automaticVideoListenAudioVariant: VideoListenAudioVariant? {
        guard let automaticVideoListenAudioVariantID else { return videoListenAudioVariants.first }
        return videoListenAudioVariants.first { $0.id == automaticVideoListenAudioVariantID }
            ?? videoListenAudioVariants.first
    }

    var selectedVideoListenAudioVariant: VideoListenAudioVariant? {
        guard let selectedVideoListenAudioPreferenceKey else { return nil }
        return videoListenAudioVariants.first { $0.preferenceKey == selectedVideoListenAudioPreferenceKey }
    }

    var resolvedVideoListenAudioVariant: VideoListenAudioVariant? {
        selectedVideoListenAudioVariant ?? automaticVideoListenAudioVariant
    }

    var videoListenAudioAccessoryTitle: String {
        if selectedVideoListenAudioPreferenceKey == nil {
            guard let automaticVideoListenAudioVariant else { return "自动" }
            return "自动 · \(automaticVideoListenAudioVariant.title)"
        }
        return selectedVideoListenAudioVariant?.title ?? "自动降级"
    }

    func applyVideoListenAudioVariants(from data: PlayURLData) {
        let variants = data.videoListenAudioVariants(
            cdnPreference: libraryStore.effectivePlaybackCDNPreference,
            prefersBackupAudioURL: libraryStore.prefersBackupAudioURL
        )
        let automaticStream = data.dash?.bestAudioStream
        videoListenAudioVariants = variants
        automaticVideoListenAudioVariantID = variants.first { $0.stream == automaticStream }?.id
            ?? variants.first?.id
        failedVideoListenAudioVariantIDs.removeAll()
    }

    func clearVideoListenAudioVariants() {
        videoListenAudioVariants = []
        automaticVideoListenAudioVariantID = nil
        failedVideoListenAudioVariantIDs.removeAll()
    }

    func selectVideoListenAudioVariant(_ variant: VideoListenAudioVariant?) {
        guard playbackContentMode == .audioOnly,
              !isPlaybackInvalidatedForNavigation,
              !isSwitchingVideoListenMode
        else { return }

        let previousVariant = resolvedVideoListenAudioVariant
        let preferenceKey = variant?.preferenceKey
        guard selectedVideoListenAudioPreferenceKey != preferenceKey else { return }
        selectedVideoListenAudioPreferenceKey = preferenceKey
        failedVideoListenAudioVariantIDs.removeAll()
        persistVideoListenPlaybackSession()
        guard let nextVariant = resolvedVideoListenAudioVariant else { return }

        PlayerMetricsLog.record(
            .qualitySupplement,
            metricsID: detail.bvid,
            title: detail.title,
            message: "listenAudioSelect mode=\(preferenceKey == nil ? "auto" : "manual") stream=\(nextVariant.diagnosticSummary)"
        )
        guard previousVariant?.url != nextVariant.url || previousVariant?.stream != nextVariant.stream else {
            updateVideoListenRemoteNavigationAvailability()
            return
        }

        let resumeTime = currentPlaybackResumeTime()
        let shouldResumePlayback = currentPlaybackIntent()
        let playbackRate = stablePlayerViewModel?.playbackRate ?? .x10
        isSwitchingVideoListenMode = true
        playbackFallbackMessage = nil
        updateStablePlayerViewModelIfNeeded(
            resumeTimeOverride: resumeTime,
            shouldResumePlayback: shouldResumePlayback,
            playbackRateOverride: playbackRate,
            preservesPreviousPlayerUntilFirstFrame: shouldResumePlayback,
            usesSeamlessPlaybackHandoff: shouldResumePlayback
        )
        if !shouldResumePlayback {
            isSwitchingVideoListenMode = false
        }
    }

    func setVideoListenModeEnabled(_ isEnabled: Bool) {
        guard !isPlaybackInvalidatedForNavigation,
              !isSwitchingPlayQuality,
              !isSwitchingVideoListenMode,
              let variant = selectedPlayVariant
        else { return }

        let nextMode: PlayerPlaybackContentMode = isEnabled ? .audioOnly : .video
        guard nextMode != playbackContentMode else { return }
        if isEnabled {
            guard resolvedVideoListenAudioVariant != nil
            else { return }
        } else {
            guard variant.videoURL != nil else { return }
        }

        let resumeTime = currentPlaybackResumeTime()
        let shouldResumePlayback = currentPlaybackIntent()
        let playbackRate = stablePlayerViewModel?.playbackRate ?? .x10
        cancelHLSRenditionPrebuildTask()
        cancelSeekWarmups()
        playbackContentMode = nextMode
        isSwitchingVideoListenMode = true
        playbackFallbackMessage = nil
        if isEnabled {
            persistVideoListenPlaybackSession(wantsPlayback: shouldResumePlayback)
            scheduleVideoListenQueuePreparation()
            scheduleVideoListenContinuationPreload()
        } else {
            cancelVideoListenQueueTasks(resetSession: false)
            videoListenPlaybackSessionStore.removeState(for: detail)
            pendingVideoListenPlaybackSessionState = nil
            cancelVideoListenSleepTimer()
        }
        updateStablePlayerViewModelIfNeeded(
            resumeTimeOverride: resumeTime,
            shouldResumePlayback: shouldResumePlayback,
            playbackRateOverride: playbackRate,
            preservesPreviousPlayerUntilFirstFrame: shouldResumePlayback,
            usesSeamlessPlaybackHandoff: shouldResumePlayback
        )
        if !shouldResumePlayback {
            isSwitchingVideoListenMode = false
        }
    }

    func normalizeVideoListenMode(for variant: PlayVariant) {
        guard playbackContentMode == .audioOnly,
              resolvedVideoListenAudioVariant == nil
        else { return }
        playbackContentMode = .video
        isSwitchingVideoListenMode = false
        videoListenPlaybackSessionStore.removeState(for: detail)
        pendingVideoListenPlaybackSessionState = nil
        cancelVideoListenSleepTimer()
        playbackFallbackMessage = "当前分 P 没有独立音频，已切回视频"
    }

    @discardableResult
    func restoreCompatibleVideoListenAudioAfterFailure(_ message: String?) -> Bool {
        guard playbackContentMode == .audioOnly,
              let failedVariant = resolvedVideoListenAudioVariant
        else { return false }

        failedVideoListenAudioVariantIDs.insert(failedVariant.id)
        let fallbackVariant = VideoListenAudioFallbackResolver.fallback(
            automatic: automaticVideoListenAudioVariant,
            variants: videoListenAudioVariants,
            failedIDs: failedVideoListenAudioVariantIDs
        )
        guard let fallbackVariant else { return false }

        let resumeTime = currentPlaybackResumeTime()
        let playbackRate = stablePlayerViewModel?.playbackRate ?? .x10
        selectedVideoListenAudioPreferenceKey = fallbackVariant.preferenceKey
        persistVideoListenPlaybackSession(wantsPlayback: true)
        isSwitchingVideoListenMode = true
        let failureDetail = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        playbackFallbackMessage = failureDetail.isEmpty
            ? "当前音质播放失败，已切换到 \(fallbackVariant.title)"
            : "当前音质播放失败，已切换到 \(fallbackVariant.title)：\(failureDetail)"
        PlayerMetricsLog.record(
            .playbackRecovery,
            metricsID: detail.bvid,
            title: detail.title,
            message: "listenAudioFallback from=\(failedVariant.diagnosticSummary) to=\(fallbackVariant.diagnosticSummary)"
        )
        updateStablePlayerViewModelIfNeeded(
            resumeTimeOverride: resumeTime,
            shouldResumePlayback: true,
            playbackRateOverride: playbackRate,
            preservesPreviousPlayerUntilFirstFrame: false
        )
        return true
    }

    @discardableResult
    func restoreVideoAfterVideoListenFailure(_ message: String?) -> Bool {
        guard playbackContentMode == .audioOnly,
              let variant = selectedPlayVariant,
              variant.videoURL != nil
        else { return false }

        let resumeTime = currentPlaybackResumeTime()
        let playbackRate = stablePlayerViewModel?.playbackRate ?? .x10
        playbackContentMode = .video
        isSwitchingVideoListenMode = false
        videoListenPlaybackSessionStore.removeState(for: detail)
        pendingVideoListenPlaybackSessionState = nil
        cancelVideoListenSleepTimer()
        let failureDetail = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        playbackFallbackMessage = failureDetail.isEmpty
            ? "听视频播放失败，已切回视频"
            : "听视频播放失败，已切回视频：\(failureDetail)"
        updateStablePlayerViewModelIfNeeded(
            resumeTimeOverride: resumeTime,
            shouldResumePlayback: true,
            playbackRateOverride: playbackRate,
            preservesPreviousPlayerUntilFirstFrame: false
        )
        return true
    }

    func advanceVideoListenPlayback(
        direction: VideoListenAdvanceDirection,
        reason: VideoListenAdvanceReason
    ) {
        guard playbackContentMode == .audioOnly,
              !isPlaybackInvalidatedForNavigation
        else { return }

        if let targetPage = VideoListenSequenceResolver.page(
            in: detail.pages ?? [],
            selectedCID: selectedCID,
            direction: direction
        ) {
            beginVideoListenAdvance(
                target: "p\(targetPage.page ?? 0)",
                reason: reason
            )
            selectPage(targetPage)
            return
        }

        let sourceBVID = detail.bvid
        let sourceCID = selectedCID
        let task = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await self.prepareVideoListenQueue()
            guard !Task.isCancelled,
                  self.isCurrentPlaybackContext(bvid: sourceBVID, cid: sourceCID)
            else { return }
            var targetVideo = self.videoListenQueueSession.video(
                relativeTo: self.detail,
                direction: direction
            )
            if targetVideo == nil,
               let currentEntry = self.videoListenQueueEntries.first(where: \.isCurrent) {
                await self.loadMoreVideoListenQueueIfNeeded(
                    current: currentEntry,
                    preferredDirection: direction
                )
                targetVideo = self.videoListenQueueSession.video(
                    relativeTo: self.detail,
                    direction: direction
                )
            }
            guard let targetVideo else {
                if direction == .previous {
                    self.stablePlayerViewModel?.seek(to: 0)
                    self.stablePlayerViewModel?.play()
                }
                self.updateVideoListenRemoteNavigationAvailability()
                return
            }
            self.beginVideoListenAdvance(
                target: VideoListenQueueBuilder.contentKey(for: targetVideo),
                reason: reason
            )
            self.selectVideoListenQueueVideo(
                targetVideo,
                direction: direction,
                shouldAutoplay: true
            )
        }
        trackBackgroundTask(task)
    }

    var videoListenQueueEntries: [VideoListenQueueEntry] {
        VideoListenQueueBuilder.entries(
            videos: videoListenQueueSession.videos,
            current: detail,
            selectedCID: selectedCID
        )
    }

    var isLoadingVideoListenQueue: Bool {
        videoListenQueueSession.isLoadingInitial
    }

    var videoListenQueueLoadFailed: Bool {
        videoListenQueueSession.errorMessage != nil
    }

    var videoListenQueueSourceTitle: String {
        videoListenQueueSession.source.title
    }

    var videoListenQueueAccessoryTitle: String {
        let entries = videoListenQueueEntries
        if isLoadingVideoListenQueue, entries.count <= 1 {
            return "载入中"
        }
        guard !entries.isEmpty else { return "无可播放内容" }
        let currentIndex = entries.firstIndex(where: \.isCurrent).map { $0 + 1 } ?? 1
        let loadingSuffix = videoListenQueueSession.isLoadingMore ? " · 载入更多" : ""
        return "\(currentIndex)/\(entries.count)\(loadingSuffix)"
    }

    var videoListenSleepTimerAccessoryTitle: String {
        videoListenSleepTimerOption.title
    }

    func prepareVideoListenQueue() async {
        guard playbackContentMode == .audioOnly,
              !isLoadingVideoListenQueue
        else { return }

        if videoListenQueueIsReadyForCurrentContext {
            return
        }

        let anchor = detail
        if detail.isPGCEpisode {
            let source = VideoListenQueueSource.pgcSeason(id: detail.pgcSeasonID)
            let generation = videoListenQueueSession.beginInitialLoad(
                source: source,
                anchor: anchor
            )
            guard let season = await videoListenSeasonInfoIfNeeded() else {
                if Task.isCancelled {
                    videoListenQueueSession.cancelLoading(generation: generation)
                } else {
                    videoListenQueueSession.failInitialLoad("剧集列表载入失败", generation: generation)
                }
                return
            }
            let videos = season.allPlayableEpisodes.compactMap { $0.videoItem(in: season) }
            guard videoListenQueueSession.finishInitialLoad(
                videos: videos,
                anchor: anchor,
                source: source,
                nextPage: 1,
                nextCursor: nil,
                hasMore: false,
                generation: generation
            ) else { return }
            updateVideoListenRemoteNavigationAvailability()
            scheduleVideoListenContinuationPreload()
            return
        }

        if let anchorAID = anchor.aid,
           anchorAID > 0,
           let anchorCID = selectedCID ?? anchor.cid ?? anchor.pages?.first?.cid,
           anchorCID > 0 {
            let sortOrder = libraryStore.videoListenPlaylistSortOrder
            let source = VideoListenQueueSource.officialListener(
                anchorAID: anchorAID,
                sortOrder: sortOrder
            )
            let generation = videoListenQueueSession.beginInitialLoad(
                source: source,
                anchor: anchor
            )
            do {
                let page = try await api.fetchOfficialVideoListenPlaylist(
                    aid: anchorAID,
                    cid: anchorCID,
                    sortOrder: sortOrder
                )
                guard !Task.isCancelled else {
                    videoListenQueueSession.cancelLoading(generation: generation)
                    return
                }
                guard playbackContentMode == .audioOnly,
                      VideoListenQueueBuilder.representsSameVideo(detail, anchor)
                else {
                    videoListenQueueSession.cancelLoading(generation: generation)
                    return
                }
                guard page.videos.contains(where: {
                    !VideoListenQueueBuilder.representsSameVideo($0, anchor)
                }) else {
                    throw BiliListenerPlaylistError.emptyPlaylist
                }
                guard videoListenQueueSession.finishInitialLoad(
                    videos: page.videos,
                    anchor: anchor,
                    source: source,
                    nextPage: 1,
                    nextCursor: nil,
                    hasMore: false,
                    listenerPreviousToken: page.previousToken,
                    listenerNextToken: page.nextToken,
                    generation: generation
                ) else { return }
                PlayerMetricsLog.record(
                    .network,
                    metricsID: anchor.bvid,
                    title: anchor.title,
                    message: "listenQueue source=listener count=\(videoListenQueueSession.videos.count) total=\(page.totalCount ?? -1) prev=\(page.previousToken == nil ? 0 : 1) next=\(page.nextToken == nil ? 0 : 1) order=\(sortOrder.rawValue)"
                )
                updateVideoListenRemoteNavigationAvailability()
                scheduleVideoListenContinuationPreload()
                return
            } catch {
                guard !Task.isCancelled else {
                    videoListenQueueSession.cancelLoading(generation: generation)
                    return
                }
                let reason = (error as? BiliListenerPlaylistError)?.diagnosticReason
                    ?? String(describing: type(of: error))
                PlayerMetricsLog.record(
                    .network,
                    metricsID: anchor.bvid,
                    title: anchor.title,
                    message: "listenQueue listenerFailure=\(reason) fallback=uploader"
                )
            }
        }

        guard let ownerMID = detail.owner?.mid, ownerMID > 0 else {
            await loadRelatedVideoListenQueue(anchor: anchor)
            return
        }

        let source = VideoListenQueueSource.uploader(mid: ownerMID)
        let generation = videoListenQueueSession.beginInitialLoad(
            source: source,
            anchor: anchor
        )
        do {
            let page = try await api.fetchUploaderVideoPage(mid: ownerMID, page: 1)
            guard !Task.isCancelled else {
                videoListenQueueSession.cancelLoading(generation: generation)
                return
            }
            guard playbackContentMode == .audioOnly,
                  VideoListenQueueBuilder.representsSameVideo(detail, anchor)
            else {
                videoListenQueueSession.cancelLoading(generation: generation)
                return
            }
            guard page.videos.contains(where: {
                !VideoListenQueueBuilder.representsSameVideo($0, anchor)
            }) else {
                PlayerMetricsLog.record(
                    .network,
                    metricsID: anchor.bvid,
                    title: anchor.title,
                    message: "listenQueue uploaderEmpty fallback=related"
                )
                await loadRelatedVideoListenQueue(anchor: anchor, generation: generation)
                return
            }
            guard videoListenQueueSession.finishInitialLoad(
                videos: page.videos,
                anchor: anchor,
                source: source,
                nextPage: 1,
                nextCursor: page.nextCursor,
                hasMore: page.hasMore,
                generation: generation
            ) else { return }
            PlayerMetricsLog.record(
                .network,
                metricsID: detail.bvid,
                title: detail.title,
                message: "listenQueue source=uploader count=\(videoListenQueueSession.videos.count) hasMore=\(page.hasMore)"
            )
            updateVideoListenRemoteNavigationAvailability()
            scheduleVideoListenContinuationPreload()
        } catch {
            guard !Task.isCancelled else {
                videoListenQueueSession.cancelLoading(generation: generation)
                return
            }
            PlayerMetricsLog.record(
                .network,
                metricsID: anchor.bvid,
                title: anchor.title,
                message: "listenQueue uploaderFailure=\(error.localizedDescription) fallback=related"
            )
            await loadRelatedVideoListenQueue(anchor: anchor, generation: generation)
        }
    }

    func selectVideoListenQueueEntry(_ entry: VideoListenQueueEntry) {
        guard playbackContentMode == .audioOnly,
              !isPlaybackInvalidatedForNavigation,
              !entry.isCurrent
        else { return }

        let shouldResumePlayback = currentPlaybackIntent()
        switch entry.target {
        case let .page(page):
            beginVideoListenAdvance(
                target: "p\(page.page ?? 0)",
                reason: .queueSelection,
                shouldAutoplay: shouldResumePlayback
            )
            selectPage(page)
        case let .video(video):
            beginVideoListenAdvance(
                target: VideoListenQueueBuilder.contentKey(for: video),
                reason: .queueSelection,
                shouldAutoplay: shouldResumePlayback
            )
            selectVideoListenQueueVideo(
                video,
                direction: .next,
                shouldAutoplay: shouldResumePlayback
            )
        case let .episode(video):
            beginVideoListenAdvance(
                target: "ep\(video.pgcEpisodeID ?? 0)",
                reason: .queueSelection,
                shouldAutoplay: shouldResumePlayback
            )
            selectPgcEpisode(video)
        }
    }

    func loadMoreVideoListenQueueIfNeeded(
        current entry: VideoListenQueueEntry,
        preferredDirection: VideoListenAdvanceDirection? = nil
    ) async {
        guard playbackContentMode == .audioOnly else { return }

        switch videoListenQueueSession.source {
        case .officialListener(let anchorAID, let sortOrder):
            await loadMoreOfficialVideoListenQueueIfNeeded(
                current: entry,
                anchorAID: anchorAID,
                sortOrder: sortOrder,
                preferredDirection: preferredDirection
            )
        case .uploader(let ownerMID):
            await loadMoreUploaderVideoListenQueueIfNeeded(current: entry, ownerMID: ownerMID)
        case .currentVideo, .pgcSeason, .related:
            return
        }
    }

    private func loadMoreUploaderVideoListenQueueIfNeeded(
        current entry: VideoListenQueueEntry,
        ownerMID: Int
    ) async {
        guard videoListenQueueEntries.suffix(5).contains(where: { $0.id == entry.id }),
              let generation = videoListenQueueSession.beginLoadMore()
        else { return }

        let nextPage = videoListenQueueSession.nextPage + 1
        let cursor = videoListenQueueSession.nextCursor
        do {
            let page = try await api.fetchUploaderVideoPage(
                mid: ownerMID,
                page: nextPage,
                cursor: cursor
            )
            guard !Task.isCancelled else {
                videoListenQueueSession.cancelLoading(generation: generation)
                return
            }
            guard playbackContentMode == .audioOnly,
                  case .uploader(let currentMID) = videoListenQueueSession.source,
                  currentMID == ownerMID
            else {
                videoListenQueueSession.cancelLoading(generation: generation)
                return
            }
            guard videoListenQueueSession.finishLoadMore(
                videos: page.videos,
                nextPage: nextPage,
                nextCursor: page.nextCursor,
                hasMore: page.hasMore,
                generation: generation
            ) else { return }
            updateVideoListenRemoteNavigationAvailability()
        } catch {
            if Task.isCancelled {
                videoListenQueueSession.cancelLoading(generation: generation)
            } else {
                videoListenQueueSession.failLoadMore(error.localizedDescription, generation: generation)
            }
        }
    }

    private func loadMoreOfficialVideoListenQueueIfNeeded(
        current entry: VideoListenQueueEntry,
        anchorAID: Int,
        sortOrder: VideoListenPlaylistSortOrder,
        preferredDirection: VideoListenAdvanceDirection?
    ) async {
        let entries = videoListenQueueEntries
        let isNearStart = entries.prefix(5).contains(where: { $0.id == entry.id })
        let isNearEnd = entries.suffix(5).contains(where: { $0.id == entry.id })

        let preferredPaginationDirection: VideoListenQueuePaginationDirection? = {
            switch preferredDirection {
            case .previous:
                return .previous
            case .next:
                return .next
            case nil:
                return nil
            }
        }()
        let candidates: [VideoListenQueuePaginationDirection] = {
            if let preferredPaginationDirection {
                return preferredPaginationDirection == .next
                    ? [.next, .previous]
                    : [.previous, .next]
            }
            return [.next]
        }()
        guard let direction = candidates.first(where: { direction in
            switch direction {
            case .previous:
                return isNearStart && videoListenQueueSession.listenerPreviousToken != nil
            case .next:
                return isNearEnd && videoListenQueueSession.listenerNextToken != nil
            }
        }) else { return }

        let cursor: String?
        switch direction {
        case .previous:
            cursor = videoListenQueueSession.listenerPreviousToken
        case .next:
            cursor = videoListenQueueSession.listenerNextToken
        }
        guard let cursor,
              let generation = videoListenQueueSession.beginLoadMore()
        else { return }

        do {
            let page = try await api.fetchOfficialVideoListenPlaylist(
                aid: anchorAID,
                cid: nil,
                cursor: cursor,
                sortOrder: sortOrder
            )
            guard !Task.isCancelled else {
                videoListenQueueSession.cancelLoading(generation: generation)
                return
            }
            guard playbackContentMode == .audioOnly,
                  case .officialListener(let currentAID, let currentOrder) = videoListenQueueSession.source,
                  currentAID == anchorAID,
                  currentOrder == sortOrder
            else {
                videoListenQueueSession.cancelLoading(generation: generation)
                return
            }
            guard videoListenQueueSession.finishLoadMore(
                videos: page.videos,
                nextPage: videoListenQueueSession.nextPage + 1,
                nextCursor: nil,
                hasMore: false,
                listenerDirection: direction,
                listenerPreviousToken: page.previousToken,
                listenerNextToken: page.nextToken,
                generation: generation
            ) else { return }
            PlayerMetricsLog.record(
                .network,
                metricsID: detail.bvid,
                title: detail.title,
                message: "listenQueue source=listener direction=\(direction.rawValue) added=\(page.videos.count) total=\(page.totalCount ?? -1) prev=\(videoListenQueueSession.listenerPreviousToken == nil ? 0 : 1) next=\(videoListenQueueSession.listenerNextToken == nil ? 0 : 1)"
            )
            updateVideoListenRemoteNavigationAvailability()
        } catch {
            if Task.isCancelled {
                videoListenQueueSession.cancelLoading(generation: generation)
            } else {
                videoListenQueueSession.failLoadMore(error.localizedDescription, generation: generation)
            }
        }
    }

    var videoListenQueueIsReadyForCurrentContext: Bool {
        guard !videoListenQueueSession.isLoadingInitial,
              videoListenQueueSession.errorMessage == nil
        else { return false }

        switch videoListenQueueSession.source {
        case .currentVideo:
            return false
        case .officialListener(_, let sortOrder):
            return sortOrder == libraryStore.videoListenPlaylistSortOrder
                && !detail.isPGCEpisode
                && videoListenQueueSession.videos.contains(where: {
                    VideoListenQueueBuilder.representsSameVideo($0, detail)
                })
        case .pgcSeason(let seasonID):
            return detail.isPGCEpisode && seasonID == detail.pgcSeasonID
        case .uploader(let ownerMID):
            return !detail.isPGCEpisode && ownerMID == detail.owner?.mid
        case .related:
            return videoListenQueueSession.videos.contains(where: {
                VideoListenQueueBuilder.representsSameVideo($0, detail)
            })
        }
    }

    func scheduleVideoListenQueuePreparation() {
        guard playbackContentMode == .audioOnly,
              !videoListenQueueIsReadyForCurrentContext,
              !isLoadingVideoListenQueue,
              videoListenQueueTask == nil
        else { return }

        videoListenQueueTaskGeneration &+= 1
        let taskGeneration = videoListenQueueTaskGeneration
        videoListenQueueTask = Task(priority: .utility) { @MainActor [weak self] in
            guard let self,
                  !Task.isCancelled,
                  self.videoListenQueueTaskGeneration == taskGeneration
            else { return }
            await self.prepareVideoListenQueue()
            guard self.videoListenQueueTaskGeneration == taskGeneration else { return }
            self.videoListenQueueTask = nil
        }
    }

    func cancelVideoListenQueueTasks(resetSession: Bool) {
        videoListenQueueTaskGeneration &+= 1
        videoListenQueueTask?.cancel()
        videoListenQueueTask = nil
        videoListenContentSwitchTask?.cancel()
        videoListenContentSwitchTask = nil
        if resetSession {
            videoListenQueueSession = VideoListenQueueSession(seedVideo: detail)
        } else {
            videoListenQueueSession.isLoadingInitial = false
            videoListenQueueSession.isLoadingMore = false
        }
    }

    private func loadRelatedVideoListenQueue(
        anchor: VideoItem,
        generation existingGeneration: UUID? = nil
    ) async {
        let source = VideoListenQueueSource.related(anchorBVID: anchor.bvid)
        let generation = existingGeneration ?? videoListenQueueSession.beginInitialLoad(
            source: source,
            anchor: anchor
        )

        do {
            let videos: [VideoItem]
            if related.isEmpty {
                videos = try await api.fetchVideoRelated(bvid: anchor.bvid)
            } else {
                videos = related
            }
            guard !Task.isCancelled else {
                videoListenQueueSession.cancelLoading(generation: generation)
                return
            }
            guard playbackContentMode == .audioOnly,
                  VideoListenQueueBuilder.representsSameVideo(detail, anchor)
            else {
                videoListenQueueSession.cancelLoading(generation: generation)
                return
            }
            guard videoListenQueueSession.finishInitialLoad(
                videos: videos,
                anchor: anchor,
                source: source,
                nextPage: 1,
                nextCursor: nil,
                hasMore: false,
                generation: generation
            ) else { return }
            updateVideoListenRemoteNavigationAvailability()
            scheduleVideoListenContinuationPreload()
        } catch {
            if Task.isCancelled {
                videoListenQueueSession.cancelLoading(generation: generation)
            } else {
                videoListenQueueSession.failInitialLoad(error.localizedDescription, generation: generation)
            }
            updateVideoListenRemoteNavigationAvailability()
        }
    }

    private func selectVideoListenQueueVideo(
        _ video: VideoItem,
        direction: VideoListenAdvanceDirection,
        shouldAutoplay: Bool
    ) {
        guard !VideoListenQueueBuilder.representsSameVideo(video, detail) else { return }
        if video.isPGCEpisode {
            selectPgcEpisode(video)
            return
        }

        let sourceBVID = detail.bvid
        let sourceCID = selectedCID
        let queueGeneration = videoListenQueueSession.generation
        let identity = videoListenLoadIdentity(for: video)
        videoListenContentSwitchTask?.cancel()
        videoListenContentSwitchTask = Task(priority: .userInitiated) { @MainActor [weak self] in
            guard let self else { return }
            do {
                let fullDetail = try await self.fetchFullDetail(
                    identity: identity,
                    priority: .userInitiated
                )
                guard !Task.isCancelled,
                      self.playbackContentMode == .audioOnly,
                      self.videoListenQueueSession.generation == queueGeneration,
                      self.isCurrentPlaybackContext(bvid: sourceBVID, cid: sourceCID)
                else { return }
                self.applyVideoListenContentSwitch(
                    fullDetail,
                    direction: direction,
                    shouldAutoplay: shouldAutoplay
                )
                self.videoListenContentSwitchTask = nil
            } catch {
                guard !Task.isCancelled else { return }
                self.videoListenContentSwitchTask = nil
                self.playbackFallbackMessage = "下一项载入失败：\(error.localizedDescription)"
                PlayerMetricsLog.record(
                    .network,
                    metricsID: self.detail.bvid,
                    title: self.detail.title,
                    message: "listenQueue contentFailure target=\(VideoListenQueueBuilder.contentKey(for: video)) error=\(error.localizedDescription)"
                )
            }
        }
    }

    private func videoListenLoadIdentity(for video: VideoItem) -> VideoDetailLoadIdentity {
        if video.bvid.hasPrefix("av"), let aid = video.aid, aid > 0 {
            return .aid(aid)
        }
        let bvid = video.bvid.trimmingCharacters(in: .whitespacesAndNewlines)
        if !bvid.isEmpty {
            return .bvid(bvid)
        }
        if let aid = video.aid, aid > 0 {
            return .aid(aid)
        }
        return .bvid(video.bvid)
    }

    private func applyVideoListenContentSwitch(
        _ video: VideoItem,
        direction: VideoListenAdvanceDirection,
        shouldAutoplay: Bool
    ) {
        guard playbackContentMode == .audioOnly,
              !isPlaybackTerminatedForNavigation
        else { return }

        saveCurrentPlaybackProgressBeforeContentSwitch()
        isPlaybackInvalidatedForNavigation = false
        cancelBackgroundTasks()
        detail = video
        let pages = video.pages ?? []
        selectedCID = direction == .previous
            ? (pages.last?.cid ?? video.cid)
            : (pages.first?.cid ?? video.cid)
        hasResolvedDetailMetadata = true
        manuallySelectedPageCID = nil
        didResolveCloudHistoryResume = true
        pendingPlaybackHistoryResumeTime = nil
        pendingPlaybackHistoryResumeCID = nil
        resumeDiagnostics = .none
        pendingVideoListenPlaybackIntent = shouldAutoplay
        videoListenQueueSession.replaceVideo(with: video)
        resetPlaybackStateForSelectedPage()
        resetInlineStateForContentSwitch()
        state = .loaded
        syncCommentsRenderStore()
        syncRelatedRenderStore()
        scheduleRelatedLoadIfNeeded()
        scheduleUploaderAndInteractionLoadIfNeeded()
        beginInitialCommentsLoadIfNeeded(waitForPlaybackStart: false)

        pageLoadingTask?.cancel()
        let token = UUID()
        pageLoadingToken = token
        pageLoadingTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            defer {
                self.clearPageLoadingTaskIfCurrent(token)
            }
            guard !Task.isCancelled,
                  !self.isPlaybackInvalidatedForNavigation,
                  VideoListenQueueBuilder.representsSameVideo(self.detail, video)
            else { return }
            await self.loadPlayURL()
        }
    }

    func setVideoListenSleepTimer(_ option: VideoListenSleepTimerOption) {
        guard option == .off || playbackContentMode == .audioOnly else { return }

        videoListenSleepTimerTask?.cancel()
        videoListenSleepTimerTask = nil
        videoListenSleepTimerOption = option
        videoListenSleepTimerDeadline = nil

        guard let durationMinutes = option.durationMinutes else { return }
        let deadline = Date().addingTimeInterval(TimeInterval(durationMinutes * 60))
        videoListenSleepTimerDeadline = deadline
        videoListenSleepTimerTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(
                    nanoseconds: UInt64(durationMinutes) * 60 * 1_000_000_000
                )
            } catch {
                return
            }
            guard let self,
                  self.playbackContentMode == .audioOnly,
                  self.videoListenSleepTimerOption == option,
                  self.videoListenSleepTimerDeadline == deadline
            else { return }
            self.stablePlayerViewModel?.pause()
            self.persistVideoListenPlaybackSession(wantsPlayback: false)
            self.videoListenSleepTimerTask = nil
            self.videoListenSleepTimerOption = .off
            self.videoListenSleepTimerDeadline = nil
            PlayerMetricsLog.record(
                .playbackRecovery,
                metricsID: self.detail.bvid,
                title: self.detail.title,
                message: "listenSleepTimer expired option=\(option.rawValue)"
            )
        }
    }

    func cancelVideoListenSleepTimer() {
        videoListenSleepTimerTask?.cancel()
        videoListenSleepTimerTask = nil
        videoListenSleepTimerOption = .off
        videoListenSleepTimerDeadline = nil
    }

    func handleVideoListenPlaybackEnded() {
        guard playbackContentMode == .audioOnly,
              !isPlaybackInvalidatedForNavigation
        else { return }

        let action = VideoListenPlaybackEndResolver.action(
            playbackOrder: libraryStore.videoListenPlaybackOrder,
            sleepTimerOption: videoListenSleepTimerOption
        )
        if videoListenSleepTimerOption == .endOfCurrent {
            cancelVideoListenSleepTimer()
        }

        switch action {
        case .advance:
            advanceVideoListenPlayback(direction: .next, reason: .playbackEnded)
        case .replayCurrent:
            persistVideoListenPlaybackSession(wantsPlayback: true)
            stablePlayerViewModel?.seek(to: 0)
            stablePlayerViewModel?.play()
        case .pause:
            persistVideoListenPlaybackSession(wantsPlayback: false)
            stablePlayerViewModel?.pause()
        }
    }

    func updateVideoListenRemoteNavigationAvailability(for player: PlayerStateViewModel? = nil) {
        let player = player ?? stablePlayerViewModel
        guard let player else { return }
        guard playbackContentMode == .audioOnly else {
            player.setTrackNavigationAvailability(hasPrevious: false, hasNext: false)
            return
        }

        let pages = detail.pages ?? []
        let hasPreviousPage = VideoListenSequenceResolver.page(
            in: pages,
            selectedCID: selectedCID,
            direction: .previous
        ) != nil
        let hasNextPage = VideoListenSequenceResolver.page(
            in: pages,
            selectedCID: selectedCID,
            direction: .next
        ) != nil
        let hasPreviousVideo = videoListenQueueSession.video(
            relativeTo: detail,
            direction: .previous
        ) != nil
        let hasNextVideo = videoListenQueueSession.video(
            relativeTo: detail,
            direction: .next
        ) != nil
        let hasPreviousListenerPage = videoListenQueueSession.listenerPreviousToken != nil
        let hasNextListenerPage = videoListenQueueSession.listenerNextToken != nil
        let canLoadQueue = !videoListenQueueIsReadyForCurrentContext
            && (
                detail.isPGCEpisode
                    || (detail.owner?.mid ?? 0) > 0
                    || ((detail.aid ?? 0) > 0 && (selectedCID ?? detail.cid ?? 0) > 0)
            )
        player.setTrackNavigationAvailability(
            hasPrevious: hasPreviousPage || hasPreviousVideo || hasPreviousListenerPage,
            hasNext: hasNextPage || hasNextVideo || hasNextListenerPage || canLoadQueue
        )
    }

    func scheduleVideoListenContinuationPreload() {
        guard playbackContentMode == .audioOnly,
              !isPlaybackInvalidatedForNavigation
        else { return }

        if let nextPage = VideoListenSequenceResolver.page(
            in: detail.pages ?? [],
            selectedCID: selectedCID,
            direction: .next
        ) {
            let bvid = detail.bvid
            let pageNumber = (nextPage.page ?? 1) > 1 ? nextPage.page : nil
            let preferredQuality = adaptiveStartupPreferredQuality
            let targetQuality = targetPlaybackPreferredQuality
            let cdnPreference = libraryStore.effectivePlaybackCDNPreference
            let adaptationProfile = playbackAdaptationProfile
            let api = api
            trackBackgroundTask(
                Task(priority: .utility) {
                    await VideoPreloadCenter.shared.preloadPlayInfo(
                        bvid: bvid,
                        cid: nextPage.cid,
                        page: pageNumber,
                        api: api,
                        preferredQuality: preferredQuality,
                        targetPreferredQuality: targetQuality,
                        cdnPreference: cdnPreference,
                        playbackAdaptationProfile: adaptationProfile
                    )
                }
            )
            updateVideoListenRemoteNavigationAvailability()
            return
        }

        guard let nextVideo = videoListenQueueSession.video(
            relativeTo: detail,
            direction: .next
        ) else {
            scheduleVideoListenQueuePreparation()
            updateVideoListenRemoteNavigationAvailability()
            return
        }

        if nextVideo.isPGCEpisode {
            let task = Task(priority: .utility) { [weak self] in
                guard let self else { return }
                await self.preloadVideoListenPgcEpisode(nextVideo)
            }
            trackBackgroundTask(task)
        } else {
            let preferredQuality = adaptiveStartupPreferredQuality
            let targetQuality = targetPlaybackPreferredQuality
            let cdnPreference = libraryStore.effectivePlaybackCDNPreference
            let adaptationProfile = playbackAdaptationProfile
            let api = api
            trackBackgroundTask(
                Task(priority: .utility) {
                    await VideoPreloadCenter.shared.preloadPlayInfo(
                        nextVideo,
                        api: api,
                        preferredQuality: preferredQuality,
                        targetPreferredQuality: targetQuality,
                        cdnPreference: cdnPreference,
                        priority: .utility,
                        warmsMedia: false,
                        mediaWarmupMode: .routePlanOnly,
                        mediaWarmupDelay: 0,
                        playbackAdaptationProfile: adaptationProfile
                    )
                }
            )
        }

        if let currentEntry = videoListenQueueEntries.first(where: \.isCurrent) {
            let task = Task(priority: .utility) { [weak self] in
                guard let self else { return }
                await self.loadMoreVideoListenQueueIfNeeded(current: currentEntry)
            }
            trackBackgroundTask(task)
        }
        updateVideoListenRemoteNavigationAvailability()
    }

    private func beginVideoListenAdvance(
        target: String,
        reason: VideoListenAdvanceReason,
        shouldAutoplay: Bool = true
    ) {
        pendingVideoListenPlaybackIntent = shouldAutoplay
        persistVideoListenPlaybackSession(wantsPlayback: shouldAutoplay)
        PlayerMetricsLog.record(
            .playbackRecovery,
            metricsID: detail.bvid,
            title: detail.title,
            message: "listenAdvance reason=\(reason.rawValue) target=\(target) autoplay=\(shouldAutoplay)"
        )
    }

    func captureVideoListenPlaybackIntentForContentSwitch() {
        guard playbackContentMode == .audioOnly else { return }
        let shouldResumePlayback = currentPlaybackIntent()
        pendingVideoListenPlaybackIntent = shouldResumePlayback
        persistVideoListenPlaybackSession(wantsPlayback: shouldResumePlayback)
    }

    func persistVideoListenPlaybackSession(wantsPlayback: Bool? = nil) {
        guard playbackContentMode == .audioOnly else { return }
        videoListenPlaybackSessionStore.save(
            VideoListenPlaybackSessionState(
                audioPreferenceKey: selectedVideoListenAudioPreferenceKey,
                wantsPlayback: wantsPlayback ?? currentPlaybackIntent()
            ),
            for: detail
        )
    }

    private func videoListenSeasonInfoIfNeeded() async -> PgcSeasonInfo? {
        let seasonID = detail.pgcSeasonID
        let episodeID = detail.pgcEpisodeID
        if let cached = videoListenPgcSeasonInfo,
           videoListenPgcSeasonID == seasonID {
            return cached
        }
        guard seasonID != nil || episodeID != nil else { return nil }
        do {
            let season = try await api.fetchPgcSeasonInfo(seasonID: seasonID, epID: episodeID)
            guard !Task.isCancelled,
                  playbackContentMode == .audioOnly,
                  detail.pgcSeasonID == seasonID
            else { return nil }
            videoListenPgcSeasonInfo = season
            videoListenPgcSeasonID = seasonID
            updateVideoListenRemoteNavigationAvailability()
            return season
        } catch {
            PlayerMetricsLog.record(
                .network,
                metricsID: detail.bvid,
                title: detail.title,
                message: "listenSeasonPreload failure=\(error.localizedDescription)"
            )
            return nil
        }
    }

    private func preloadVideoListenPgcEpisode(_ video: VideoItem) async {
        guard let cid = video.cid else { return }
        do {
            let data = try await api.fetchPgcPlayURL(
                bvid: video.bvid,
                cid: cid,
                seasonID: video.pgcSeasonID,
                epID: video.pgcEpisodeID,
                preferredQuality: adaptiveStartupPreferredQuality
            )
            guard !Task.isCancelled else { return }
            await VideoPreloadCenter.shared.store(
                data,
                bvid: video.bvid,
                cid: cid,
                page: nil,
                preferredQuality: adaptiveStartupPreferredQuality,
                targetPreferredQuality: targetPlaybackPreferredQuality,
                cdnPreference: libraryStore.effectivePlaybackCDNPreference,
                warmsMedia: false,
                mediaWarmupDelay: 0
            )
            PlayerMetricsLog.record(
                .manifestStage,
                metricsID: detail.bvid,
                title: detail.title,
                message: "listenNextAudioPreload ready target=ep\(video.pgcEpisodeID ?? 0)"
            )
        } catch {
            PlayerMetricsLog.record(
                .network,
                metricsID: detail.bvid,
                title: detail.title,
                message: "listenNextAudioPreload failure target=ep\(video.pgcEpisodeID ?? 0)"
            )
        }
    }
}

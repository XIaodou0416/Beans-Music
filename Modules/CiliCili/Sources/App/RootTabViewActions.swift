import SwiftUI

extension RootTabView {
    var shouldAutoOpenDetail: Bool {
        !didConsumeStartupVideo && shouldStartDetail && startBVID == nil
    }

    func openStartupVideoIfNeeded() {
        guard !didConsumeStartupVideo,
              let startBVID
        else { return }

        openVideo(Self.seedVideo(bvid: startBVID))
    }

    func openStartupLiveRoomIfNeeded() {
        guard !didConsumeStartupLiveRoom,
              let startLiveRoomID
        else { return }

        didConsumeStartupLiveRoom = true
        selectAvailableRootTab(.live)
        DispatchQueue.main.async {
            openLiveRoom(Self.seedLiveRoom(roomID: startLiveRoomID))
        }
    }

    func openStartupUploaderIfNeeded() {
        guard !didConsumeStartupUploader,
              let startUploaderMID,
              startUploaderMID > 0
        else { return }

        didConsumeStartupUploader = true
        selectAvailableRootTab(.home)
        DispatchQueue.main.async {
            openVideoOwnerRoute(Self.seedUploader(mid: startUploaderMID))
        }
    }

    func openAppURL(_ url: URL) {
        guard AppLinkRouter.canHandle(url) else { return }

        Task { @MainActor in
            let destination = await AppLinkRouter.destination(for: url, api: dependencies.api)
            routeAppLinkDestination(destination)
        }
    }

    func routeAppLinkDestination(_ destination: AppLinkDestination) {
        switch destination {
        case .video(let video):
            openVideo(video)
        case .videoComment(let route):
            openVideoComment(route)
        case .liveRoom(let room):
            openLiveRoomFromLink(room)
        case .user(let owner):
            openUserFromLink(owner)
        case .browser(let url):
            inAppBrowserItem = InAppBrowserItem(url: url)
        }
    }

    func openPgcSeasonRoute(_ route: PgcSeasonRoute) {
        pushRootRoute(route)
    }

    func openVideoOwnerRoute(_ owner: VideoOwner) {
        guard owner.mid > 0 else { return }
        AppOrientationLock.restorePortrait()
        pushRootRoute(owner)
    }

    private func pushRootRoute<Route: Hashable>(_ route: Route) {
        AppOrientationLock.restorePortrait()
        withAnimation(.smooth(duration: 0.30)) {
            appendActiveRootRoute(route)
        }
    }

    func openLiveRoomFromLink(_ room: LiveRoom) {
        selectAvailableRootTab(.live)
        openLiveRoom(room)
    }

    func openLiveRoom(_ room: LiveRoom) {
        AppOrientationLock.restorePortrait()
        if !activeRootNavigationPathIsEmpty {
            ActivePlaybackCoordinator.shared.stopActivePlayback()
        }
        withAnimation(.smooth(duration: 0.30)) {
            appendActiveRootRoute(room)
        }
    }

    func openUserFromLink(_ owner: VideoOwner) {
        openVideoOwnerRoute(owner)
    }

    func openMineOverlayRoute(_ route: MineOverlayRoute) {
        withAnimation(.smooth(duration: 0.30)) {
            appendActiveRootRoute(route)
        }
    }

    func openVideo(_ video: VideoItem) {
        AppOrientationLock.restorePortrait()
        PlayerMetricsLog.record(.routeOpen, metricsID: video.bvid, title: video.title)
        if libraryStore.videoDetailNavigationLatencyDiagnosticsEnabled {
            PlaybackDetailPerformanceMonitor.shared.beginNavigation(
                to: .video(video),
                detail: "source=openVideo \(VideoDetailFormalPerformancePolicy.navigationTraceDetail)"
            )
        }
        beginPlaybackPreload(for: video)
        if !activeRootNavigationPathIsEmpty {
            ActivePlaybackCoordinator.shared.pauseActivePlaybackForNavigation()
        }

        let opensFromStartup = shouldStartDetail && !didConsumeStartupVideo
        didConsumeStartupVideo = true
        let push = {
            appendActiveRootRoute(video)
        }
        if opensFromStartup {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction, push)
        } else {
            withAnimation(.smooth(duration: 0.30), push)
        }
    }

    func openVideoComment(_ route: VideoCommentRoute) {
        AppOrientationLock.restorePortrait()
        PlayerMetricsLog.record(.routeOpen, metricsID: route.video.bvid, title: route.video.title)
        if libraryStore.videoDetailNavigationLatencyDiagnosticsEnabled {
            PlaybackDetailPerformanceMonitor.shared.beginNavigation(
                to: .video(route.video),
                detail: "source=openVideoComment \(VideoDetailFormalPerformancePolicy.navigationTraceDetail)"
            )
        }
        beginPlaybackPreload(for: route.video)
        if !activeRootNavigationPathIsEmpty {
            ActivePlaybackCoordinator.shared.pauseActivePlaybackForNavigation()
        }

        let opensFromStartup = shouldStartDetail && !didConsumeStartupVideo
        didConsumeStartupVideo = true
        let push = {
            appendActiveRootRoute(route)
        }
        if opensFromStartup {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction, push)
        } else {
            withAnimation(.smooth(duration: 0.30), push)
        }
    }

    func beginPlaybackPreload(for video: VideoItem) {
        guard !video.bvid.isEmpty, !video.bvid.hasPrefix("av") else { return }
        guard !video.isPGCEpisode else { return }
        guard recentPlaybackPreloadGate.shouldBeginPreload(for: video.bvid) else { return }
        Task {
            let playbackAdaptationProfile = PlayerPerformanceStore.shared.playbackAdaptationProfile(
                for: video.bvid,
                isEnabled: dependencies.libraryStore.isPlaybackAutoOptimizationEnabled
            )
            let preferredQuality = dependencies.libraryStore.effectivePreferredVideoQuality
            let cdnPreference = dependencies.libraryStore.effectivePlaybackCDNPreference
            let api = dependencies.api
            await VideoPreloadCenter.shared.updatePlaybackPreferences(
                preferredQuality: preferredQuality,
                cdnPreference: cdnPreference,
                playbackAdaptationProfile: playbackAdaptationProfile
            )
            await VideoPreloadCenter.shared.prioritizePlayback(for: video)
            await VideoPreloadCenter.shared.preloadPlayInfo(
                video,
                api: api,
                preferredQuality: preferredQuality,
                cdnPreference: cdnPreference,
                priority: .userInitiated,
                warmsMedia: true,
                mediaWarmupMode: .full,
                mediaWarmupDelay: 0,
                playbackAdaptationProfile: playbackAdaptationProfile
            )
        }
    }

    func restoreVideoPlaybackUIForPictureInPicture(_ video: VideoItem) async -> Bool {
        AppOrientationLock.restorePortrait()

        beginPlaybackPreload(for: video)
        didConsumeStartupVideo = true
        var restoredPath = NavigationPath()
        restoredPath.append(video)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            replaceActiveRootNavigationPath(with: restoredPath)
        }

        await Task.yield()
        return activeRootNavigationPathCount == 1
    }
}

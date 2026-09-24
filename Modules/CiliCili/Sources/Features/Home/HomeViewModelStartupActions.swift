import Foundation
import SwiftUI

extension HomeViewModel {
    func loadInitial() async {
        guard videos.isEmpty else { return }
        updateLastSeenMarkerIndex(nil)
        updateFeed([])
        if mode != .recommend {
            restoreCachedVideosIfAvailable()
        }
        if videos.isEmpty {
            state = .loading
        }
        await refresh(resetCursor: true)
    }

    func switchMode(
        _ newMode: HomeFeedMode,
        using nativeRefreshAction: RefreshAction? = nil
    ) async {
        guard mode != newMode else { return }
        let previousMode = mode
        if previousMode == .recommend, !videos.isEmpty {
            retainedRecommendVideos = videos
            retainedRecommendLastSeenMarkerIndex = lastSeenMarkerIndex
        }
        mode = newMode
        updateLastSeenMarkerIndex(nil)
        updateFeed([])
        if newMode == .recommend, !retainedRecommendVideos.isEmpty {
            updateFeed(retainedRecommendVideos)
            updateLastSeenMarkerIndex(retainedRecommendLastSeenMarkerIndex)
            state = .loaded
        } else {
            restoreCachedVideosIfAvailable()
        }

        guard newMode.requiresRefreshAfterSwitch(
            from: previousMode,
            restoredContent: !videos.isEmpty
        ) else {
            requestRevision += 1
            cancelRecommendMetadataHydrationTasks()
            modeSwitchRefreshPending = false
            isRefreshing = false
            isUserRefreshing = false
            return
        }

        guard !Task.isCancelled else { return }
        if let nativeRefreshAction {
            modeSwitchRefreshPending = true
            defer { modeSwitchRefreshPending = false }
            await nativeRefreshAction()
            return
        }

        await refresh(resetCursor: true)
    }

    func reloadForRecommendContextChange() async {
        retainedRecommendVideos.removeAll()
        retainedRecommendLastSeenMarkerIndex = nil
        guard mode == .recommend else { return }
        updateLastSeenMarkerIndex(nil)
        updateFeed([])
        restoreCachedVideosIfAvailable()
        await refresh(resetCursor: true)
    }
}

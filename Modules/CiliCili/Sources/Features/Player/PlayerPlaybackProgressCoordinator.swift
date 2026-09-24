import Combine
import Foundation
import OSLog
import UIKit

struct PlayerPlaybackProgressContext {
    let dependencies: AppDependencies
    let libraryStore: LibraryStore
    let historyVideo: VideoItem?
    let historyCID: Int?
    let historyDuration: TimeInterval?
    let durationHint: TimeInterval?
    let playerDuration: TimeInterval?
}

@MainActor
final class PlayerPlaybackProgressCoordinator: ObservableObject {
    private let logger = Logger(subsystem: "cc.bili", category: "PlaybackProgress")
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var progressSaveTask: Task<Void, Never>?
    private var backgroundTaskEndTask: Task<Void, Never>?
    private var backgroundTaskGeneration = 0

    func saveProgress(
        _ time: TimeInterval,
        context: PlayerPlaybackProgressContext
    ) {
        guard !context.libraryStore.incognitoModeEnabled else { return }
        let minimumProgress = TimeInterval(context.libraryStore.playbackHistorySyncThresholdSeconds)
        guard time.isFinite, time >= minimumProgress else { return }
        guard let historyVideo = context.historyVideo else { return }
        let bvid = historyVideo.bvid.trimmingCharacters(in: .whitespacesAndNewlines)
        let aid = historyVideo.aid
        guard aid != nil || !bvid.isEmpty else {
            logger.error("progressReport skipped missing video identity time=\(Int(time), privacy: .public)")
            return
        }
        let duration = context.historyDuration ?? context.durationHint ?? context.playerDuration
        context.libraryStore.recordPlaybackProgress(
            video: historyVideo,
            cid: context.historyCID ?? historyVideo.cid,
            progress: time,
            duration: duration
        )
        HomeRecommendFeedbackCenter.shared.recordPlayProgress(
            video: historyVideo,
            progress: time,
            duration: duration
        )
        progressSaveTask?.cancel()
        progressSaveTask = Task {
            do {
                try await context.dependencies.api.reportVideoHistory(
                    aid: aid,
                    cid: context.historyCID ?? historyVideo.cid,
                    progress: time,
                    duration: duration,
                    bvid: bvid
                )
            } catch is CancellationError {
                return
            } catch {
                logger.error("progressReport failed aid=\(aid ?? 0, privacy: .public) time=\(Int(time), privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func saveProgressInBackground(
        currentTime: TimeInterval,
        context: PlayerPlaybackProgressContext
    ) {
        endBackgroundTaskIfNeeded()
        backgroundTaskGeneration += 1
        let generation = backgroundTaskGeneration
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "cc.bili.player.progress") {
            Task { @MainActor [weak self] in
                self?.endBackgroundTaskIfNeeded()
            }
        }
        saveProgress(currentTime, context: context)
        backgroundTaskEndTask?.cancel()
        backgroundTaskEndTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let self,
                  !Task.isCancelled,
                  self.backgroundTaskGeneration == generation
            else { return }
            self.endBackgroundTaskIfNeeded()
        }
    }

    func endBackgroundTaskIfNeeded() {
        backgroundTaskEndTask?.cancel()
        backgroundTaskEndTask = nil
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    deinit {
        progressSaveTask?.cancel()
        backgroundTaskEndTask?.cancel()
        if backgroundTaskID != .invalid {
            let backgroundTaskID = backgroundTaskID
            Task { @MainActor in
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
            }
        }
    }
}

import Foundation

@MainActor
final class PictureInPictureRestoreCoordinator {
    static let shared = PictureInPictureRestoreCoordinator()

    var restoreHandler: ((VideoItem) async -> Bool)?
    private var pendingRestore: PendingRestore?

    private init() {}

    func restorePlaybackUI(for video: VideoItem) async -> Bool {
        if let pendingRestore, pendingRestore.videoID == video.id {
            return await pendingRestore.task.value
        }
        guard let restoreHandler else { return false }

        let token = UUID()
        let task = Task { @MainActor in
            await restoreHandler(video)
        }
        pendingRestore = PendingRestore(videoID: video.id, token: token, task: task)
        let didRestore = await task.value
        if pendingRestore?.token == token {
            pendingRestore = nil
        }
        return didRestore
    }

    private struct PendingRestore {
        let videoID: String
        let token: UUID
        let task: Task<Bool, Never>
    }
}

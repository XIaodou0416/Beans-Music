import Foundation

extension VideoDetailViewModel {
    func cancelStartupPlayURLTask() {
        startupPlayURLRequestLease?.invalidate()
        startupPlayURLTask?.cancel()
        startupPlayURLTask = nil
        startupPlayURLTaskKey = nil
        startupPlayURLRequestLease = nil
        advanceStartupPlayURLGeneration()
    }

    func startupPlayURL(
        bvid: String,
        cid: Int,
        page: Int?
    ) async throws -> PlayURLData {
        let adaptiveQuality = adaptiveStartupPreferredQuality
        let streamSource = libraryStore.playbackStreamSourcePreference
        let key = [
            bvid,
            String(cid),
            page.map(String.init) ?? "-",
            "q\(adaptiveQuality ?? 0)",
            streamSource.cachePlatform
        ].joined(separator: "|")
        if startupPlayURLTaskKey == key, let startupPlayURLTask {
            let data = try await waitForStartupPlayURLTask(
                startupPlayURLTask,
                requestLease: startupPlayURLRequestLease
            )
            guard isCurrentPlaybackContext(bvid: bvid, cid: cid, page: page),
                  StartupPlayURLFeedbackEligibility.allows(startupPlayURLRequestLease)
            else { throw CancellationError() }
            return data
        }

        startupPlayURLRequestLease?.invalidate()
        startupPlayURLTask?.cancel()
        let startupGeneration = advanceStartupPlayURLGeneration()
        let requestLease = StartupPlayURLRequestLease()
        let task = Task(priority: .userInitiated) { [weak self] in
            guard let self else { throw CancellationError() }
            guard self.isCurrentPlaybackContext(bvid: bvid, cid: cid, page: page),
                  self.startupPlayURLGeneration == startupGeneration,
                  requestLease.isActive
            else { throw CancellationError() }
            let data = try await self.fetchStartupPlayURL(
                bvid: bvid,
                cid: cid,
                page: page,
                requestLease: requestLease
            )
            try Task.checkCancellation()
            guard self.isCurrentPlaybackContext(bvid: bvid, cid: cid, page: page),
                  self.startupPlayURLGeneration == startupGeneration,
                  requestLease.isActive
            else { throw CancellationError() }
            return data
        }
        startupPlayURLTask = task
        startupPlayURLTaskKey = key
        startupPlayURLRequestLease = requestLease
        defer {
            clearStartupPlayURLTaskIfCurrent(key: key, generation: startupGeneration)
        }

        let data = try await waitForStartupPlayURLTask(task, requestLease: requestLease)
        guard isCurrentPlaybackContext(bvid: bvid, cid: cid, page: page),
              startupPlayURLGeneration == startupGeneration,
              requestLease.isActive
        else { throw CancellationError() }
        return data
    }

    private func waitForStartupPlayURLTask(
        _ task: Task<PlayURLData, Error>,
        requestLease: StartupPlayURLRequestLease?
    ) async throws -> PlayURLData {
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            requestLease?.invalidate()
            task.cancel()
        }
    }
}

import Foundation
import OSLog
import QuartzCore

extension BiliAPIClient {
    nonisolated func logPlayURLStage(
        _ stage: String,
        bvid: String,
        cid: Int,
        start: CFTimeInterval,
        data: PlayURLData? = nil,
        error: Error? = nil
    ) {
        let elapsed = PlayerMetricsLog.elapsedMilliseconds(since: start)
        let variants = data?.playVariants ?? []
        let playableVariants = variants.filter(\.isPlayable)
        let qualities =
            playableVariants
            .map { "\($0.quality)\($0.audioURL == nil ? "p" : "d")" }
            .joined(separator: ",")
        let qualitySummary = qualities.isEmpty ? "-" : qualities
        let rawSummary = data?.rawPlayURLSummary ?? "-"
        let errorMessage = error?.localizedDescription ?? ""

        if error != nil {
            PlayerMetricsLog.logger.error(
                "playURLStage stage=\(stage, privacy: .public) bvid=\(bvid, privacy: .public) cid=\(cid, privacy: .public) elapsedMs=\(elapsed, format: .fixed(precision: 1), privacy: .public) error=\(errorMessage, privacy: .public)"
            )
        } else {
            PlayerMetricsLog.logger.info(
                "playURLStage stage=\(stage, privacy: .public) bvid=\(bvid, privacy: .public) cid=\(cid, privacy: .public) elapsedMs=\(elapsed, format: .fixed(precision: 1), privacy: .public) variants=\(variants.count, privacy: .public) playable=\(playableVariants.count, privacy: .public) highest=\(data?.highestPlayableQuality ?? 0, privacy: .public) durl=\((data?.durl?.isEmpty == false), privacy: .public) dash=\((data?.dash?.video?.isEmpty == false), privacy: .public) qualities=\(qualitySummary, privacy: .public) raw=\(rawSummary, privacy: .public)"
            )
        }
    }

    func clearCachedPlayURLFailures(bvid: String) async {
        await state.clearPlayURLFailuresAndTasks(containing: bvid)
    }

    func clearPlaybackPerformanceTestState(bvid: String) async {
        await state.clearPlayURLFailuresAndTasks(containing: bvid)
        await state.clearVideoDetailTasks(containing: bvid)
    }

    func cachedPlayablePlayURLFallback(bvid: String, cid: Int) async -> PlayURLData? {
        let context = await playbackAPIRequestContext()
        let scope = PlayURLCacheLoginScope(
            isLoggedIn: context.isLoggedIn,
            userMID: context.currentUserMID,
            guestModeEnabled: context.guestModeEnabled,
            credentialVersion: context.playbackCredentialVersion
        )
        guard
            let data = await playURLCache.playableFallback(
                bvid: bvid,
                cid: cid,
                platform: nil,
                scope: scope
            )
        else { return nil }
        return await applyingConfiguredHistoryAccount(
            to: data,
            playbackUserMID: context.currentUserMID
        )
    }

    func cachedPlayURL(
        for key: PlayURLCacheKey,
        scope: PlayURLCacheLoginScope,
        requiredQuality: Int
    ) async -> PlayURLData? {
        await playURLCache.value(
            for: key,
            scope: scope,
            requiredQuality: requiredQuality
        )
    }

    func fetchPlayURLWithPendingRequest(
        cacheKey: PlayURLCacheKey,
        scope: PlayURLCacheLoginScope,
        bvid: String,
        cid: Int,
        requestedQuality: Int,
        source: String,
        cachePlatform: String,
        isStartup: Bool,
        operation: @escaping () async throws -> PlayURLData
    ) async throws -> PlayURLData {
        let coordinatorStart = CACurrentMediaTime()
        let pendingKey = PendingPlayURLRequestKey(cacheKey: cacheKey, scope: scope)
        if let existingRequest = await state.pendingPlayURLRequest(for: pendingKey) {
            PlayerMetricsLog.logger.info(
                "playURLRequestJoined source=\(source, privacy: .public) bvid=\(bvid, privacy: .public) cid=\(cid, privacy: .public) qn=\(requestedQuality, privacy: .public)"
            )
            return try await awaitPendingPlayURLRequest(
                existingRequest.task,
                role: "joined",
                source: source,
                bvid: bvid,
                cid: cid,
                requestID: existingRequest.id,
                requestedQuality: requestedQuality,
                isStartup: isStartup,
                coordinatorStart: coordinatorStart
            )
        }

        let requestID = UUID()
        let startGate = PendingPlayURLRequestStartGate()
        let task = Task<PlayURLData, Error>(priority: .userInitiated) {
            await startGate.wait()
            do {
                try Task.checkCancellation()
                let data = try await operation()
                let storageKey: PlayURLCacheKey
                if data.hasPlayableMediaQuality(requestedQuality) {
                    storageKey = cacheKey
                } else if let actualQuality = Self.startupCandidateQuality(
                    in: data,
                    requestedQuality: requestedQuality
                ), actualQuality < requestedQuality {
                    if isStartup,
                        PiliPlusStylePlayURLSelectionExperiment.stored(),
                        Self.canUseUnavailablePreferredStartupFallback(
                            data,
                            requestedQuality: requestedQuality,
                            isAuthoritativeSource: true
                        )
                    {
                        storageKey = cacheKey
                    } else {
                        storageKey = PlayURLCacheKey(
                            bvid: bvid,
                            cid: cid,
                            requestedQuality: actualQuality,
                            audioLanguage: cacheKey.audioLanguage,
                            fnval: cacheKey.fnval,
                            fnver: cacheKey.fnver,
                            platform: Self.playURLCachePlatform(
                                cachePlatform,
                                requestedQuality: actualQuality,
                                isStartup: isStartup
                            )
                        )
                    }
                } else {
                    storageKey = cacheKey
                }
                await self.playURLCache.store(data, for: storageKey, scope: scope)
                await self.state.clearPendingPlayURLRequest(for: pendingKey, id: requestID)
                return data
            } catch {
                await self.state.clearPendingPlayURLRequest(for: pendingKey, id: requestID)
                throw error
            }
        }
        let request = PendingPlayURLRequest(id: requestID, task: task)
        if let existingRequest = await state.insertPendingPlayURLRequestIfAbsent(request, for: pendingKey) {
            task.cancel()
            await startGate.open()
            PlayerMetricsLog.logger.info(
                "playURLRequestJoinedAfterRace source=\(source, privacy: .public) bvid=\(bvid, privacy: .public) cid=\(cid, privacy: .public) qn=\(requestedQuality, privacy: .public)"
            )
            return try await awaitPendingPlayURLRequest(
                existingRequest.task,
                role: "raceJoined",
                source: source,
                bvid: bvid,
                cid: cid,
                requestID: existingRequest.id,
                requestedQuality: requestedQuality,
                isStartup: isStartup,
                coordinatorStart: coordinatorStart
            )
        }

        await startGate.open()
        return try await awaitPendingPlayURLRequest(
            task,
            role: "owner",
            source: source,
            bvid: bvid,
            cid: cid,
            requestID: requestID,
            requestedQuality: requestedQuality,
            isStartup: isStartup,
            coordinatorStart: coordinatorStart
        )
    }

    private func awaitPendingPlayURLRequest(
        _ task: Task<PlayURLData, Error>,
        role: String,
        source: String,
        bvid: String,
        cid: Int,
        requestID: UUID,
        requestedQuality: Int,
        isStartup: Bool,
        coordinatorStart: CFTimeInterval
    ) async throws -> PlayURLData {
        let lookupMilliseconds = Int(PlayerMetricsLog.elapsedMilliseconds(since: coordinatorStart).rounded())
        let waitStart = CACurrentMediaTime()
        do {
            let data = try await Self.awaitSharedTask(task)
            recordPendingPlayURLRequestDiagnostic(
                role: role,
                source: source,
                bvid: bvid,
                cid: cid,
                requestID: requestID,
                requestedQuality: requestedQuality,
                isStartup: isStartup,
                result: "success",
                lookupMilliseconds: lookupMilliseconds,
                waitStart: waitStart,
                coordinatorStart: coordinatorStart
            )
            return data
        } catch {
            let result =
                error is CancellationError
                    || (error as? URLError)?.code == .cancelled
                ? "cancelled"
                : "failure"
            recordPendingPlayURLRequestDiagnostic(
                role: role,
                source: source,
                bvid: bvid,
                cid: cid,
                requestID: requestID,
                requestedQuality: requestedQuality,
                isStartup: isStartup,
                result: result,
                lookupMilliseconds: lookupMilliseconds,
                waitStart: waitStart,
                coordinatorStart: coordinatorStart
            )
            throw error
        }
    }

    private func recordPendingPlayURLRequestDiagnostic(
        role: String,
        source: String,
        bvid: String,
        cid: Int,
        requestID: UUID,
        requestedQuality: Int,
        isStartup: Bool,
        result: String,
        lookupMilliseconds: Int,
        waitStart: CFTimeInterval,
        coordinatorStart: CFTimeInterval
    ) {
        guard isStartup else { return }
        let waitMilliseconds = Int(PlayerMetricsLog.elapsedMilliseconds(since: waitStart).rounded())
        let totalMilliseconds = Int(PlayerMetricsLog.elapsedMilliseconds(since: coordinatorStart).rounded())
        let message =
            "playURLPending source=\(source) role=\(role) request=\(requestID.uuidString.prefix(8)) cid=\(cid) result=\(result) q=\(requestedQuality) lookup=\(lookupMilliseconds)ms wait=\(waitMilliseconds)ms total=\(totalMilliseconds)ms"
        Task(priority: .utility) { [self] in
            await recordStartupSchedulerMessage(message, bvid: bvid)
        }
    }

    func hasCachedStartupPlayURL(
        bvid: String,
        cid: Int,
        preferredQuality: Int? = nil
    ) async -> Bool {
        let context = await playbackAPIRequestContext()
        let configuredQuality = preferredQuality ?? context.effectivePreferredVideoQuality
        let requestedQuality = configuredQuality ?? LibraryStore.defaultPreferredVideoQuality
        let key = PlayURLCacheKey(
            bvid: bvid,
            cid: cid,
            requestedQuality: requestedQuality,
            audioLanguage: "default",
            fnval: "4048",
            fnver: "0",
            platform: Self.playURLCachePlatform(
                context.playbackStreamSourcePreference.cachePlatform,
                requestedQuality: requestedQuality,
                isStartup: true
            )
        )
        let scope = PlayURLCacheLoginScope(
            isLoggedIn: context.isLoggedIn,
            userMID: context.currentUserMID,
            guestModeEnabled: context.guestModeEnabled,
            credentialVersion: context.playbackCredentialVersion
        )
        return await playURLCache.contains(
            key,
            scope: scope,
            requiredQuality: requestedQuality,
            allowsVerifiedLowerQualityFallback: PiliPlusStylePlayURLSelectionExperiment.stored()
        )
    }

    nonisolated static func playURLCachePlatform(
        _ basePlatform: String,
        requestedQuality: Int?,
        isStartup: Bool = false
    ) -> String {
        let base = isStartup ? "startup-\(basePlatform)" : basePlatform
        let selectionStrategy: String
        if isStartup && PiliPlusStylePlayURLSelectionExperiment.stored() {
            selectionStrategy = PiliPlusStylePlayURLSelectionExperiment.currentStrategyKey
        } else {
            selectionStrategy = "strictTargetQualityV1"
        }
        return "\(base)-\(selectionStrategy)-\(playURLCodecCachePolicyToken(requestedQuality: requestedQuality))"
    }

    nonisolated static func playURLCodecCachePolicyToken(requestedQuality: Int?) -> String {
        let preference = VideoCodecPreference.stored()
        let policy: String
        if requestedQuality.map({ Self.requiresAutomaticCodecNegotiation(requestedQuality: $0) }) == true {
            policy = "hdrAutoStrictV2"
        } else if preference.codecOrder.first == .av1, PlaybackCodecPolicy.canDecodeAV1 {
            policy = "av1FirstHardwareV1"
        } else {
            policy = "hevcFirstV2"
        }
        return "codec-\(preference.rawValue)-\(policy)"
    }

    func runCachedPlayURLStage(
        _ stage: String,
        bvid: String,
        cid: Int,
        qn: Int,
        cookieMode: String,
        credentialVersion: Int,
        start: CFTimeInterval,
        operation: @escaping () async throws -> PlayURLData
    ) async throws -> PlayURLData {
        let cacheKey = Self.playURLFailureCacheKey(
            stage: stage,
            bvid: bvid,
            cid: cid,
            qn: qn,
            cookieMode: cookieMode,
            credentialVersion: credentialVersion
        )
        if let cachedFailure = await state.cachedPlayURLFailure(for: cacheKey) {
            logPlayURLStage("\(stage)CachedFailure", bvid: bvid, cid: cid, start: start, error: cachedFailure)
            throw cachedFailure
        }
        if let existingTask = await state.playURLStageTask(for: cacheKey) {
            logPlayURLStage("\(stage)Joined", bvid: bvid, cid: cid, start: start)
            return try await Self.awaitSharedTask(existingTask.task)
        }

        let requestID = UUID()
        let startGate = PendingPlayURLRequestStartGate()
        let task = Task<PlayURLData, Error>(priority: .userInitiated) {
            await startGate.wait()
            try Task.checkCancellation()
            return try await operation()
        }
        let request = PendingPlayURLStageRequest(id: requestID, task: task)
        if let existingTask = await state.insertPlayURLStageTaskIfAbsent(request, for: cacheKey) {
            task.cancel()
            await startGate.open()
            logPlayURLStage("\(stage)JoinedAfterRace", bvid: bvid, cid: cid, start: start)
            return try await Self.awaitSharedTask(existingTask.task)
        }
        await startGate.open()
        Task(priority: .utility) { [self] in
            do {
                _ = try await task.value
                await state.clearPlayURLStageTask(for: cacheKey, id: requestID)
            } catch {
                await state.clearPlayURLStageTask(for: cacheKey, id: requestID)
                logPlayURLStage(stage, bvid: bvid, cid: cid, start: start, error: error)
                await state.storePlayURLFailure(error, for: cacheKey)
            }
        }
        return try await Self.awaitSharedTask(task)
    }

    nonisolated static func playURLFailureCacheKey(
        stage: String,
        bvid: String,
        cid: Int,
        qn: Int,
        cookieMode: String,
        credentialVersion: Int
    ) -> String {
        "\(stage)|\(bvid)|\(cid)|\(qn)|\(cookieMode)|credential=\(credentialVersion)"
    }

    nonisolated static func cacheablePlayURLFailure(_ error: Error) -> BiliAPIError? {
        guard !(error is CancellationError), let biliError = error as? BiliAPIError else { return nil }

        switch biliError {
        case .api(let code, _) where code == -351:
            return biliError
        default:
            return nil
        }
    }

    nonisolated static func playURLFailureTTL(for error: BiliAPIError) -> CFTimeInterval {
        switch error {
        case .api(let code, _) where code == -351:
            return 45
        case .emptyPlayURL:
            return 10
        default:
            return 6
        }
    }
}

private actor PendingPlayURLRequestStartGate {
    private var isOpen = false
    private var waiters = [CheckedContinuation<Void, Never>]()

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            if isOpen {
                continuation.resume()
            } else {
                waiters.append(continuation)
            }
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let pendingWaiters = waiters
        waiters.removeAll()
        for waiter in pendingWaiters {
            waiter.resume()
        }
    }
}

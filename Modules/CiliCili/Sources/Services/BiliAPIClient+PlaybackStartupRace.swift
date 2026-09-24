import Foundation
import QuartzCore

extension BiliAPIClient {
    nonisolated static func startupWBIRouteHintKey(
        bvid: String,
        cid: Int,
        requestedQuality: Int,
        accountMID: Int?,
        credentialVersion: Int
    ) -> StartupWBIRouteHintKey {
        StartupWBIRouteHintKey(
            bvid: bvid,
            cid: cid,
            requestedQuality: requestedQuality,
            accountMID: accountMID,
            credentialVersion: credentialVersion
        )
    }

    func fetchRacedStartupPlayURL(
        bvid: String,
        cid: Int,
        page: Int?,
        requestedQuality: Int,
        requestLease: StartupPlayURLRequestLease?,
        requestSource: StartupPlayURLRequestSource
    ) async throws -> StartupPlayURLRaceResult? {
        let raceStart = CACurrentMediaTime()
        let suppressionStatus = await startupWBISuppressionStatus()
        let piliPlusStyleEnabled = PiliPlusStylePlayURLSelectionExperiment.stored()
        let routeHint: StartupWBIRouteHint?
        if piliPlusStyleEnabled {
            let context = await playbackAPIRequestContext()
            routeHint = await state.startupWBIRouteHint(
                for: Self.startupWBIRouteHintKey(
                    bvid: bvid,
                    cid: cid,
                    requestedQuality: requestedQuality,
                    accountMID: context.currentUserMID,
                    credentialVersion: context.playbackCredentialVersion
                )
            )
        } else {
            routeHint = nil
        }
        let shouldRaceWBI = suppressionStatus == nil && routeHint != .webpageOnly
        let playbackEnvironment = PlaybackEnvironment.current
        let startupGrace = playbackEnvironment.preferredPlayURLStartupGrace
        let schedulingDecision = await StartupPlayURLRoutePerformanceStore.shared.decision(
            networkClass: playbackEnvironment.networkClass,
            wbiAvailable: shouldRaceWBI
        ).preferringWBIForPiliPlus(
            piliPlusStyleEnabled: piliPlusStyleEnabled,
            wbiAvailable: shouldRaceWBI
        )
        let routingPlan = StartupPlayURLRoutingPlan(
            schedulingDecision: schedulingDecision,
            shouldRaceWBI: shouldRaceWBI,
            piliPlusStyleEnabled: piliPlusStyleEnabled
        )
        let schedulerBaseMessage =
            shouldRaceWBI
            ? schedulingDecision.diagnosticMessage(
                piliPlusStyleEnabled: piliPlusStyleEnabled
            )
            : startupWBISuppressionMessage(
                mode: "adaptive",
                suppressionStatus: suppressionStatus,
                routeHint: routeHint
            )
        let schedulerMessage =
            piliPlusStyleEnabled
            ? "\(schedulerBaseMessage) strategy=\(PiliPlusStylePlayURLSelectionExperiment.currentStrategyKey) routeHint=\(routeHint?.rawValue ?? "none")"
            : schedulerBaseMessage
        if recordsStartupSchedulerFeedback(
            requestSource: requestSource,
            requestLease: requestLease
        ) {
            await recordStartupSchedulerMessage(schedulerMessage, bvid: bvid)
        }
        var bestStartupResult: StartupPlayURLRaceResult?
        var lastError: Error?
        let fallbackTracker =
            routingPlan.usesStaggeredFallback
            ? StartupPlayURLFallbackTracker(
                initialStatus: routingPlan.defersWebpageFallbackUntilWBIFailure ? .deferred : .waiting
            )
            : nil
        let webpageHedge =
            routingPlan.startsWebpageHedge
            ? makePiliPlusWebpageHedge(
                bvid: bvid,
                page: page,
                delayNanoseconds: PiliPlusStylePlayURLSelectionExperiment.webpageHedgeDelayNanoseconds
            )
            : nil
        defer { webpageHedge?.task.cancel() }

        return await withTaskGroup(of: StartupPlayURLAttempt.self, returning: StartupPlayURLRaceResult?.self) { group in
            if routingPlan.usesStaggeredFallback,
                let primaryRoute = schedulingDecision.primaryRoute,
                let fallbackRoute = schedulingDecision.fallbackRoute
            {
                group.addTask(priority: .userInitiated) {
                    await self.startupPlayURLAttempt(
                        route: primaryRoute,
                        bvid: bvid,
                        cid: cid,
                        page: page,
                        requestedQuality: requestedQuality
                    )
                }
                if !routingPlan.defersWebpageFallbackUntilWBIFailure {
                    group.addTask(priority: .utility) {
                        do {
                            try await Task.sleep(
                                nanoseconds: PlaybackStartupRequestSchedulingPolicy.staggeredFallbackDelayNanoseconds
                            )
                        } catch {
                            await fallbackTracker?.markCancelledBeforeStart()
                            return StartupPlayURLAttempt(
                                stage: "startupFallbackCancelled",
                                route: nil,
                                elapsedMilliseconds: nil,
                                data: nil,
                                error: nil,
                                isAuthoritativePlayURLSource: false
                            )
                        }
                        guard !Task.isCancelled else {
                            await fallbackTracker?.markCancelledBeforeStart()
                            return StartupPlayURLAttempt(
                                stage: "startupFallbackCancelled",
                                route: nil,
                                elapsedMilliseconds: nil,
                                data: nil,
                                error: nil,
                                isAuthoritativePlayURLSource: false
                            )
                        }
                        await fallbackTracker?.markStarted()
                        return await self.startupPlayURLAttempt(
                            route: fallbackRoute,
                            bvid: bvid,
                            cid: cid,
                            page: page,
                            requestedQuality: requestedQuality
                        )
                    }
                }
            } else {
                if startupGrace > 0 {
                    group.addTask(priority: .userInitiated) {
                        try? await Task.sleep(nanoseconds: startupGrace)
                        return StartupPlayURLAttempt(
                            stage: "startupRaceTimeout",
                            route: nil,
                            elapsedMilliseconds: nil,
                            data: nil,
                            error: nil,
                            isAuthoritativePlayURLSource: false
                        )
                    }
                }

                group.addTask(priority: .userInitiated) {
                    await self.startupPlayURLAttempt(
                        route: .webpage,
                        bvid: bvid,
                        cid: cid,
                        page: page,
                        requestedQuality: requestedQuality
                    )
                }

                if routingPlan.shouldRaceWBI {
                    group.addTask(priority: .userInitiated) {
                        await self.startupPlayURLAttempt(
                            route: .wbi,
                            bvid: bvid,
                            cid: cid,
                            page: page,
                            requestedQuality: requestedQuality
                        )
                    }
                }
            }

            while let attempt = await group.next() {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    return nil
                }

                if attempt.stage == "startupRaceTimeout" {
                    logPlayURLStage(
                        "startupRaceGraceExpired",
                        bvid: bvid,
                        cid: cid,
                        start: raceStart
                    )
                    continue
                }
                if attempt.stage == "startupFallbackCancelled" {
                    continue
                }

                var shouldStartDeferredWebpageFallback = false
                if let data = attempt.data {
                    let result = StartupPlayURLRaceResult(
                        data: data,
                        isVerifiedUnavailablePreferredFallback: Self.canUseUnavailablePreferredStartupFallback(
                            data,
                            requestedQuality: requestedQuality,
                            isAuthoritativeSource: attempt.isAuthoritativePlayURLSource
                        )
                    )
                    let hasRequestedMedia = data.hasPlayableMediaQuality(requestedQuality)
                    let acceptsRequestedQuality =
                        hasRequestedMedia
                        || result.isVerifiedUnavailablePreferredFallback
                    if recordsStartupSchedulerFeedback(
                        requestSource: requestSource,
                        requestLease: requestLease
                    ) {
                        await recordStartupRouteAttempt(
                            attempt,
                            accepted: acceptsRequestedQuality,
                            networkClass: playbackEnvironment.networkClass,
                            requestLease: requestLease
                        )
                        if attempt.route == .wbi {
                            await recordStartupWBISuccess(bvid: bvid)
                        }
                    }
                    bestStartupResult = preferredStartupRaceCandidate(
                        bestStartupResult,
                        result,
                        requestedQuality: requestedQuality
                    )
                    if hasRequestedMedia {
                        if routingPlan.defersWebpageFallbackUntilWBIFailure, attempt.route == .wbi {
                            await fallbackTracker?.markNotNeeded()
                            webpageHedge?.task.cancel()
                        }
                        group.cancelAll()
                        await group.waitForAll()
                        if recordsStartupSchedulerFeedback(
                            requestSource: requestSource,
                            requestLease: requestLease
                        ) {
                            let fallbackStatus = await startupFallbackStatus(
                                tracker: fallbackTracker,
                                route: schedulingDecision.fallbackRoute
                            )
                            await recordStartupSchedulerResult(
                                attempt,
                                result: "winner",
                                requestedQuality: requestedQuality,
                                bvid: bvid,
                                fallbackStatus: fallbackStatus
                            )
                        } else if requestSource.recordsSchedulerFeedback {
                            await recordStartupSchedulerResult(
                                attempt,
                                result: "ignoredLate",
                                requestedQuality: requestedQuality,
                                bvid: bvid
                            )
                        }
                        logPlayURLStage(
                            "startupRaceWinner.\(attempt.stage)",
                            bvid: bvid,
                            cid: cid,
                            start: raceStart,
                            data: data
                        )
                        return result
                    }
                    if result.isVerifiedUnavailablePreferredFallback {
                        if routingPlan.defersWebpageFallbackUntilWBIFailure, attempt.route == .wbi {
                            await fallbackTracker?.markNotNeeded()
                            webpageHedge?.task.cancel()
                        }
                        group.cancelAll()
                        await group.waitForAll()
                        if recordsStartupSchedulerFeedback(
                            requestSource: requestSource,
                            requestLease: requestLease
                        ) {
                            let fallbackStatus = await startupFallbackStatus(
                                tracker: fallbackTracker,
                                route: schedulingDecision.fallbackRoute
                            )
                            await recordStartupSchedulerResult(
                                attempt,
                                result: "unavailablePreferred",
                                requestedQuality: requestedQuality,
                                bvid: bvid,
                                fallbackStatus: fallbackStatus
                            )
                        } else if requestSource.recordsSchedulerFeedback {
                            await recordStartupSchedulerResult(
                                attempt,
                                result: "ignoredLate",
                                requestedQuality: requestedQuality,
                                bvid: bvid
                            )
                        }
                        logPlayURLStage(
                            "startupRaceUnavailablePreferredFallback.\(attempt.stage)",
                            bvid: bvid,
                            cid: cid,
                            start: raceStart,
                            data: data
                        )
                        return result
                    }
                    logPreferredQualityMiss(
                        stage: attempt.stage,
                        bvid: bvid,
                        cid: cid,
                        requestedQuality: requestedQuality,
                        data: data
                    )
                    shouldStartDeferredWebpageFallback = attempt.route == .wbi
                }

                if let error = attempt.error {
                    if recordsStartupSchedulerFeedback(
                        requestSource: requestSource,
                        requestLease: requestLease
                    ) {
                        let fallbackStatus = await startupFallbackStatus(
                            tracker: fallbackTracker,
                            route: schedulingDecision.fallbackRoute
                        )
                        await recordStartupSchedulerResult(
                            attempt,
                            result: "failed",
                            requestedQuality: requestedQuality,
                            bvid: bvid,
                            fallbackStatus: fallbackStatus
                        )
                        if !(error is CancellationError),
                            (error as? URLError)?.code != .cancelled
                        {
                            await recordStartupRouteAttempt(
                                attempt,
                                accepted: false,
                                networkClass: playbackEnvironment.networkClass,
                                requestLease: requestLease
                            )
                        }
                        if attempt.stage == "startupWBI" {
                            await recordStartupWBIFailureIfNeeded(error, bvid: bvid)
                        }
                    } else if requestSource.recordsSchedulerFeedback {
                        await recordStartupSchedulerResult(
                            attempt,
                            result: "ignoredLate",
                            requestedQuality: requestedQuality,
                            bvid: bvid
                        )
                    }
                    lastError = error
                    logPlayURLStage(
                        "\(attempt.stage)Fallback",
                        bvid: bvid,
                        cid: cid,
                        start: raceStart,
                        error: error
                    )
                    shouldStartDeferredWebpageFallback = attempt.route == .wbi
                }

                if shouldStartDeferredWebpageFallback,
                    let fallbackRoute = routingPlan.deferredFallbackRoute(
                        forUnacceptableResultFrom: attempt.route
                    )
                {
                    await fallbackTracker?.markStartedAfterWBIFailure()
                    group.addTask(priority: .userInitiated) {
                        await self.startupPlayURLAttempt(
                            route: fallbackRoute,
                            bvid: bvid,
                            cid: cid,
                            page: page,
                            requestedQuality: requestedQuality,
                            webpageHedge: webpageHedge
                        )
                    }
                }
            }

            if let bestStartupResult {
                logPlayURLStage(
                    "startupRaceBestFallback",
                    bvid: bvid,
                    cid: cid,
                    start: raceStart,
                    data: bestStartupResult.data
                )
            } else if let lastError {
                logPlayURLStage(
                    "startupRaceFailed",
                    bvid: bvid,
                    cid: cid,
                    start: raceStart,
                    error: lastError
                )
            }
            return bestStartupResult
        }
    }

    private func startupPlayURLAttempt(
        route: StartupPlayURLRoute,
        bvid: String,
        cid: Int,
        page: Int?,
        requestedQuality: Int,
        webpageHedge: PiliPlusWebpageHedge? = nil
    ) async -> StartupPlayURLAttempt {
        let start = CACurrentMediaTime()
        let stage = route == .wbi ? "startupWBI" : "startupWebpage"
        // Both routes use the current playback account's cookies, so either can
        // authoritatively declare that the requested quality is unavailable.
        let isAuthoritativePlayURLSource = true
        do {
            let data: PlayURLData
            switch route {
            case .webpage:
                if PiliPlusStylePlayURLSelectionExperiment.stored() {
                    data = try await fetchPiliPlusStyleStartupFallbackPlayURL(
                        bvid: bvid,
                        cid: cid,
                        page: page,
                        requestedQuality: requestedQuality,
                        webpageHedge: webpageHedge
                    )
                } else {
                    data = try await fetchWebPagePlayURL(
                        bvid: bvid,
                        cid: cid,
                        page: page,
                        preferredQuality: requestedQuality
                    )
                }
            case .wbi:
                if PiliPlusStylePlayURLSelectionExperiment.stored() {
                    data = try await fetchPiliPlusStyleStartupPlayURL(
                        bvid: bvid,
                        cid: cid,
                        requestedQuality: requestedQuality
                    )
                } else {
                    let keys = try await fetchWBIKeys(priority: URLSessionTask.highPriority)
                    data = try await fetchWBIStartupPlayURL(
                        bvid: bvid,
                        cid: cid,
                        keys: keys,
                        preferredQuality: requestedQuality
                    )
                }
            }
            return StartupPlayURLAttempt(
                stage: stage,
                route: route,
                elapsedMilliseconds: max(Int(PlayerMetricsLog.elapsedMilliseconds(since: start).rounded()), 1),
                data: data,
                error: nil,
                isAuthoritativePlayURLSource: isAuthoritativePlayURLSource
            )
        } catch {
            return StartupPlayURLAttempt(
                stage: stage,
                route: route,
                elapsedMilliseconds: max(Int(PlayerMetricsLog.elapsedMilliseconds(since: start).rounded()), 1),
                data: nil,
                error: error,
                isAuthoritativePlayURLSource: isAuthoritativePlayURLSource
            )
        }
    }

    private func recordStartupRouteAttempt(
        _ attempt: StartupPlayURLAttempt,
        accepted: Bool,
        networkClass: PlaybackEnvironment.NetworkClass,
        requestLease: StartupPlayURLRequestLease?
    ) async {
        guard let route = attempt.route,
            let elapsedMilliseconds = attempt.elapsedMilliseconds
        else { return }
        _ = await StartupPlayURLRoutePerformanceStore.shared.record(
            route: route,
            networkClass: networkClass,
            elapsedMilliseconds: elapsedMilliseconds,
            accepted: accepted,
            requestLease: requestLease
        )
    }

    private nonisolated func recordsStartupSchedulerFeedback(
        requestSource: StartupPlayURLRequestSource,
        requestLease: StartupPlayURLRequestLease?
    ) -> Bool {
        requestSource.recordsSchedulerFeedback
            && StartupPlayURLFeedbackEligibility.allows(requestLease)
    }

    private nonisolated func startupWBISuppressionMessage(
        mode: String,
        suppressionStatus: StartupWBISuppressionStatus?,
        routeHint: StartupWBIRouteHint? = nil
    ) -> String {
        if routeHint == .webpageOnly {
            return
                "startupScheduler=\(mode) mode=webpageOnly wbi=suppressed source=routeHint reason=emptyPlayURL remaining=short"
        }
        guard let suppressionStatus else {
            return
                "startupScheduler=\(mode) mode=webpageOnly wbi=suppressed source=foreground reason=unknown remaining=-"
        }
        return
            "startupScheduler=\(mode) mode=webpageOnly wbi=suppressed source=foreground reason=\(suppressionStatus.reason) remaining=\(suppressionStatus.remainingMilliseconds)ms"
    }

    private func recordStartupWBISuccess(bvid: String) async {
        guard await state.recordStartupWBISuccess() else { return }
        await recordStartupSchedulerMessage(
            "startupWBIHealth source=foreground result=success action=reset",
            bvid: bvid
        )
    }

    private func recordStartupWBIFailureIfNeeded(_ error: Error, bvid: String) async {
        guard let reason = Self.startupWBIHealthFailureReason(for: error) else { return }
        let update = await state.recordStartupWBIFailure(reason: reason)
        switch update {
        case .observed(let consecutiveFailures):
            await recordStartupSchedulerMessage(
                "startupWBIHealth source=foreground result=failure reason=\(reason) failures=\(consecutiveFailures)/\(PlaybackStartupRequestSchedulingPolicy.wbiFailureThreshold) action=observe",
                bvid: bvid
            )
        case .suppressed(let status):
            await recordStartupSchedulerMessage(
                "startupWBIHealth source=foreground result=failure reason=\(status.reason) failures=\(PlaybackStartupRequestSchedulingPolicy.wbiFailureThreshold)/\(PlaybackStartupRequestSchedulingPolicy.wbiFailureThreshold) action=suppress remaining=\(status.remainingMilliseconds)ms",
                bvid: bvid
            )
        }
    }

    func recordStartupSchedulerMessage(_ message: String, bvid: String) async {
        await MainActor.run {
            PlayerMetricsLog.record(
                .startupScheduler,
                metricsID: bvid,
                message: message
            )
        }
    }

    private func recordStartupSchedulerResult(
        _ attempt: StartupPlayURLAttempt,
        result: String,
        requestedQuality: Int,
        bvid: String,
        fallbackStatus: String? = nil
    ) async {
        guard let route = attempt.route else { return }
        let elapsed = attempt.elapsedMilliseconds.map { "\($0)ms" } ?? "-"
        let fallback = fallbackStatus.map { " fallback=\($0)" } ?? ""
        await recordStartupSchedulerMessage(
            "startupSchedulerResult result=\(result) route=\(route.rawValue) elapsed=\(elapsed) requestedQ=\(requestedQuality)\(fallback)",
            bvid: bvid
        )
    }

    private func startupFallbackStatus(
        tracker: StartupPlayURLFallbackTracker?,
        route: StartupPlayURLRoute?
    ) async -> String {
        guard let route else { return "notScheduled" }
        guard let tracker else { return "\(route.rawValue):unknown" }
        let status = await tracker.currentStatus()
        return "\(route.rawValue):\(status.rawValue)"
    }

    private func preferredStartupRaceCandidate(
        _ lhs: StartupPlayURLRaceResult?,
        _ rhs: StartupPlayURLRaceResult,
        requestedQuality: Int
    ) -> StartupPlayURLRaceResult? {
        guard Self.startupCandidateQuality(in: rhs.data, requestedQuality: requestedQuality) != nil else {
            return lhs
        }
        guard let lhs else { return rhs }
        guard let lhsQuality = Self.startupCandidateQuality(in: lhs.data, requestedQuality: requestedQuality) else {
            return rhs
        }
        let rhsQuality = Self.startupCandidateQuality(in: rhs.data, requestedQuality: requestedQuality) ?? 0
        if rhsQuality != lhsQuality {
            return rhsQuality > lhsQuality ? rhs : lhs
        }
        return rhs.isVerifiedUnavailablePreferredFallback ? rhs : lhs
    }

}

private struct StartupPlayURLAttempt: Sendable {
    let stage: String
    let route: StartupPlayURLRoute?
    let elapsedMilliseconds: Int?
    let data: PlayURLData?
    let error: Error?
    let isAuthoritativePlayURLSource: Bool
}

struct StartupPlayURLRaceResult: Sendable {
    let data: PlayURLData
    let isVerifiedUnavailablePreferredFallback: Bool
}

import Foundation
import OSLog
import QuartzCore

extension BiliAPIClient {
    func fetchPiliPlusStyleStartupPlayURL(
        bvid: String,
        cid: Int,
        requestedQuality: Int
    ) async throws -> PlayURLData {
        let context = await playbackAPIRequestContext()
        let routeHintKey = Self.startupWBIRouteHintKey(
            bvid: bvid,
            cid: cid,
            requestedQuality: requestedQuality,
            accountMID: context.currentUserMID,
            credentialVersion: context.playbackCredentialVersion
        )
        let routeHint = await state.startupWBIRouteHint(for: routeHintKey)
        let queryQuality = Self.piliPlusPrimaryProbeQuality(
            requestedQuality: requestedQuality
        )
        let stageStart = CACurrentMediaTime()
        var keysElapsed: Double?
        var baseAttempt: PiliPlusWBIQualityAttempt?
        var rescueAttempt: PiliPlusWBIQualityAttempt?

        do {
            let keysStart = CACurrentMediaTime()
            let keys = try await fetchWBIKeys(priority: URLSessionTask.highPriority)
            keysElapsed = PlayerMetricsLog.elapsedMilliseconds(since: keysStart)
            let initialAttempt = await fetchPiliPlusWBIQualityAttempt(
                bvid: bvid,
                cid: cid,
                queryQuality: queryQuality,
                requestedQuality: requestedQuality,
                keys: keys,
                context: context
            )
            baseAttempt = initialAttempt
            var selectedAttempt = initialAttempt
            if !initialAttempt.isSuccessful,
                let error = initialAttempt.error,
                Self.shouldRescuePiliPlusWBI(after: error),
                let rescueQuality = Self.piliPlusCompatibilityRescueProbeQuality(
                    requestedQuality: requestedQuality,
                    baseQuality: queryQuality
                )
            {
                let attemptedRescue = await fetchPiliPlusWBIQualityAttempt(
                    bvid: bvid,
                    cid: cid,
                    queryQuality: rescueQuality,
                    requestedQuality: requestedQuality,
                    keys: keys,
                    context: context
                )
                rescueAttempt = attemptedRescue
                if attemptedRescue.isSuccessful {
                    selectedAttempt = attemptedRescue
                }
            }
            guard selectedAttempt.isSuccessful,
                let data = selectedAttempt.data,
                let selectedQuality = selectedAttempt.selectedQuality
            else {
                let finalError =
                    rescueAttempt?.error
                    ?? initialAttempt.error
                    ?? BiliAPIError.emptyPlayURL
                if Self.shouldRescuePiliPlusWBI(after: finalError) {
                    await state.storeStartupWBIRouteHint(.webpageOnly, for: routeHintKey)
                }
                throw finalError
            }

            try Task.checkCancellation()
            recordPiliPlusStylePlayURLDiagnostic(
                bvid: bvid,
                result: "success",
                requestedQuality: requestedQuality,
                queryQuality: queryQuality,
                selectedQuality: selectedQuality,
                requests: rescueAttempt == nil ? 1 : 2,
                keysElapsedMilliseconds: keysElapsed,
                requestElapsedMilliseconds: initialAttempt.elapsedMilliseconds,
                selectionElapsedMilliseconds: selectedAttempt.selectionElapsedMilliseconds,
                totalElapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: stageStart),
                routeHint: routeHint,
                availabilityData: data,
                targetResponseDiagnostic: initialAttempt.responseDiagnostic,
                rescueQueryQuality: rescueAttempt?.queryQuality,
                rescueRequestElapsedMilliseconds: rescueAttempt?.elapsedMilliseconds,
                rescueResponseDiagnostic: rescueAttempt?.responseDiagnostic
            )
            PlayerMetricsLog.logger.info(
                "piliPlusStyleStartupSelection bvid=\(bvid, privacy: .public) cid=\(cid, privacy: .public) requested=\(requestedQuality, privacy: .public) query=\(queryQuality, privacy: .public) selected=\(selectedQuality, privacy: .public) requests=1 codec=automatic"
            )
            return data
        } catch {
            guard !Task.isCancelled else { throw error }
            recordPiliPlusStylePlayURLDiagnostic(
                bvid: bvid,
                result: "failure",
                requestedQuality: requestedQuality,
                queryQuality: queryQuality,
                selectedQuality: (rescueAttempt ?? baseAttempt)?.data.flatMap {
                    Self.startupCandidateQuality(in: $0, requestedQuality: requestedQuality)
                },
                requests: rescueAttempt == nil ? 1 : 2,
                keysElapsedMilliseconds: keysElapsed,
                requestElapsedMilliseconds: baseAttempt?.elapsedMilliseconds,
                selectionElapsedMilliseconds: (rescueAttempt ?? baseAttempt)?.selectionElapsedMilliseconds,
                totalElapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: stageStart),
                routeHint: routeHint,
                availabilityData: (rescueAttempt ?? baseAttempt)?.data,
                targetResponseDiagnostic: baseAttempt?.responseDiagnostic,
                rescueQueryQuality: rescueAttempt?.queryQuality,
                rescueRequestElapsedMilliseconds: rescueAttempt?.elapsedMilliseconds,
                rescueResponseDiagnostic: rescueAttempt?.responseDiagnostic,
                error: error
            )
            throw error
        }
    }

    private func fetchPiliPlusWBIQualityAttempt(
        bvid: String,
        cid: Int,
        queryQuality: Int,
        requestedQuality: Int,
        keys: WBIKeys,
        context: PlaybackAPIRequestContext
    ) async -> PiliPlusWBIQualityAttempt {
        let requestStart = CACurrentMediaTime()
        var diagnosticData: PlayURLData?
        var selectionElapsed: Double?
        var responseDiagnostic: String?

        do {
            let requestTask = Task<BiliResponse<PlayURLData>, Error>(priority: TaskPriority.userInitiated) { [self] in
                let query = Self.piliPlusStylePlayURLQuery(
                    bvid: bvid,
                    cid: cid,
                    qn: queryQuality,
                    tryLook: !context.isLoggedIn
                )
                return try await get(
                    base: baseURL,
                    path: "/x/player/wbi/playurl",
                    query: WBISigner.sign(query, keys: keys),
                    referer: "https://www.bilibili.com/video/\(bvid)",
                    userAgent: userAgent(for: .web),
                    cookieHeader: context.cookieHeader,
                    cachePolicy: .reloadIgnoringLocalCacheData,
                    priority: URLSessionTask.highPriority
                )
            }
            defer { requestTask.cancel() }
            let response = try await Self.awaitSharedTask(requestTask)
            responseDiagnostic = Self.piliPlusWBIResponseDiagnosticMessage(
                queryQuality: queryQuality,
                response: response,
                isLoggedIn: context.isLoggedIn,
                hasSESSDATA: Self.cookieValue(named: "SESSDATA", in: context.cookieHeader) != nil,
                hasDedeUserID: Self.cookieValue(named: "DedeUserID", in: context.cookieHeader) != nil,
                hasAccessKey: context.appAccessKey?.isEmpty == false,
                accountPurposeEnabled: context.isAccountPurposeEnabled
            )
            diagnosticData = response.payload
            let data = try requirePlayURLData(response, requirePlayablePayload: true)
            diagnosticData = data
            let selectionStart = CACurrentMediaTime()
            let selectedQuality = Self.startupCandidateQuality(
                in: data,
                requestedQuality: requestedQuality
            )
            selectionElapsed = PlayerMetricsLog.elapsedMilliseconds(since: selectionStart)
            guard let selectedQuality else {
                throw TargetQualityUnavailableError(
                    requestedQuality: requestedQuality,
                    fallbackQuality: nil,
                    fallbackData: data
                )
            }
            guard
                Self.canUsePiliPlusCompatibilityResponse(
                    data,
                    requestedQuality: requestedQuality
                )
            else {
                throw TargetQualityUnavailableError(
                    requestedQuality: requestedQuality,
                    fallbackQuality: selectedQuality,
                    fallbackData: data
                )
            }
            return PiliPlusWBIQualityAttempt(
                queryQuality: queryQuality,
                selectedQuality: selectedQuality,
                data: data,
                elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: requestStart),
                selectionElapsedMilliseconds: selectionElapsed,
                responseDiagnostic: responseDiagnostic,
                error: nil
            )
        } catch {
            return PiliPlusWBIQualityAttempt(
                queryQuality: queryQuality,
                selectedQuality: nil,
                data: diagnosticData,
                elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: requestStart),
                selectionElapsedMilliseconds: selectionElapsed,
                responseDiagnostic: responseDiagnostic,
                error: error
            )
        }
    }

    nonisolated static func piliPlusWBIResponseDiagnosticMessage(
        queryQuality: Int,
        response: BiliResponse<PlayURLData>,
        isLoggedIn: Bool,
        hasSESSDATA: Bool,
        hasDedeUserID: Bool,
        hasAccessKey: Bool,
        accountPurposeEnabled: Bool
    ) -> String {
        func bit(_ value: Bool) -> Int { value ? 1 : 0 }

        let payload = response.payload
        return [
            "q\(queryQuality)",
            "outer\(response.code)",
            "inner\(payload?.code.map(String.init) ?? "-")",
            "payload\(bit(payload != nil))",
            "dashV\(payload?.dash?.video?.count ?? 0)",
            "dashA\(payload?.dash?.audio?.count ?? 0)",
            "durl\(payload?.durl?.count ?? 0)",
            "accept\(payload?.acceptQuality?.count ?? 0)",
            "support\(payload?.supportFormats?.count ?? 0)",
            "loggedIn\(bit(isLoggedIn))",
            "sess\(bit(hasSESSDATA))",
            "dede\(bit(hasDedeUserID))",
            "access\(bit(hasAccessKey))",
            "purpose\(bit(accountPurposeEnabled))",
        ].joined(separator: ":")
    }

    private nonisolated func recordPiliPlusStylePlayURLDiagnostic(
        bvid: String,
        result: String,
        requestedQuality: Int,
        queryQuality: Int,
        selectedQuality: Int?,
        requests: Int,
        keysElapsedMilliseconds: Double?,
        requestElapsedMilliseconds: Double?,
        selectionElapsedMilliseconds: Double?,
        totalElapsedMilliseconds: Double,
        routeHint: StartupWBIRouteHint?,
        availabilityData: PlayURLData? = nil,
        targetResponseDiagnostic: String? = nil,
        rescueQueryQuality: Int? = nil,
        rescueRequestElapsedMilliseconds: Double? = nil,
        rescueResponseDiagnostic: String? = nil,
        error: Error? = nil
    ) {
        let message = Self.piliPlusStylePlayURLDiagnosticMessage(
            result: result,
            requestedQuality: requestedQuality,
            queryQuality: queryQuality,
            selectedQuality: selectedQuality,
            requests: requests,
            keysElapsedMilliseconds: keysElapsedMilliseconds,
            requestElapsedMilliseconds: requestElapsedMilliseconds,
            selectionElapsedMilliseconds: selectionElapsedMilliseconds,
            totalElapsedMilliseconds: totalElapsedMilliseconds,
            routeHint: routeHint,
            availabilityData: availabilityData,
            targetResponseDiagnostic: targetResponseDiagnostic,
            rescueQueryQuality: rescueQueryQuality,
            rescueRequestElapsedMilliseconds: rescueRequestElapsedMilliseconds,
            rescueResponseDiagnostic: rescueResponseDiagnostic,
            error: error
        )
        Task { @MainActor in
            PlayerMetricsLog.record(.startupScheduler, metricsID: bvid, message: message)
        }
    }

    nonisolated static func piliPlusStylePlayURLDiagnosticMessage(
        result: String,
        requestedQuality: Int,
        queryQuality: Int? = nil,
        selectedQuality: Int?,
        requests: Int,
        keysElapsedMilliseconds: Double?,
        requestElapsedMilliseconds: Double?,
        selectionElapsedMilliseconds: Double?,
        totalElapsedMilliseconds: Double,
        routeHint: StartupWBIRouteHint? = nil,
        availabilityData: PlayURLData? = nil,
        targetResponseDiagnostic: String? = nil,
        rescueQueryQuality: Int? = nil,
        rescueRequestElapsedMilliseconds: Double? = nil,
        rescueResponseDiagnostic: String? = nil,
        error: Error? = nil
    ) -> String {
        func duration(_ milliseconds: Double?) -> String {
            guard let milliseconds else { return "-" }
            return "\(Int(milliseconds.rounded()))ms"
        }

        var parts = [
            "piliPlusStylePlayURL",
            "result=\(result)",
            "route=\(rescueQueryQuality == nil ? "baseQualityWBI" : "baseThenRescueWBI")",
            "strategy=\(PiliPlusStylePlayURLSelectionExperiment.currentStrategyKey)",
            "target=\(requestedQuality)",
            "queryQ=\(queryQuality ?? requestedQuality)",
            "routeHint=\(routeHint?.rawValue ?? "none")",
            "selected=\(selectedQuality.map(String.init) ?? "-")",
            "requests=\(requests)",
            "keys=\(duration(keysElapsedMilliseconds))",
            "request=\(duration(requestElapsedMilliseconds))",
            "selection=\(duration(selectionElapsedMilliseconds))",
            "total=\(duration(totalElapsedMilliseconds))",
        ]
        if let availabilityData {
            parts.append(availabilityData.targetQualityAvailabilitySummary(requestedQuality))
        }
        if let targetResponseDiagnostic {
            parts.append("baseResponse=\(targetResponseDiagnostic)")
        }
        if let rescueQueryQuality {
            parts.append("rescueQ=\(rescueQueryQuality)")
            parts.append("rescue=\(duration(rescueRequestElapsedMilliseconds))")
        }
        if let rescueResponseDiagnostic {
            parts.append("rescueResponse=\(rescueResponseDiagnostic)")
        }
        if let error {
            parts.append("reason=\(sanitizedPiliPlusStylePlayURLError(error))")
        }
        return parts.joined(separator: " ")
    }

    nonisolated static func piliPlusStartupFallbackDiagnosticMessage(
        result: String,
        route: String,
        requestedQuality: Int,
        selectedQuality: Int?,
        legacyResult: String,
        legacyElapsedMilliseconds: Double?,
        standardWBIResult: String = "notStarted",
        standardWBIQuality: Int? = nil,
        standardWBIElapsedMilliseconds: Double? = nil,
        webpageElapsedMilliseconds: Double?,
        totalElapsedMilliseconds: Double,
        legacyError: Error? = nil,
        standardWBIError: Error? = nil,
        webpageError: Error? = nil
    ) -> String {
        func duration(_ milliseconds: Double?) -> String {
            guard let milliseconds else { return "-" }
            return "\(Int(milliseconds.rounded()))ms"
        }

        var parts = [
            "piliPlusFallback",
            "result=\(result)",
            "route=\(route)",
            "strategy=\(PiliPlusStylePlayURLSelectionExperiment.currentStrategyKey)",
            "target=\(requestedQuality)",
            "selected=\(selectedQuality.map(String.init) ?? "-")",
            "legacyResult=\(legacyResult)",
            "legacy=\(duration(legacyElapsedMilliseconds))",
            "wbiResult=\(standardWBIResult)",
            "wbiQ=\(standardWBIQuality.map(String.init) ?? "-")",
            "wbi=\(duration(standardWBIElapsedMilliseconds))",
            "webpage=\(duration(webpageElapsedMilliseconds))",
            "total=\(duration(totalElapsedMilliseconds))",
        ]
        if let legacyError {
            parts.append("legacyReason=\(sanitizedPiliPlusStylePlayURLError(legacyError))")
        }
        if let standardWBIError {
            parts.append("wbiReason=\(sanitizedPiliPlusStylePlayURLError(standardWBIError))")
        }
        if let webpageError {
            parts.append("webpageReason=\(sanitizedPiliPlusStylePlayURLError(webpageError))")
        }
        return parts.joined(separator: " ")
    }

    nonisolated static func piliPlusPrimaryProbeQuality(requestedQuality: Int) -> Int {
        requestedQuality == 116 ? 112 : requestedQuality
    }

    nonisolated static func piliPlusCompatibilityRescueProbeQuality(
        requestedQuality: Int,
        baseQuality: Int
    ) -> Int? {
        guard requestedQuality > 80, baseQuality > 80 else { return nil }
        return 80
    }

    nonisolated static func shouldRescuePiliPlusWBI(after error: Error) -> Bool {
        if error is TargetQualityUnavailableError {
            return true
        }
        guard let apiError = error as? BiliAPIError else { return false }
        if case .emptyPlayURL = apiError {
            return true
        }
        return false
    }

    private nonisolated static func sanitizedPiliPlusStylePlayURLError(_ error: Error) -> String {
        if error is TargetQualityUnavailableError {
            return "targetQualityUnavailable"
        }
        if let error = error as? BiliAPIError {
            switch error {
            case .invalidURL: return "invalidURL"
            case .emptyData: return "emptyData"
            case .api(let code, _): return "api\(code)"
            case .missingPayload: return "missingPayload"
            case .missingSESSDATA: return "missingSESSDATA"
            case .missingCSRF: return "missingCSRF"
            case .emptyPlayURL: return "emptyPlayURL"
            case .unsupportedHardwarePlayback: return "unsupportedHardwarePlayback"
            }
        }
        if let error = error as? URLError {
            return "url\(error.errorCode)"
        }
        return String(describing: type(of: error))
            .replacingOccurrences(of: " ", with: "_")
    }
}

nonisolated private struct PiliPlusWBIQualityAttempt: Sendable {
    let queryQuality: Int
    let selectedQuality: Int?
    let data: PlayURLData?
    let elapsedMilliseconds: Double
    let selectionElapsedMilliseconds: Double?
    let responseDiagnostic: String?
    let error: Error?

    var isSuccessful: Bool {
        error == nil && data != nil && selectedQuality != nil
    }
}

import Foundation
import OSLog
import QuartzCore

extension BiliAPIClient {
    func fetchPlayURL(
        bvid: String,
        cid: Int,
        qn: Int = 112,
        page: Int? = nil,
        preferredQuality: Int? = nil
    ) async throws -> PlayURLData {
        let context = await playbackAPIRequestContext()
        let requestedQuality = preferredQuality ?? context.effectivePreferredVideoQuality ?? qn
        let key = PlayURLCacheKey(
            bvid: bvid,
            cid: cid,
            requestedQuality: requestedQuality,
            audioLanguage: "default",
            fnval: "4048",
            fnver: "0",
            platform: Self.playURLCachePlatform(
                context.playbackStreamSourcePreference.cachePlatform,
                requestedQuality: requestedQuality
            )
        )
        let scope = PlayURLCacheLoginScope(
            isLoggedIn: context.isLoggedIn,
            userMID: context.currentUserMID,
            guestModeEnabled: context.guestModeEnabled,
            credentialVersion: context.playbackCredentialVersion
        )
        if let cached = await cachedPlayURL(
            for: key,
            scope: scope,
            requiredQuality: requestedQuality
        ) {
            PlayerMetricsLog.logger.info(
                "playURLMemoryCacheHit bvid=\(bvid, privacy: .public) cid=\(cid, privacy: .public) qn=\(requestedQuality, privacy: .public)"
            )
            return await applyingConfiguredHistoryAccount(
                to: cached,
                playbackUserMID: context.currentUserMID
            )
        }

        let data = try await fetchPlayURLWithPendingRequest(
            cacheKey: key,
            scope: scope,
            bvid: bvid,
            cid: cid,
            requestedQuality: requestedQuality,
            source: "playURL",
            cachePlatform: context.playbackStreamSourcePreference.cachePlatform,
            isStartup: false
        ) { [self] in
            try await fetchPlayURLUncached(
                bvid: bvid,
                cid: cid,
                qn: qn,
                page: page,
                preferredQuality: preferredQuality
            )
        }
        return await applyingConfiguredHistoryAccount(
            to: data,
            playbackUserMID: context.currentUserMID
        )
    }

    func fetchPlayURLUncached(
        bvid: String,
        cid: Int,
        qn: Int = 112,
        page: Int? = nil,
        preferredQuality: Int? = nil
    ) async throws -> PlayURLData {
        let requestStart = CACurrentMediaTime()
        let referer = "https://www.bilibili.com/video/\(bvid)"
        let snapshot = requestSnapshot(purpose: .playback)
        let anonymousCookieHeader = snapshot.anonymousCookieHeader
        let playCookieHeader = snapshot.cookieHeader
        let requestedQuality =
            preferredQuality
            ?? snapshot.effectivePreferredVideoQuality
            ?? qn
        let streamSource = snapshot.playbackStreamSourcePreference
        let initialCodecPreference =
            PlayURLCodecPreference.primaryPlaybackOrder(
                requestedQuality: requestedQuality
            ).first ?? .hevc
        let query = Self.playURLQuery(
            bvid: bvid,
            cid: cid,
            qn: requestedQuality,
            streamSource: streamSource,
            codecPreference: initialCodecPreference
        )
        var lastError: Error?
        var bestPlayableData: PlayURLData?

        logPlayURLStage("start", bvid: bvid, cid: cid, start: requestStart)

        let wbiStageStart = CACurrentMediaTime()
        do {
            let playable = try await runCachedPlayURLStage(
                "wbiPrimary",
                bvid: bvid,
                cid: cid,
                qn: requestedQuality,
                cookieMode: "auth-wbi-\(streamSource.cachePlatform)",
                credentialVersion: snapshot.playbackCredentialVersion,
                start: wbiStageStart
            ) { [self] in
                let keys = try await fetchWBIKeys(priority: URLSessionTask.highPriority)
                return try await fetchWBIPlayURLWithCodecFallbacks(
                    bvid: bvid,
                    cid: cid,
                    requestedQuality: requestedQuality,
                    keys: keys,
                    referer: referer,
                    cookieHeader: playCookieHeader,
                    stagePrefix: "wbiPrimary",
                    cookieModePrefix: "auth-wbi-\(streamSource.cachePlatform)",
                    credentialVersion: snapshot.playbackCredentialVersion,
                    streamSource: streamSource,
                    priority: URLSessionTask.highPriority
                )
            }
            logPlayURLStage("wbiPrimary", bvid: bvid, cid: cid, start: wbiStageStart, data: playable)
            if shouldAcceptPlayURLData(playable, requestedQuality: requestedQuality) {
                logPlayURLStage("completeWBIPrimary", bvid: bvid, cid: cid, start: requestStart, data: playable)
                return playable
            }
            logPreferredQualityMiss(
                stage: "wbiPrimary", bvid: bvid, cid: cid, requestedQuality: requestedQuality, data: playable)
            bestPlayableData = playable
        } catch {
            lastError = error
        }

        // The mobile request profile can be handed a low AV1 rendition even when
        // the web player exposes the configured quality. Verify only a miss via
        // the web WBI profile before accepting a lower-quality fallback.
        if streamSource != .web {
            let webQualityProbeStart = CACurrentMediaTime()
            do {
                let playable = try await runCachedPlayURLStage(
                    "wbiWebQualityProbe",
                    bvid: bvid,
                    cid: cid,
                    qn: requestedQuality,
                    cookieMode: "auth-wbi-webQualityProbe-\(PlaybackStreamSourcePreference.web.cachePlatform)",
                    credentialVersion: snapshot.playbackCredentialVersion,
                    start: webQualityProbeStart
                ) { [self] in
                    let keys = try await fetchWBIKeys(priority: URLSessionTask.highPriority)
                    return try await fetchWBIPlayURLWithCodecFallbacks(
                        bvid: bvid,
                        cid: cid,
                        requestedQuality: requestedQuality,
                        keys: keys,
                        referer: referer,
                        cookieHeader: playCookieHeader,
                        stagePrefix: "wbiWebQualityProbe",
                        cookieModePrefix:
                            "auth-wbi-webQualityProbe-\(PlaybackStreamSourcePreference.web.cachePlatform)",
                        credentialVersion: snapshot.playbackCredentialVersion,
                        streamSource: .web,
                        priority: URLSessionTask.highPriority
                    )
                }
                logPlayURLStage("wbiWebQualityProbe", bvid: bvid, cid: cid, start: webQualityProbeStart, data: playable)
                if shouldAcceptPlayURLData(playable, requestedQuality: requestedQuality) {
                    logPlayURLStage(
                        "completeWBIWebQualityProbe", bvid: bvid, cid: cid, start: requestStart, data: playable)
                    return playable
                }
                logPreferredQualityMiss(
                    stage: "wbiWebQualityProbe", bvid: bvid, cid: cid, requestedQuality: requestedQuality,
                    data: playable)
                bestPlayableData = preferredPlayURLCandidate(
                    bestPlayableData,
                    playable,
                    requestedQuality: requestedQuality
                )
            } catch {
                lastError = error
            }
        }

        let legacyStageStart = CACurrentMediaTime()
        do {
            let playable = try await runCachedPlayURLStage(
                "legacyPrimary",
                bvid: bvid,
                cid: cid,
                qn: requestedQuality,
                cookieMode: "auth-legacy-\(streamSource.cachePlatform)",
                credentialVersion: snapshot.playbackCredentialVersion,
                start: legacyStageStart
            ) { [self] in
                try await fetchLegacyPlayURLWithCodecFallbacks(
                    bvid: bvid,
                    cid: cid,
                    requestedQuality: requestedQuality,
                    referer: referer,
                    cookieHeader: playCookieHeader,
                    streamSource: streamSource,
                    priority: URLSessionTask.highPriority
                )
            }
            logPlayURLStage("legacyPrimary", bvid: bvid, cid: cid, start: legacyStageStart, data: playable)
            if shouldAcceptPlayURLData(playable, requestedQuality: requestedQuality) {
                logPlayURLStage("completeLegacyPrimary", bvid: bvid, cid: cid, start: requestStart, data: playable)
                return playable
            }
            logPreferredQualityMiss(
                stage: "legacyPrimary", bvid: bvid, cid: cid, requestedQuality: requestedQuality, data: playable)
            bestPlayableData = preferredPlayURLCandidate(bestPlayableData, playable, requestedQuality: requestedQuality)
        } catch {
            lastError = error
        }

        let metadataStageStart = CACurrentMediaTime()
        do {
            let metadata = try await runCachedPlayURLStage(
                "anonymousMetadata",
                bvid: bvid,
                cid: cid,
                qn: requestedQuality,
                cookieMode: "anon-metadata-\(streamSource.cachePlatform)",
                credentialVersion: snapshot.playbackCredentialVersion,
                start: metadataStageStart
            ) { [self] in
                try await fetchAnonymousPlayURLMetadata(
                    bvid: bvid,
                    cid: cid,
                    referer: referer,
                    query: query,
                    streamSource: streamSource
                )
            }
            logPlayURLStage("anonymousMetadata", bvid: bvid, cid: cid, start: metadataStageStart, data: metadata)
            if !metadata.playVariants.isEmpty {
                let merged = bestPlayableData?.mergingPlayableStreams(from: metadata) ?? metadata
                if merged.highestPlayableQuality >= (bestPlayableData?.highestPlayableQuality ?? 0) {
                    bestPlayableData = merged
                }
            }
        } catch {
            lastError = error
        }

        let legacyAnonymousStageStart = CACurrentMediaTime()
        do {
            let playableFallback = try await runCachedPlayURLStage(
                "legacyAnonymousFallback",
                bvid: bvid,
                cid: cid,
                qn: requestedQuality,
                cookieMode: "anon-legacy-\(streamSource.cachePlatform)",
                credentialVersion: snapshot.playbackCredentialVersion,
                start: legacyAnonymousStageStart
            ) { [self] in
                try await fetchLegacyPlayURLWithCodecFallbacks(
                    bvid: bvid,
                    cid: cid,
                    requestedQuality: requestedQuality,
                    referer: referer,
                    cookieHeader: anonymousCookieHeader,
                    streamSource: streamSource,
                    priority: URLSessionTask.highPriority
                )
            }
            logPlayURLStage(
                "legacyAnonymousFallback", bvid: bvid, cid: cid, start: legacyAnonymousStageStart,
                data: playableFallback)
            if let existing = bestPlayableData {
                let merged = existing.mergingPlayableStreams(from: playableFallback)
                if merged.highestPlayableQuality > existing.highestPlayableQuality
                    || playableFallback.durl?.isEmpty == false
                {
                    bestPlayableData = merged
                }
            } else if playableFallback.highestPlayableQuality > 0 {
                bestPlayableData = playableFallback
            }
        } catch {
            lastError = error
        }

        let webpageStageStart = CACurrentMediaTime()
        do {
            let webpagePlayable = try await runCachedPlayURLStage(
                "webpagePlayInfo",
                bvid: bvid,
                cid: cid,
                qn: requestedQuality,
                cookieMode: "auth-webpage-\(streamSource.cachePlatform)",
                credentialVersion: snapshot.playbackCredentialVersion,
                start: webpageStageStart
            ) { [self] in
                try await fetchWebPagePlayInfo(
                    bvid: bvid,
                    page: page,
                    referer: referer,
                    cookieHeader: playCookieHeader
                )
            }
            logPlayURLStage("webpagePlayInfo", bvid: bvid, cid: cid, start: webpageStageStart, data: webpagePlayable)
            if let bestPlayableData {
                let merged = bestPlayableData.mergingPlayableStreams(from: webpagePlayable)
                logPlayURLStage("completeWebpageMerged", bvid: bvid, cid: cid, start: requestStart, data: merged)
                return merged
            }
            logPlayURLStage("completeWebpage", bvid: bvid, cid: cid, start: requestStart, data: webpagePlayable)
            return webpagePlayable
        } catch {
            if let bestPlayableData {
                logPlayURLStage("webpagePlayInfo", bvid: bvid, cid: cid, start: webpageStageStart, error: error)
                logPlayURLStage(
                    "completeBestFallback", bvid: bvid, cid: cid, start: requestStart, data: bestPlayableData)
                return bestPlayableData
            }
            logPlayURLStage("completeFailed", bvid: bvid, cid: cid, start: requestStart, error: lastError ?? error)
            throw lastError ?? error
        }
    }
}

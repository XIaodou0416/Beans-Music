import Foundation

nonisolated struct PlaybackAPIRequestContext: Sendable {
    let cookieHeader: String
    let anonymousCookieHeader: String
    let appAccessKey: String?
    let effectivePreferredVideoQuality: Int?
    let playbackStreamSourcePreference: PlaybackStreamSourcePreference
    let isLoggedIn: Bool
    let currentUserMID: Int?
    let guestModeEnabled: Bool
    let playbackCredentialVersion: Int
    let isAccountPurposeEnabled: Bool
}

extension BiliAPIClient {
    nonisolated func fetchPgcSeasonInfo(seasonID: Int?, epID: Int? = nil) async throws -> PgcSeasonInfo {
        var candidates = [(query: [String: String], referer: String)]()
        if let epID, epID > 0 {
            candidates.append(
                (
                    query: ["ep_id": String(epID)],
                    referer: "https://www.bilibili.com/bangumi/play/ep\(epID)"
                ))
        }
        if let seasonID, seasonID > 0 {
            candidates.append(
                (
                    query: ["season_id": String(seasonID)],
                    referer: "https://www.bilibili.com/bangumi/play/ss\(seasonID)"
                ))
        }
        guard !candidates.isEmpty else { throw BiliAPIError.missingPayload }

        var lastError: Error?
        for candidate in candidates {
            do {
                let response: BiliResponse<PgcSeasonInfo> = try await get(
                    base: baseURL,
                    path: "/pgc/view/web/season",
                    query: candidate.query,
                    referer: candidate.referer,
                    responseCachePolicy: .detail
                )
                guard response.code == 0 else {
                    throw BiliAPIError.api(code: response.code, message: response.displayMessage)
                }
                guard let info = response.payload else { throw BiliAPIError.missingPayload }
                return info
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }
        throw lastError ?? BiliAPIError.missingPayload
    }

    nonisolated func fetchPgcPlayURL(
        bvid: String,
        cid: Int,
        seasonID: Int?,
        epID: Int?,
        qn: Int = 112,
        preferredQuality: Int? = nil
    ) async throws -> PlayURLData {
        let context = await playbackAPIRequestContext()
        let requestedQuality = preferredQuality ?? context.effectivePreferredVideoQuality ?? qn
        let streamSource = context.playbackStreamSourcePreference
        let keys = try await fetchWBIKeys(priority: URLSessionTask.highPriority)
        let referer: String
        if let epID {
            referer = "https://www.bilibili.com/bangumi/play/ep\(epID)"
        } else if let seasonID {
            referer = "https://www.bilibili.com/bangumi/play/ss\(seasonID)"
        } else {
            referer = "https://www.bilibili.com/bangumi/play/"
        }
        var lastError: Error?
        var bestFallbackData: PlayURLData?
        for codecPreference in PlayURLCodecPreference.extendedPlaybackOrder(requestedQuality: requestedQuality) {
            do {
                var query = pgcPlayURLQuery(
                    bvid: bvid,
                    cid: cid,
                    seasonID: seasonID,
                    epID: epID,
                    qn: requestedQuality,
                    streamSource: streamSource,
                    codecPreference: codecPreference
                )
                query = WBISigner.sign(query, keys: keys)
                let response: BiliResponse<PgcPlayURLResult> = try await get(
                    base: baseURL,
                    path: "/pgc/player/web/v2/playurl",
                    query: query,
                    referer: referer,
                    userAgent: userAgent(for: streamSource),
                    cookieHeader: context.cookieHeader,
                    cachePolicy: .reloadIgnoringLocalCacheData,
                    priority: URLSessionTask.highPriority
                )
                let data = try requirePgcPlayURLData(response, requirePlayablePayload: true)
                let requestedData = try requireRequestedQualityIfNeeded(data, requestedQuality: requestedQuality)
                guard codecPreference.accepts(requestedData) else {
                    throw BiliAPIError.emptyPlayURL
                }
                if Self.shouldContinueCodecFallback(
                    for: requestedData,
                    requestedQuality: requestedQuality,
                    requestedCodecFamily: codecPreference.selectionCodecFamily,
                    allowsUnavailableQualityFallback: codecPreference.allowsUnavailableQualityFallback
                ) {
                    bestFallbackData = preferredStartupCandidate(
                        bestFallbackData,
                        requestedData,
                        requestedQuality: requestedQuality
                    )
                    continue
                }
                return await applyingConfiguredHistoryAccount(
                    to: requestedData,
                    playbackUserMID: context.currentUserMID
                )
            } catch {
                guard !Task.isCancelled else { throw error }
                lastError = error
                guard shouldTryAlternatePlayURLCodec(after: error) else { break }
            }
        }
        if let bestFallbackData {
            return await applyingConfiguredHistoryAccount(
                to: bestFallbackData,
                playbackUserMID: context.currentUserMID
            )
        }
        throw lastError ?? BiliAPIError.emptyPlayURL
    }

    private nonisolated func pgcPlayURLQuery(
        bvid: String,
        cid: Int,
        seasonID: Int?,
        epID: Int?,
        qn: Int,
        streamSource: PlaybackStreamSourcePreference,
        codecPreference: PlayURLCodecPreference = .hevc
    ) -> [String: String] {
        var query = [
            "cid": String(cid),
            "qn": String(qn),
            "fnval": "4048",
            "fnver": "0",
            "fourk": "1",
            "platform": streamSource.playURLPlatform,
            "high_quality": "1",
            "otype": "json",
            "try_look": "1",
            "gaia_source": "pre-load",
            "isGaiaAvoided": "true",
            "web_location": "1315873",
        ]
        if bvid.hasPrefix("BV") {
            query["bvid"] = bvid
        }
        if let seasonID {
            query["season_id"] = String(seasonID)
        }
        if let epID {
            query["ep_id"] = String(epID)
        }
        if let videoCodecid = codecPreference.videoCodecid(requestedQuality: qn) {
            query["video_codecid"] = videoCodecid
        }
        return query
    }

    private nonisolated func requirePgcPlayURLData(
        _ response: BiliResponse<PgcPlayURLResult>,
        requirePlayablePayload: Bool = false
    ) throws -> PlayURLData {
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        guard let data = response.payload?.videoInfo else { throw BiliAPIError.missingPayload }
        if let code = data.code, code != 0 {
            throw BiliAPIError.api(code: code, message: data.message)
        }
        if requirePlayablePayload, data.playVariants.isEmpty {
            if data.hasAnyPlayURLPayload {
                throw BiliAPIError.unsupportedHardwarePlayback(
                    "番剧播放接口已返回地址，但没有可用的 HEVC/AAC 硬解组合（\(data.rawPlayURLSummary)）"
                )
            }
            throw BiliAPIError.emptyPlayURL
        }
        return data
    }
}

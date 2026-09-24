import Foundation
import QuartzCore

extension BiliAPIClient {
    nonisolated func requirePlayURLData(_ response: BiliResponse<PlayURLData>, requirePlayablePayload: Bool = false) throws
        -> PlayURLData
    {
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        guard let data = response.payload else { throw BiliAPIError.missingPayload }
        if let code = data.code, code != 0 {
            throw BiliAPIError.api(code: code, message: data.message)
        }
        if requirePlayablePayload, data.playVariants.isEmpty {
            if data.hasAnyPlayURLPayload {
                throw BiliAPIError.unsupportedHardwarePlayback(
                    "播放接口已返回地址，但没有可用的 HEVC/AAC 硬解组合（\(data.rawPlayURLSummary)）"
                )
            }
            throw BiliAPIError.emptyPlayURL
        }
        return data
    }

    nonisolated static func playURLQuery(
        bvid: String,
        cid: Int,
        qn: Int,
        streamSource: PlaybackStreamSourcePreference,
        codecPreference: PlayURLCodecPreference = .hevc,
        tryLook: Bool = true
    ) -> [String: String] {
        var query = [
            "bvid": bvid,
            "cid": String(cid),
            "qn": String(qn),
            "fnval": "4048",
            "fnver": "0",
            "fourk": "1",
            "platform": streamSource.playURLPlatform,
            "high_quality": "1",
            "otype": "json",
            "gaia_source": "pre-load",
            "isGaiaAvoided": "true",
            "web_location": "1315873",
            "dm_img_list": "[]",
            "dm_img_str": Self.randomAlphaNumeric(length: 16),
            "dm_cover_img_str": Self.randomAlphaNumeric(length: 32),
            "dm_img_inter": #"{"ds":[],"wh":[0,0,0],"of":[0,0,0]}"#,
        ]
        if tryLook {
            query["try_look"] = "1"
        }
        if let videoCodecid = codecPreference.videoCodecid(requestedQuality: qn) {
            query["video_codecid"] = videoCodecid
        }
        return query
    }

    nonisolated static func piliPlusCompatibilityPlayURLQuery(
        bvid: String,
        cid: Int,
        qn: Int,
        streamSource: PlaybackStreamSourcePreference,
        tryLook: Bool
    ) -> [String: String] {
        playURLQuery(
            bvid: bvid,
            cid: cid,
            qn: qn,
            streamSource: streamSource,
            codecPreference: .automatic,
            tryLook: tryLook
        )
    }

    nonisolated static func piliPlusStylePlayURLQuery(
        bvid: String,
        cid: Int,
        qn: Int,
        tryLook: Bool
    ) -> [String: String] {
        var query = [
            "bvid": bvid,
            "cid": String(cid),
            "qn": String(qn),
            "fnval": "4048",
            "fourk": "1",
            "fnver": "0",
            "voice_balance": "0",
            "gaia_source": "pre-load",
            "isGaiaAvoided": "true",
            "web_location": "1315873",
            "dm_img_list": "[]",
            "dm_img_str": piliPlusDMParameter(minLength: 16, maxLength: 64),
            "dm_cover_img_str": piliPlusDMParameter(minLength: 32, maxLength: 128),
            "dm_img_inter": #"{"ds":[],"wh":[0,0,0],"of":[0,0,0]}"#,
        ]
        if tryLook {
            query["try_look"] = "1"
        }
        return query
    }

    private nonisolated static func piliPlusDMParameter(
        minLength: Int,
        maxLength: Int
    ) -> String {
        let length = Int.random(in: minLength...maxLength)
        let bytes = (0..<length).map { _ in UInt8.random(in: 0x26...0x7e) }
        return String(Data(bytes).base64EncodedString().dropLast(2))
    }

    nonisolated func fetchLegacyPlayURLWithCodecFallbacks(
        bvid: String,
        cid: Int,
        requestedQuality: Int,
        referer: String,
        cookieHeader: String,
        streamSource: PlaybackStreamSourcePreference,
        priority: Float,
        codecPreferences: [PlayURLCodecPreference]? = nil,
        allowsCodecFallbackAfterAnyError: Bool = false
    ) async throws -> PlayURLData {
        let orderedPreferences: [PlayURLCodecPreference]
        if let codecPreferences, !codecPreferences.isEmpty {
            orderedPreferences = codecPreferences
        } else {
            orderedPreferences = PlayURLCodecPreference.extendedPlaybackOrder(
                requestedQuality: requestedQuality
            )
        }
        var lastError: Error?
        var bestFallbackData: PlayURLData?

        for codecPreference in orderedPreferences {
            do {
                let query = Self.playURLQuery(
                    bvid: bvid,
                    cid: cid,
                    qn: requestedQuality,
                    streamSource: streamSource,
                    codecPreference: codecPreference
                )
                let response: BiliResponse<PlayURLData> = try await get(
                    base: baseURL,
                    path: "/x/player/playurl",
                    query: query,
                    referer: referer,
                    userAgent: userAgent(for: streamSource),
                    cookieHeader: cookieHeader,
                    cachePolicy: .reloadIgnoringLocalCacheData,
                    priority: priority
                )
                let data = try requirePlayURLData(response, requirePlayablePayload: true)
                let requestedData = try requireRequestedQualityIfNeeded(
                    data,
                    requestedQuality: requestedQuality
                )
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
                return requestedData
            } catch {
                guard !Task.isCancelled else { throw error }
                lastError = error
                guard shouldTryAlternatePlayURLCodec(after: error) else { break }
            }
        }

        if let bestFallbackData {
            return bestFallbackData
        }
        throw lastError ?? BiliAPIError.emptyPlayURL
    }

    nonisolated func fetchWBIPlayURLWithCodecFallbacks(
        bvid: String,
        cid: Int,
        requestedQuality: Int,
        keys: WBIKeys,
        referer: String,
        cookieHeader: String,
        stagePrefix: String,
        cookieModePrefix: String,
        credentialVersion: Int,
        streamSource: PlaybackStreamSourcePreference,
        priority: Float,
        codecPreferences: [PlayURLCodecPreference]? = nil,
        requiresRequestedQuality: Bool = true,
        tryLook: Bool = true,
        allowsCodecFallbackAfterAnyError: Bool = false
    ) async throws -> PlayURLData {
        var lastError: Error?
        var bestFallbackData: PlayURLData?
        let orderedPreferences: [PlayURLCodecPreference]
        if let codecPreferences, !codecPreferences.isEmpty {
            orderedPreferences = codecPreferences
        } else {
            orderedPreferences = PlayURLCodecPreference.extendedPlaybackOrder(
                requestedQuality: requestedQuality
            )
        }
        for codecPreference in orderedPreferences {
            let stage = "\(stagePrefix)\(codecPreference.stageSuffix)"
            do {
                let stageStart = CACurrentMediaTime()
                let data = try await runCachedPlayURLStage(
                    stage,
                    bvid: bvid,
                    cid: cid,
                    qn: requestedQuality,
                    cookieMode: "\(cookieModePrefix)-\(codecPreference.rawValue)",
                    credentialVersion: credentialVersion,
                    start: stageStart
                ) { [self] in
                    let query = Self.playURLQuery(
                        bvid: bvid,
                        cid: cid,
                        qn: requestedQuality,
                        streamSource: streamSource,
                        codecPreference: codecPreference,
                        tryLook: tryLook
                    )
                    let signed = WBISigner.sign(query, keys: keys)
                    let response: BiliResponse<PlayURLData> = try await get(
                        base: baseURL,
                        path: "/x/player/wbi/playurl",
                        query: signed,
                        referer: referer,
                        userAgent: userAgent(for: streamSource),
                        cookieHeader: cookieHeader,
                        cachePolicy: .reloadIgnoringLocalCacheData,
                        priority: priority
                    )
                    let data = try requirePlayURLData(response, requirePlayablePayload: true)
                    let requestedData =
                        requiresRequestedQuality
                        ? try requireRequestedQualityIfNeeded(data, requestedQuality: requestedQuality)
                        : data
                    guard codecPreference.accepts(requestedData) else {
                        throw BiliAPIError.emptyPlayURL
                    }
                    return requestedData
                }
                if codecPreference != .hevc {
                    logPlayURLStage(stage, bvid: bvid, cid: cid, start: CACurrentMediaTime(), data: data)
                }
                if Self.shouldContinueCodecFallback(
                    for: data,
                    requestedQuality: requestedQuality,
                    requestedCodecFamily: codecPreference.selectionCodecFamily,
                    allowsUnavailableQualityFallback: codecPreference.allowsUnavailableQualityFallback
                ) {
                    bestFallbackData = preferredStartupCandidate(
                        bestFallbackData,
                        data,
                        requestedQuality: requestedQuality
                    )
                    continue
                }
                return data
            } catch {
                guard !Task.isCancelled else { throw error }
                lastError = error
                guard
                    allowsCodecFallbackAfterAnyError
                        || shouldTryAlternatePlayURLCodec(after: error)
                else { break }
            }
        }
        if let bestFallbackData {
            return bestFallbackData
        }
        throw lastError ?? BiliAPIError.emptyPlayURL
    }

    nonisolated func shouldRefreshWBIKeys(after error: Error) -> Bool {
        guard let biliError = error as? BiliAPIError else { return false }
        switch biliError {
        case .emptyPlayURL, .unsupportedHardwarePlayback:
            return true
        default:
            return false
        }
    }

    nonisolated func shouldRetryWBIAnonymously(after error: Error) -> Bool {
        guard let biliError = error as? BiliAPIError else { return false }
        switch biliError {
        case .emptyPlayURL, .unsupportedHardwarePlayback:
            return true
        case .api(let code, _) where code == -351:
            return true
        default:
            return false
        }
    }

    nonisolated func shouldTryExtendedPlayURLCodecFallback(after error: Error) -> Bool {
        guard let biliError = error as? BiliAPIError else { return false }
        switch biliError {
        case .unsupportedHardwarePlayback:
            return true
        default:
            return false
        }
    }
}

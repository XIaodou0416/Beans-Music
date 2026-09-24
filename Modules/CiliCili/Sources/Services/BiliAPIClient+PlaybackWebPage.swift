import Foundation
import QuartzCore

extension BiliAPIClient {
    func fetchWebPagePlayURL(
        bvid: String,
        cid: Int,
        page: Int? = nil,
        preferredQuality: Int? = nil
    ) async throws -> PlayURLData {
        let stageStart = CACurrentMediaTime()
        let referer = "https://www.bilibili.com/video/\(bvid)"
        let snapshot = requestSnapshot(purpose: .playback)
        let requestedQuality = preferredQuality ?? snapshot.effectivePreferredVideoQuality ?? 112
        let streamSource = snapshot.playbackStreamSourcePreference
        let data = try await runCachedPlayURLStage(
            "webpagePlayInfo",
            bvid: bvid,
            cid: cid,
            qn: requestedQuality,
            cookieMode: "auth-webpage-\(streamSource.cachePlatform)",
            credentialVersion: snapshot.playbackCredentialVersion,
            start: stageStart
        ) { [self] in
            try await fetchWebPagePlayInfo(
                bvid: bvid,
                page: page,
                referer: referer,
                cookieHeader: snapshot.cookieHeader
            )
        }
        logPlayURLStage("webpagePlayInfo", bvid: bvid, cid: cid, start: stageStart, data: data)
        return await applyingConfiguredHistoryAccount(
            to: data,
            playbackUserMID: snapshot.currentUserMID
        )
    }

    func fetchWebPagePlayInfo(
        bvid: String,
        page: Int?,
        referer: String,
        cookieHeader: String?
    ) async throws -> PlayURLData {
        guard var components = URLComponents(string: "https://www.bilibili.com/video/\(bvid)/") else {
            throw BiliAPIError.invalidURL
        }
        if let page, page > 1 {
            components.queryItems = [URLQueryItem(name: "p", value: String(page))]
        }
        guard let url = components.url else { throw BiliAPIError.invalidURL }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        let resolvedCookieHeader: String
        if let cookieHeader {
            resolvedCookieHeader = cookieHeader
        } else {
            resolvedCookieHeader = await transportRequestContext().cookieHeader
        }
        let headers = BiliURLSessionFactory.apiHeaders(
            referer: referer,
            userAgent: Self.webUserAgent,
            cookieHeader: resolvedCookieHeader
        )
        for header in headers {
            request.setValue(header.value, forHTTPHeaderField: header.key)
        }
        let json: String
        if PiliPlusStylePlayURLSelectionExperiment.stored() {
            let streamStart = CACurrentMediaTime()
            do {
                let result = try await webPagePlayInfoStreamFetch(
                    request,
                    URLSessionTask.highPriority
                )
                if let extractedJSON = result.json {
                    json = extractedJSON
                    await recordStartupSchedulerMessage(
                        Self.piliPlusWebpageStreamDiagnosticMessage(
                            mode: "incremental",
                            receivedBytes: result.receivedByteCount,
                            expectedBytes: result.expectedByteCount,
                            elapsedMilliseconds: Double(result.elapsedMilliseconds)
                        ),
                        bvid: bvid
                    )
                } else if let data = result.fullPageData,
                    !data.isEmpty,
                    let html = String(data: data, encoding: .utf8),
                    let extractedJSON = Self.extractWebPagePlayInfoJSON(from: html)
                {
                    json = extractedJSON
                    await recordStartupSchedulerMessage(
                        Self.piliPlusWebpageStreamDiagnosticMessage(
                            mode: "completedPage",
                            receivedBytes: result.receivedByteCount,
                            expectedBytes: result.expectedByteCount,
                            elapsedMilliseconds: Double(result.elapsedMilliseconds)
                        ),
                        bvid: bvid
                    )
                } else if result.receivedByteCount == 0 {
                    throw BiliAPIError.emptyData
                } else {
                    throw BiliAPIError.missingPayload
                }
            } catch {
                let isCancellation =
                    Task.isCancelled
                    || error is CancellationError
                    || (error as? URLError)?.code == .cancelled
                if isCancellation {
                    throw error
                }
                let fallbackReason: String
                if let urlError = error as? URLError {
                    fallbackReason = "network.\(urlError.code.rawValue)"
                } else if let reason = Self.startupWBIHealthFailureReason(for: error) {
                    fallbackReason = reason
                } else {
                    fallbackReason = String(describing: type(of: error))
                }
                let (data, response) = try await data(
                    for: request,
                    priority: URLSessionTask.highPriority
                )
                guard !data.isEmpty else { throw BiliAPIError.emptyData }
                guard let html = String(data: data, encoding: .utf8),
                    let extractedJSON = Self.extractWebPagePlayInfoJSON(from: html)
                else {
                    throw BiliAPIError.missingPayload
                }
                json = extractedJSON
                let expectedBytes =
                    response.expectedContentLength > 0
                    ? response.expectedContentLength
                    : nil
                await recordStartupSchedulerMessage(
                    Self.piliPlusWebpageStreamDiagnosticMessage(
                        mode: "fullPageFallback",
                        receivedBytes: data.count,
                        expectedBytes: expectedBytes,
                        elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: streamStart),
                        fallbackReason: fallbackReason
                    ),
                    bvid: bvid
                )
            }
        } else {
            let (data, _) = try await data(
                for: request,
                priority: URLSessionTask.highPriority
            )
            guard !data.isEmpty else { throw BiliAPIError.emptyData }
            guard let html = String(data: data, encoding: .utf8),
                let extractedJSON = Self.extractWebPagePlayInfoJSON(from: html)
            else {
                throw BiliAPIError.missingPayload
            }
            json = extractedJSON
        }

        let response: BiliResponse<PlayURLData> = try await Self.decode(
            Data(json.utf8),
            priority: URLSessionTask.highPriority
        )
        return try requirePlayURLData(response, requirePlayablePayload: true)
    }

    func fetchAnonymousPlayURLMetadata(
        bvid: String,
        cid: Int,
        referer: String,
        query: [String: String],
        streamSource: PlaybackStreamSourcePreference
    ) async throws -> PlayURLData {
        let response: BiliResponse<PlayURLData> = try await get(
            base: baseURL,
            path: "/x/player/playurl",
            query: query,
            referer: referer,
            userAgent: userAgent(for: streamSource),
            cookieHeader: await anonymousCookieHeader(purpose: .playback),
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        return try requirePlayURLData(response)
    }

    private static func extractWebPagePlayInfoJSON(from html: String) -> String? {
        let markers = [
            "window.__playinfo__=",
            "window.__playinfo__ =",
            "__playinfo__=",
        ]
        for marker in markers {
            guard let markerRange = html.range(of: marker),
                let json = extractBalancedJSONObject(from: html[markerRange.upperBound...])
            else { continue }
            return json
        }
        return nil
    }

    static func extractBalancedJSONObject(from source: Substring) -> String? {
        guard let start = source.firstIndex(of: "{") else { return nil }
        var index = start
        var depth = 0
        var isInsideString = false
        var isEscaped = false

        while index < source.endIndex {
            let character = source[index]
            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
            } else {
                if character == "\"" {
                    isInsideString = true
                } else if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1
                    if depth == 0 {
                        return String(source[start...index])
                    }
                }
            }
            index = source.index(after: index)
        }
        return nil
    }
}

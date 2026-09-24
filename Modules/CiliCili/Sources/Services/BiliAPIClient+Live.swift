import Foundation
import OSLog
import QuartzCore

private let liveAPIURL = URL(string: "https://api.live.bilibili.com")!

nonisolated struct LiveDanmakuClientContext: Sendable {
    let uid: Int
    let buvid: String
    let cookieHeader: String
    let headers: [String: String]
}

extension BiliAPIClient {
    func liveDanmakuTransportData(
        for request: URLRequest,
        transportSession: URLSession?
    ) async throws -> Data {
        if let transportSession {
            return try await transportSession.data(for: request).0
        }
        return try await session.data(for: request).0
    }

    func fetchLiveRooms(page: Int = 1, refreshIndex: Int = 0) async throws -> [LiveRoom] {
        var query = [
            "platform": "web",
            "page": String(page),
            "page_size": "20",
        ]
        if refreshIndex > 0 {
            query["fresh_idx"] = String(refreshIndex)
            query["fresh_type"] = "3"
            query["_"] = String(Int(Date().timeIntervalSince1970 * 1000))
        }

        let request = try await makeRequest(
            base: liveAPIURL,
            path: "/xlive/web-interface/v1/webMain/getMoreRecList",
            query: query,
            referer: "https://live.bilibili.com",
            cookieHeader: await anonymousCookieHeader(),
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        let (data, _) = try await data(for: request, priority: URLSessionTask.lowPriority)
        guard !data.isEmpty else { throw BiliAPIError.emptyData }

        do {
            let response: BiliResponse<LiveRecommendData> = try await Self.decode(
                data,
                priority: URLSessionTask.lowPriority
            )
            guard response.code == 0 else {
                throw BiliAPIError.api(code: response.code, message: response.displayMessage)
            }
            if let rooms = response.payload?.recommendRoomList, !rooms.isEmpty {
                return rooms.filter { $0.roomID > 0 }
            }
        } catch {
            let rooms = try Self.decodeLiveRoomsFallback(from: data)
            if !rooms.isEmpty {
                return rooms
            }
            throw error
        }

        return try Self.decodeLiveRoomsFallback(from: data)
    }

    func fetchLiveAreas() async throws -> [LiveAreaGroup] {
        let response: BiliResponse<[LiveAreaGroup]> = try await get(
            base: liveAPIURL,
            path: "/room/v1/Area/getList",
            query: ["show_pinyin": "1"],
            referer: "https://live.bilibili.com",
            responseCachePolicy: .long
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        return (response.payload ?? []).filter { $0.id > 0 }
    }

    func fetchLiveRooms(parentAreaID: Int, areaID: Int = 0, page: Int = 1) async throws -> [LiveRoom] {
        let response: BiliResponse<[LiveRoom]> = try await get(
            base: liveAPIURL,
            path: "/room/v1/area/getRoomList",
            query: [
                "parent_area_id": String(parentAreaID),
                "area_id": String(areaID),
                "page": String(page),
                "page_size": "20",
                "sort_type": "online",
                "platform": "web",
            ],
            referer: "https://live.bilibili.com",
            responseCachePolicy: .brief
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        return (response.payload ?? []).filter { $0.roomID > 0 }
    }

    func fetchLiveRoomInfo(roomID: Int) async throws -> LiveRoomInfo {
        let response: BiliResponse<LiveRoomInfo> = try await get(
            base: liveAPIURL,
            path: "/room/v1/Room/get_info",
            query: ["room_id": String(roomID)],
            referer: "https://live.bilibili.com/\(roomID)",
            responseCachePolicy: .short
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        guard let info = response.payload else { throw BiliAPIError.missingPayload }
        return info
    }

    func fetchLiveAnchorInfo(roomID: Int) async throws -> LiveAnchorInfoData {
        let response: BiliResponse<LiveAnchorInfoData> = try await get(
            base: liveAPIURL,
            path: "/live_user/v1/UserInfo/get_anchor_in_room",
            query: ["roomid": String(roomID)],
            referer: "https://live.bilibili.com/\(roomID)",
            responseCachePolicy: .short
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        guard let info = response.payload else { throw BiliAPIError.missingPayload }
        return info
    }

    func fetchLiveRoomSummary(uid: Int) async throws -> LiveRoomSummary {
        let response: BiliResponse<LiveRoomSummary> = try await get(
            base: liveAPIURL,
            path: "/room/v1/Room/getRoomInfoOld",
            query: ["mid": String(uid)],
            referer: "https://space.bilibili.com/\(uid)",
            responseCachePolicy: .short
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        guard let info = response.payload, info.roomID > 0 else {
            throw BiliAPIError.missingPayload
        }
        return info
    }

    func fetchLiveStreamURL(roomID: Int) async throws -> URL {
        guard let url = try await fetchLiveStreamInfo(roomID: roomID).candidates.first?.url else {
            throw BiliAPIError.missingPayload
        }
        return url
    }

    func fetchLiveStreamCandidates(roomID: Int) async throws -> [LiveStreamURLCandidate] {
        try await fetchLiveStreamInfo(roomID: roomID).candidates
    }

    func livePlaybackHTTPHeaders(roomID: Int) async -> [String: String] {
        let cookieHeader = await liveAccountRequestIdentity().cookieHeader
        var headers = [
            "User-Agent": Self.mobileUserAgent,
            "Referer": "https://live.bilibili.com/\(roomID)",
            "Origin": "https://live.bilibili.com",
            "Accept": "*/*",
            "Accept-Language": "zh-CN,zh;q=0.9",
        ]
        if !cookieHeader.isEmpty {
            headers["Cookie"] = cookieHeader
        }
        return headers
    }

    func fetchLiveStreamInfo(roomID: Int, quality: Int? = nil) async throws -> LiveStreamFetchResult {
        var lastError: Error?
        let requestedQuality = quality ?? 10000
        let attempts: [(stageName: String, query: [String: String])] = [
            (
                "web",
                [
                    "room_id": String(roomID),
                    "protocol": "0,1",
                    "format": "0,1,2",
                    "codec": "0,1",
                    "qn": String(requestedQuality),
                    "platform": "web",
                ]
            ),
            (
                "android",
                [
                    "room_id": String(roomID),
                    "protocol": "0,1",
                    "format": "0,1,2",
                    "codec": "0",
                    "qn": String(requestedQuality),
                    "platform": "android",
                ]
            ),
        ]

        let racedAttempt = await withTaskGroup(
            of: Result<LiveStreamAttemptOutcome, Error>.self,
            returning: (result: LiveStreamFetchResult?, error: Error?, qualities: [LiveStreamQuality]).self
        ) { group in
            for attempt in attempts {
                group.addTask { [self] in
                    do {
                        return .success(
                            try await fetchLiveStreamInfoAttempt(
                                roomID: roomID,
                                query: attempt.query,
                                stageName: attempt.stageName
                            )
                        )
                    } catch {
                        return .failure(error)
                    }
                }
            }

            var collectedQualities: [LiveStreamQuality] = []
            var lastAttemptError: Error?
            while let attemptResult = await group.next() {
                switch attemptResult {
                case .success(let outcome):
                    collectedQualities.append(contentsOf: outcome.qualities)
                    guard !outcome.candidates.isEmpty else {
                        lastAttemptError = BiliAPIError.missingPayload
                        continue
                    }
                    group.cancelAll()
                    PlayerMetricsLog.logger.info(
                        "liveStreamInfoReady room=\(roomID, privacy: .public) stage=\(outcome.stageName, privacy: .public) candidates=\(outcome.candidates.count, privacy: .public) qualities=\(outcome.qualities.count, privacy: .public) elapsedMs=\(outcome.elapsedMilliseconds, format: .fixed(precision: 1), privacy: .public)"
                    )
                    return (
                        LiveStreamFetchResult(
                            candidates: Self.removingDuplicateLiveURLs(from: outcome.candidates),
                            qualities: LiveStreamQuality.merged(collectedQualities)
                        ),
                        nil,
                        collectedQualities
                    )
                case .failure(let error):
                    lastAttemptError = error
                }
            }
            return (nil, lastAttemptError, collectedQualities)
        }

        if let result = racedAttempt.result {
            return result
        }
        lastError = racedAttempt.error

        do {
            let legacyStart = CACurrentMediaTime()
            let legacyCandidates = try await fetchLegacyLiveStreamCandidates(roomID: roomID)
            if !legacyCandidates.isEmpty {
                PlayerMetricsLog.logger.info(
                    "liveStreamInfoLegacyReady room=\(roomID, privacy: .public) candidates=\(legacyCandidates.count, privacy: .public) elapsedMs=\(PlayerMetricsLog.elapsedMilliseconds(since: legacyStart), format: .fixed(precision: 1), privacy: .public)"
                )
                return LiveStreamFetchResult(
                    candidates: legacyCandidates,
                    qualities: LiveStreamQuality.merged(racedAttempt.qualities)
                )
            }
        } catch {
            lastError = error
        }

        throw lastError ?? BiliAPIError.missingPayload
    }

    func fetchLiveDanmakuConnectionInfo(
        roomID: Int,
        cookieHeader: String? = nil,
        transportSession: URLSession? = nil
    ) async throws -> LiveDanmakuConnectionInfoData {
        let query = [
            "id": String(roomID),
            "type": "0",
            "web_location": "444.8",
        ]
        let signedQuery: [String: String]
        do {
            let keys = try await fetchWBIKeys(priority: URLSessionTask.defaultPriority)
            signedQuery = WBISigner.sign(query, keys: keys)
        } catch {
            signedQuery = query
        }
        guard var components = URLComponents(url: liveAPIURL, resolvingAgainstBaseURL: false) else {
            throw BiliAPIError.invalidURL
        }
        components.path = "/xlive/web-room/v1/index/getDanmuInfo"
        components.queryItems =
            signedQuery
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw BiliAPIError.invalidURL }

        // The live socket token is paired with the default web transport. Keep
        // this request intentionally small so the following WebSocket handshake
        // has the same client identity as Bilibili's working native clients.
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.timeoutInterval = 15
        if let cookieHeader, !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        let data = try await liveDanmakuTransportData(
            for: request,
            transportSession: transportSession
        )
        guard !data.isEmpty else { throw BiliAPIError.emptyData }
        let response: BiliResponse<LiveDanmakuConnectionInfoData> = try await Self.decode(
            data,
            priority: URLSessionTask.defaultPriority
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        guard let info = response.payload else { throw BiliAPIError.missingPayload }
        return info
    }

    func fetchLiveDanmakuHistory(roomID: Int) async throws -> [LiveDanmakuHistoryMessage] {
        guard var components = URLComponents(url: liveAPIURL, resolvingAgainstBaseURL: false) else {
            throw BiliAPIError.invalidURL
        }
        components.path = "/xlive/web-room/v1/dM/gethistory"
        components.queryItems = [URLQueryItem(name: "roomid", value: String(roomID))]
        guard let url = components.url else { throw BiliAPIError.invalidURL }

        // This endpoint rejects the browser-style headers used by the general
        // API client on some live rooms. Keep it aligned with the mobile
        // request shape used by PiliPod: a native User-Agent and session cookie.
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.timeoutInterval = 8
        request.setValue(
            "bili-universal/103300 (iPhone; iOS 18.2; Scale/3.00)",
            forHTTPHeaderField: "User-Agent"
        )
        let cookieHeader = await liveAccountRequestIdentity().cookieHeader
        if !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        let (data, urlResponse) = try await URLSession.shared.data(for: request)
        guard let response = urlResponse as? HTTPURLResponse else {
            throw BiliAPIError.emptyData
        }
        guard (200...299).contains(response.statusCode) else {
            throw BiliAPIError.api(
                code: response.statusCode,
                message: HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
            )
        }
        guard !data.isEmpty else { throw BiliAPIError.emptyData }

        let decoded: BiliResponse<LiveDanmakuHistoryData> = try await Self.decode(
            data,
            priority: URLSessionTask.defaultPriority
        )
        guard decoded.code == 0 else {
            throw BiliAPIError.api(code: decoded.code, message: decoded.displayMessage)
        }
        guard let history = decoded.payload else { throw BiliAPIError.missingPayload }
        return history.chronologicalMessages
    }

    func liveDanmakuClientContext(roomID: Int) async -> LiveDanmakuClientContext {
        let identity = await liveAccountRequestIdentity()
        let cookieHeader = identity.cookieHeader
        let buvid = Self.cookieValue(named: "buvid3", in: cookieHeader) ?? ""
        let uid =
            identity.currentUserMID
            ?? Self.cookieValue(named: "DedeUserID", in: cookieHeader).flatMap(Int.init)
            ?? 0
        var headers = [
            "Referer": "https://live.bilibili.com/\(roomID)",
            "Origin": "https://live.bilibili.com",
        ]
        if !cookieHeader.isEmpty {
            headers["Cookie"] = cookieHeader
        }
        return LiveDanmakuClientContext(
            uid: uid,
            buvid: buvid,
            cookieHeader: cookieHeader,
            headers: headers
        )
    }

    func fetchFollowedLiveRooms(page: Int = 1, pageSize: Int = 10) async throws -> [LiveRoom] {
        let response: BiliResponse<FollowedLiveRoomsData> = try await get(
            base: liveAPIURL,
            path: "/xlive/web-ucenter/v1/xfetter/FeedList",
            query: [
                "page": String(page),
                "page_size": String(pageSize),
                "platform": "web",
            ],
            referer: "https://live.bilibili.com",
            responseCachePolicy: .brief
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        return response.payload?.roomList.filter { $0.roomID > 0 && $0.isLive } ?? []
    }

    private func fetchLiveStreamInfoAttempt(
        roomID: Int,
        query: [String: String],
        stageName: String
    ) async throws -> LiveStreamAttemptOutcome {
        let attemptStart = CACurrentMediaTime()
        let response: BiliResponse<LivePlayInfoData> = try await get(
            base: liveAPIURL,
            path: "/xlive/web-room/v2/index/getRoomPlayInfo",
            query: query,
            referer: "https://live.bilibili.com/\(roomID)",
            userAgent: Self.webUserAgent,
            cachePolicy: .reloadIgnoringLocalCacheData,
            priority: URLSessionTask.highPriority,
            timeoutInterval: 6
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        return LiveStreamAttemptOutcome(
            stageName: stageName,
            candidates: response.payload?.playableURLCandidates ?? [],
            qualities: response.payload?.availableQualities ?? [],
            elapsedMilliseconds: PlayerMetricsLog.elapsedMilliseconds(since: attemptStart)
        )
    }

    private func fetchLegacyLiveStreamURL(roomID: Int) async throws -> URL {
        guard let url = try await fetchLegacyLiveStreamCandidates(roomID: roomID).first?.url else {
            throw BiliAPIError.missingPayload
        }
        return url
    }

    private func fetchLegacyLiveStreamCandidates(roomID: Int) async throws -> [LiveStreamURLCandidate] {
        let response: BiliResponse<LiveRoomPlayURLData> = try await get(
            base: liveAPIURL,
            path: "/room/v1/Room/playUrl",
            query: [
                "cid": String(roomID),
                "quality": "4",
                "platform": "h5",
            ],
            referer: "https://live.bilibili.com/\(roomID)",
            userAgent: Self.mobileUserAgent,
            cachePolicy: .reloadIgnoringLocalCacheData,
            priority: URLSessionTask.highPriority,
            timeoutInterval: 6
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        let candidates = response.payload?.playableURLCandidates ?? []
        guard !candidates.isEmpty else { throw BiliAPIError.missingPayload }
        return candidates
    }

    private static func decodeLiveRoomsFallback(from data: Data) throws -> [LiveRoom] {
        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dataObject = object["data"] as? [String: Any]
        else {
            return []
        }

        let candidates = ["recommend_room_list", "room_list", "list"]
        for key in candidates {
            guard let rawRooms = dataObject[key] as? [[String: Any]], !rawRooms.isEmpty else {
                continue
            }
            return rawRooms.compactMap { rawRoom in
                guard JSONSerialization.isValidJSONObject(rawRoom),
                    let roomData = try? JSONSerialization.data(withJSONObject: rawRoom),
                    let room = try? JSONDecoder.bili.decode(LiveRoom.self, from: roomData),
                    room.roomID > 0
                else {
                    return nil
                }
                return room
            }
        }

        return []
    }

    private static func removingDuplicateLiveURLs(
        from candidates: [LiveStreamURLCandidate]
    ) -> [LiveStreamURLCandidate] {
        var seen = Set<String>()
        var result: [LiveStreamURLCandidate] = []
        for candidate in candidates {
            guard seen.insert(candidate.url.absoluteString).inserted else { continue }
            result.append(candidate)
        }
        return result
    }
}

nonisolated private struct LiveStreamAttemptOutcome {
    let stageName: String
    let candidates: [LiveStreamURLCandidate]
    let qualities: [LiveStreamQuality]
    let elapsedMilliseconds: Double
}

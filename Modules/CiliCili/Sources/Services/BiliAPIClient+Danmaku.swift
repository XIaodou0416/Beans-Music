import Foundation

nonisolated struct DanmakuRequestContext: Sendable {
    let commentURL: URL
    let apiURL: URL
    let guestModeCookieHeader: String?
}

nonisolated struct DanmakuXMLParseContext: Sendable {
    let cid: Int
    let maxItems: Int

    init(cid: Int, maxItems: Int = 6_000) {
        self.cid = cid
        self.maxItems = maxItems
    }
}

nonisolated struct DanmakuSegmentParseContext: Sendable {
    let cid: Int
    let segmentIndex: Int
    let maxItems: Int

    init(cid: Int, segmentIndex: Int, maxItems: Int = 2_200) {
        self.cid = cid
        self.segmentIndex = segmentIndex
        self.maxItems = maxItems
    }
}

extension BiliAPIClient {
    nonisolated static func parseDanmakuXML(
        _ data: Data,
        context: DanmakuXMLParseContext
    ) async throws -> [DanmakuItem] {
        try await Task.detached(priority: .userInitiated) {
            try DanmakuXMLParser(cid: context.cid, maxItems: context.maxItems).parse(data: data)
        }.value
    }

    nonisolated static func parseDanmakuSegment(
        _ data: Data,
        context: DanmakuSegmentParseContext
    ) async throws -> [DanmakuItem] {
        try await Task.detached(priority: .userInitiated) {
            try DanmakuSegmentProtobufParser(
                cid: context.cid,
                segmentIndex: context.segmentIndex,
                maxItems: context.maxItems
            )
            .parse(data: data)
        }.value
    }

    func danmakuRequestContext() async -> DanmakuRequestContext {
        let snapshot = requestSnapshot()
        return DanmakuRequestContext(
            commentURL: commentURL,
            apiURL: baseURL,
            guestModeCookieHeader: snapshot.guestModeEnabled ? snapshot.anonymousCookieHeader : nil
        )
    }

    func fetchDanmakuData(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request, priority: URLSessionTask.defaultPriority)
    }

    func fetchDanmaku(cid: Int) async throws -> [DanmakuItem] {
        if let cached = await SubtitleDanmakuResourceCache.shared.danmaku(for: cid, segmentIndex: 0) {
            return cached
        }

        return try await ResourceRequestLimiter.shared.runDanmaku { [self] in
            if let cached = await SubtitleDanmakuResourceCache.shared.danmaku(for: cid, segmentIndex: 0) {
                return cached
            }

            let context = await danmakuRequestContext()
            var request = try await makeRequest(
                base: context.commentURL,
                path: "/\(cid).xml",
                query: [:],
                referer: "https://www.bilibili.com",
                userAgent: Self.webUserAgent,
                cookieHeader: context.guestModeCookieHeader,
                cachePolicy: .returnCacheDataElseLoad
            )
            request.networkServiceType = .responsiveData
            request.timeoutInterval = 8
            request.setValue("application/xml,text/xml,*/*", forHTTPHeaderField: "Accept")

            let (data, response) = try await fetchDanmakuData(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                (200..<300).contains(httpResponse.statusCode)
            else {
                throw BiliAPIError.emptyData
            }
            guard !data.isEmpty else { throw BiliAPIError.emptyData }

            let items = try await Self.parseDanmakuXML(
                data,
                context: DanmakuXMLParseContext(cid: cid)
            )
            await SubtitleDanmakuResourceCache.shared.storeDanmaku(items, for: cid, segmentIndex: 0)
            return items
        }
    }

    func fetchDanmakuSegment(cid: Int, segmentIndex: Int) async throws -> [DanmakuItem] {
        let normalizedSegmentIndex = max(1, segmentIndex)
        if let cached = await SubtitleDanmakuResourceCache.shared.danmaku(
            for: cid,
            segmentIndex: normalizedSegmentIndex
        ) {
            return cached
        }

        return try await ResourceRequestLimiter.shared.runDanmaku { [self] in
            if let cached = await SubtitleDanmakuResourceCache.shared.danmaku(
                for: cid,
                segmentIndex: normalizedSegmentIndex
            ) {
                return cached
            }

            let context = await danmakuRequestContext()
            var request = try await makeRequest(
                base: context.apiURL,
                path: "/x/v2/dm/web/seg.so",
                query: [
                    "type": "1",
                    "oid": String(cid),
                    "segment_index": String(normalizedSegmentIndex),
                ],
                referer: "https://www.bilibili.com",
                userAgent: Self.webUserAgent,
                cookieHeader: context.guestModeCookieHeader,
                cachePolicy: .returnCacheDataElseLoad
            )
            request.networkServiceType = .responsiveData
            request.timeoutInterval = 8
            request.setValue("application/octet-stream,*/*", forHTTPHeaderField: "Accept")

            let (data, response) = try await fetchDanmakuData(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                (200..<300).contains(httpResponse.statusCode)
            else {
                throw BiliAPIError.emptyData
            }

            let items = try await Self.parseDanmakuSegment(
                data,
                context: DanmakuSegmentParseContext(
                    cid: cid,
                    segmentIndex: normalizedSegmentIndex
                )
            )
            await SubtitleDanmakuResourceCache.shared.storeDanmaku(
                items,
                for: cid,
                segmentIndex: normalizedSegmentIndex
            )
            return items
        }
    }
}

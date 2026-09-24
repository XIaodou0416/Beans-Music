import Foundation
import OSLog

extension BiliAPIClient {
    func fetchUploaderVideoPage(
        mid: Int,
        page: Int = 1,
        cursor: UploaderVideoPageCursor? = nil,
        order: UploaderVideoOrder = .pubdate
    ) async throws -> UploaderVideoPageResult {
        do {
            return try await fetchUploaderWebVideoPage(mid: mid, page: page, order: order)
        } catch {
            Self.uploaderLogger.error(
                "webArchive failed mid=\(mid, privacy: .public) page=\(page, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            return try await fetchUploaderAppArchivePage(mid: mid, cursor: cursor, order: order)
        }
    }

    private func fetchUploaderWebVideoPage(
        mid: Int,
        page: Int = 1,
        order: UploaderVideoOrder
    ) async throws -> UploaderVideoPageResult {
        let keys = try await fetchWBIKeys()
        let signed = WBISigner.sign(
            [
                "mid": String(mid),
                "pn": String(page),
                "ps": "30",
                "tid": "0",
                "keyword": "",
                "order": order.rawValue,
                "platform": "web",
                "web_location": "333.1387",
                "order_avoided": "true",
                "dm_img_list": "[]",
                "dm_img_str": Self.randomAlphaNumeric(length: 16),
                "dm_cover_img_str": Self.randomAlphaNumeric(length: 32),
                "dm_img_inter": #"{"ds":[],"wh":[0,0,0],"of":[0,0,0]}"#,
            ], keys: keys)

        let response: BiliResponse<UploaderVideoData> = try await get(
            base: baseURL,
            path: "/x/space/wbi/arc/search",
            query: signed,
            referer: "https://space.bilibili.com/\(mid)",
            userAgent: Self.webUserAgent,
            cookieHeader: await uploaderProfileRequestContext().anonymousCookieHeader,
            additionalHeaders: ["Origin": "https://space.bilibili.com"],
            cachePolicy: .reloadIgnoringLocalCacheData,
            responseCachePolicy: .short
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        let videos =
            response.payload?.list?.vlist?
            .filter { !$0.bvid.isEmpty }
            .map { $0.asVideoItem(defaultMID: mid) } ?? []
        let pageSize = 30
        let totalCount = response.payload?.page?.count
        let hasMore = totalCount.map { page * pageSize < $0 } ?? (videos.count >= pageSize)
        let cursor = videos.last?.aid.map { UploaderVideoPageCursor(aid: String($0), next: nil) }
        return UploaderVideoPageResult(
            videos: videos,
            totalCount: totalCount,
            hasMore: hasMore,
            nextCursor: hasMore ? cursor : nil
        )
    }

    private func fetchUploaderAppArchivePage(
        mid: Int,
        cursor: UploaderVideoPageCursor? = nil,
        order: UploaderVideoOrder
    ) async throws -> UploaderVideoPageResult {
        let profile = BiliAppSigner.Profile.androidLogin
        let requestContext = await uploaderProfileRequestContext()
        var fields = [
            "build": profile.build,
            "version": profile.appVersion,
            "c_locale": "zh_CN",
            "channel": profile.channel,
            "mobi_app": profile.mobiApp,
            "platform": profile.platform,
            "s_locale": "zh_CN",
            "statistics": profile.statistics,
            "vmid": String(mid),
            "ps": "20",
            "qn": "80",
            "order": order.rawValue,
        ]
        if let aid = cursor?.aid, !aid.isEmpty {
            fields["aid"] = aid
        }
        if let next = cursor?.next {
            fields["next"] = String(next)
        }
        let publicCookieHeader = requestContext.anonymousCookieHeader
        let additionalHeaders = Self.uploaderAppHeaders(
            cookieHeader: publicCookieHeader,
            profile: profile
        )

        do {
            return try await requestUploaderAppArchivePage(
                mid: mid,
                query: BiliAppSigner.sign(fields, profile: profile),
                profile: profile,
                cookieHeader: publicCookieHeader,
                additionalHeaders: additionalHeaders
            )
        } catch {
            Self.uploaderLogger.error(
                "appArchive signed failed mid=\(mid, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            return try await requestUploaderAppArchivePage(
                mid: mid,
                query: fields,
                profile: profile,
                cookieHeader: publicCookieHeader,
                additionalHeaders: additionalHeaders
            )
        }
    }

    private func requestUploaderAppArchivePage(
        mid: Int,
        query: [String: String],
        profile: BiliAppSigner.Profile,
        cookieHeader: String,
        additionalHeaders: [String: String]
    ) async throws -> UploaderVideoPageResult {
        let response: BiliResponse<UploaderAppArchiveData> = try await get(
            base: appURL,
            path: "/x/v2/space/archive/cursor",
            query: query,
            referer: "https://space.bilibili.com/\(mid)",
            userAgent: profile.userAgent,
            cookieHeader: cookieHeader,
            additionalHeaders: additionalHeaders,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        guard let payload = response.payload else { throw BiliAPIError.missingPayload }
        let videos = payload.item?.compactMap { $0.asVideoItem(defaultMID: mid) } ?? []
        let hasMore = payload.hasNext ?? payload.next.map { $0 != 0 } ?? !videos.isEmpty
        return UploaderVideoPageResult(
            videos: videos,
            totalCount: payload.count,
            hasMore: hasMore,
            nextCursor: hasMore ? payload.pageCursor() : nil
        )
    }

    func fetchUploaderVideos(mid: Int, page: Int = 1) async throws -> [VideoItem] {
        try await fetchUploaderVideoPage(mid: mid, page: page).videos
    }

    func fetchUploaderSeasonSeries(
        mid: Int,
        page: Int = 1,
        pageSize: Int = 10
    ) async throws -> UploaderSeasonSeriesData {
        guard mid > 0 else { throw BiliAPIError.api(code: -1, message: "UP 主 UID 无效") }
        let response: BiliResponse<UploaderSeasonSeriesResponse> = try await get(
            base: baseURL,
            path: "/x/polymer/web-space/seasons_series_list",
            query: [
                "mid": String(mid),
                "page_num": String(page),
                "page_size": String(pageSize),
            ],
            referer: "https://space.bilibili.com/\(mid)",
            userAgent: Self.webUserAgent,
            cookieHeader: await uploaderProfileRequestContext().anonymousCookieHeader,
            additionalHeaders: ["Origin": "https://space.bilibili.com"],
            cachePolicy: .reloadIgnoringLocalCacheData,
            responseCachePolicy: .short
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        guard let data = response.payload?.itemsLists else { throw BiliAPIError.missingPayload }
        return data
    }

    func fetchUploaderSeasonSeriesArchivePage(
        mid: Int,
        owner: VideoOwner,
        kind: UploaderSeasonSeriesKind,
        page: Int = 1,
        pageSize: Int = 30,
        sort: UploaderSeasonSeriesArchiveSort = .desc
    ) async throws -> UploaderSeasonSeriesArchivePageResult {
        guard mid > 0 else { throw BiliAPIError.api(code: -1, message: "UP 主 UID 无效") }
        let path: String
        let query: [String: String]
        switch kind {
        case .season(let seasonID):
            path = "/x/polymer/web-space/seasons_archives_list"
            query = [
                "mid": String(mid),
                "season_id": String(seasonID),
                "sort_reverse": sort == .asc ? "true" : "false",
                "page_size": String(pageSize),
                "page_num": String(page),
                "web_location": "333.1387",
            ]
        case .series(let seriesID):
            path = "/x/series/archives"
            query = [
                "mid": String(mid),
                "series_id": String(seriesID),
                "sort": sort.rawValue,
                "ps": String(pageSize),
                "pn": String(page),
                "web_location": "333.1387",
            ]
        }

        let response: BiliResponse<UploaderSeasonSeriesArchiveData> = try await get(
            base: baseURL,
            path: path,
            query: query,
            referer: "https://space.bilibili.com/\(mid)",
            userAgent: Self.webUserAgent,
            cookieHeader: await uploaderProfileRequestContext().anonymousCookieHeader,
            additionalHeaders: ["Origin": "https://space.bilibili.com"],
            cachePolicy: .reloadIgnoringLocalCacheData,
            responseCachePolicy: .short
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        guard let data = response.payload else { throw BiliAPIError.missingPayload }
        let videos = data.archives.compactMap { $0.asVideoItem(defaultOwner: owner) }
        return UploaderSeasonSeriesArchivePageResult(
            videos: videos,
            totalCount: data.page?.total,
            hasMore: data.page?.hasMore(
                afterPage: page,
                receivedCount: data.archives.count,
                fallbackPageSize: pageSize
            ) ?? !videos.isEmpty
        )
    }
}

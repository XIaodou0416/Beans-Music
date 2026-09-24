import Foundation

private let dynamicUploaderWebUserAgent =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.2 Safari/605.1.15"
private let dynamicWebFeatures =
    "itemOpusStyle,listOnlyfans,opusBigCover,onlyfansVote,decorationCard,onlyfansAssetsV2,forwardListHidden,ugcDelete"

extension BiliAPIClient {
    nonisolated static func uploaderDynamicCookieHeader(
        isLoggedIn: Bool,
        authenticatedCookieHeader: String,
        anonymousCookieHeader: String
    ) -> String {
        isLoggedIn ? authenticatedCookieHeader : anonymousCookieHeader
    }

    func fetchDynamicFeed(offset: String? = nil) async throws -> DynamicFeedData {
        let context = await dynamicFeedRequestContext()
        guard context.isLoggedIn else { throw BiliAPIError.missingSESSDATA }
        var query = [
            "type": "all",
            "platform": "web",
            "features": dynamicWebFeatures,
            "web_location": "333.1365",
        ]
        if let offset, !offset.isEmpty {
            query["offset"] = offset
        }

        let isInitialRequest = offset?.isEmpty != false
        let diskSnapshotIdentity =
            isInitialRequest
            ? DynamicFeedDiskSnapshotStore.accountIdentity(for: context.currentUserMID)
            : nil
        if let diskSnapshotIdentity,
            let cachedData = await DynamicFeedDiskSnapshotStore.shared.freshData(for: diskSnapshotIdentity)
        {
            if let cachedResponse: BiliResponse<DynamicFeedData> = try? await Self.decodeDynamicFeedResponse(
                cachedData),
                cachedResponse.code == 0,
                let cachedPage = cachedResponse.payload
            {
                Task(priority: .utility) { [weak self] in
                    guard let self else { return }
                    _ = try? await self.fetchDynamicFeedFromNetwork(
                        query: query,
                        cookieHeader: context.cookieHeader,
                        diskSnapshotIdentity: diskSnapshotIdentity
                    )
                }
                return cachedPage
            }
            await DynamicFeedDiskSnapshotStore.shared.removeData(for: diskSnapshotIdentity)
        }

        return try await fetchDynamicFeedFromNetwork(
            query: query,
            cookieHeader: context.cookieHeader,
            diskSnapshotIdentity: diskSnapshotIdentity
        )
    }

    private func fetchDynamicFeedFromNetwork(
        query: [String: String],
        cookieHeader: String,
        diskSnapshotIdentity: String?
    ) async throws -> DynamicFeedData {
        let responseDataObserver: (@Sendable (Data) -> Void)?
        if let diskSnapshotIdentity {
            responseDataObserver = { data in
                guard Self.isSuccessfulDynamicFeedResponse(data) else { return }
                Task(priority: TaskPriority.utility) {
                    await DynamicFeedDiskSnapshotStore.shared.store(data, for: diskSnapshotIdentity)
                }
            }
        } else {
            responseDataObserver = nil
        }
        let response: BiliResponse<DynamicFeedData> = try await get(
            base: baseURL,
            path: "/x/polymer/web-dynamic/v1/feed/all",
            query: query,
            cookieHeader: cookieHeader,
            responseCachePolicy: .brief,
            responseDataObserver: responseDataObserver
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard let data = response.payload else { throw BiliAPIError.missingPayload }
        return data
    }

    private nonisolated static func isSuccessfulDynamicFeedResponse(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let code = object["code"] as? NSNumber,
            code.intValue == 0,
            let payload = object["data"],
            !(payload is NSNull)
        else { return false }
        return true
    }

    private nonisolated static func decodeDynamicFeedResponse(
        _ data: Data
    ) async throws -> BiliResponse<DynamicFeedData> {
        try await Task.detached(priority: .utility) {
            try JSONDecoder.bili.decode(BiliResponse<DynamicFeedData>.self, from: data)
        }.value
    }

    func fetchDynamicPortal() async throws -> DynamicPortalData {
        let context = await dynamicFeedRequestContext()
        guard context.isLoggedIn else { throw BiliAPIError.missingSESSDATA }
        let response: BiliResponse<DynamicPortalData> = try await get(
            base: baseURL,
            path: "/x/polymer/web-dynamic/v1/portal",
            query: [
                "up_list_more": "1",
                "web_location": "333.1365",
            ],
            cookieHeader: context.cookieHeader,
            responseCachePolicy: .brief
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard let data = response.payload else { throw BiliAPIError.missingPayload }
        return data
    }

    func fetchDynamicDetail(id: String) async throws -> DynamicFeedItem {
        let dynamicID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !dynamicID.isEmpty else {
            throw BiliAPIError.api(code: -1, message: "动态 ID 无效")
        }

        let context = await dynamicFeedRequestContext()
        let cookieHeader = Self.uploaderDynamicCookieHeader(
            isLoggedIn: context.isLoggedIn,
            authenticatedCookieHeader: context.cookieHeader,
            anonymousCookieHeader: context.anonymousCookieHeader
        )
        let response: BiliResponse<DynamicDetailData> = try await get(
            base: baseURL,
            path: "/x/polymer/web-dynamic/v1/detail",
            query: [
                "timezone_offset": "-480",
                "id": dynamicID,
                "features": dynamicWebFeatures,
                "gaia_source": "Athena",
                "web_location": "333.1330",
                "x-bili-device-req-json": #"{"platform":"web","device":"pc","spmid":"333.1330"}"#,
            ],
            cookieHeader: cookieHeader,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        guard let item = response.payload?.item else {
            throw BiliAPIError.missingPayload
        }
        return item
    }

    func fetchUploaderDynamicFeed(mid: Int, offset: String? = nil) async throws -> DynamicFeedData {
        guard mid > 0 else { throw BiliAPIError.api(code: -1, message: "UP 主 UID 无效") }
        let context = await dynamicFeedRequestContext()
        let cookieHeader = Self.uploaderDynamicCookieHeader(
            isLoggedIn: context.isLoggedIn,
            authenticatedCookieHeader: context.cookieHeader,
            anonymousCookieHeader: context.anonymousCookieHeader
        )

        do {
            return try await requestUploaderDynamicFeed(mid: mid, offset: offset, cookieHeader: cookieHeader)
        } catch let error as BiliAPIError {
            guard case .api(let code, _) = error, code == -352 else {
                throw error
            }

            // Bilibili rotates WBI keys independently; retry once with a fresh signature.
            await clearWBIKeysForDynamicFeed()
            return try await requestUploaderDynamicFeed(mid: mid, offset: offset, cookieHeader: cookieHeader)
        }
    }

    private func requestUploaderDynamicFeed(
        mid: Int,
        offset: String?,
        cookieHeader: String
    ) async throws -> DynamicFeedData {
        let keys = try await fetchWBIKeys(priority: URLSessionTask.defaultPriority)
        let signed = WBISigner.sign(
            [
                "offset": offset ?? "",
                "host_mid": String(mid),
                "timezone_offset": "-480",
                "features": dynamicWebFeatures,
                "platform": "web",
                "web_location": "333.1387",
                "dm_img_list": "[]",
                "dm_img_str": Self.randomAlphaNumeric(length: 16),
                "dm_cover_img_str": Self.randomAlphaNumeric(length: 32),
                "dm_img_inter": #"{"ds":[],"wh":[0,0,0],"of":[0,0,0]}"#,
                "x-bili-device-req-json": #"{"platform":"web","device":"pc","spmid":"333.1387"}"#,
            ], keys: keys)
        let response: BiliResponse<DynamicFeedData> = try await get(
            base: baseURL,
            path: "/x/polymer/web-dynamic/v1/feed/space",
            query: signed,
            referer: "https://space.bilibili.com/\(mid)/dynamic",
            userAgent: dynamicUploaderWebUserAgent,
            cookieHeader: cookieHeader,
            additionalHeaders: ["Origin": "https://space.bilibili.com"],
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard let data = response.payload else { throw BiliAPIError.missingPayload }
        return data
    }
}

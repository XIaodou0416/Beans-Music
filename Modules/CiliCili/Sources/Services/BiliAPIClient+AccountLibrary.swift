import Foundation

nonisolated struct AccountHistoryCursor: Equatable {
    let max: Int
    let viewAt: Int
}

nonisolated struct AccountVideoEntryPage {
    let entries: [AccountVideoEntry]
    let hasMore: Bool
    let nextHistoryCursor: AccountHistoryCursor?
}

extension BiliAPIClient {
    func fetchAccountHistory(page: Int = 1, pageSize: Int = 20) async throws -> [AccountVideoEntry] {
        if page <= 1 {
            return try await fetchAccountHistoryPage(pageSize: pageSize).entries
        }
        var cursor: AccountHistoryCursor?
        var entries: [AccountVideoEntry] = []
        for _ in 1...page {
            let page = try await fetchAccountHistoryPage(cursor: cursor, pageSize: pageSize)
            entries = page.entries
            cursor = page.nextHistoryCursor
            if !page.hasMore {
                break
            }
        }
        return entries
    }

    func fetchAccountHistoryPage(
        cursor: AccountHistoryCursor? = nil,
        pageSize: Int = 20
    ) async throws -> AccountVideoEntryPage {
        let context = await accountLibraryRequestContext(purpose: .historyRead)
        guard context.isLoggedIn else { throw BiliAPIError.missingSESSDATA }
        let previousCursor = cursor
        let response: BiliResponse<DynamicJSONValue> = try await get(
            base: baseURL,
            path: "/x/web-interface/history/cursor",
            query: [
                "type": "archive",
                "ps": String(pageSize),
                "max": String(cursor?.max ?? 0),
                "view_at": String(cursor?.viewAt ?? 0),
            ],
            cookieHeader: context.cookieHeader
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        let entries = response.payload?.accountVideoEntries ?? []
        let payloadCursor = Self.accountHistoryCursor(from: response.payload)
        let nextCursor = Self.accountHistoryCursor(fromLastEntryIn: entries) ?? payloadCursor
        let cursorCanAdvance = nextCursor.map { $0 != previousCursor && $0.viewAt > 0 } ?? false
        return AccountVideoEntryPage(
            entries: entries,
            hasMore: !entries.isEmpty && cursorCanAdvance,
            nextHistoryCursor: nextCursor
        )
    }

    func fetchVideoHistoryProgress(aid: Int) async throws -> VideoHistoryProgress {
        let context = await accountLibraryRequestContext(purpose: .historyRead)
        guard context.isLoggedIn else { throw BiliAPIError.missingSESSDATA }
        let response: BiliResponse<VideoHistoryProgress> = try await get(
            base: baseURL,
            path: "/x/v2/history",
            query: [
                "aid": String(aid),
                "type": "3",
            ],
            referer: "https://www.bilibili.com/video/av\(aid)",
            cookieHeader: context.cookieHeader
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        guard let progress = response.payload else { throw BiliAPIError.missingPayload }
        return progress
    }

    func fetchAccountWatchLater() async throws -> [AccountVideoEntry] {
        let context = await accountLibraryRequestContext(purpose: .historyRead)
        guard context.isLoggedIn else { throw BiliAPIError.missingSESSDATA }
        let response: BiliResponse<DynamicJSONValue> = try await get(
            base: baseURL,
            path: "/x/v2/history/toview",
            query: [:],
            cookieHeader: context.cookieHeader
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        return response.payload?.accountVideoEntries ?? []
    }

    func fetchAccountFavorites(page: Int = 1, pageSize: Int = 20) async throws -> [AccountVideoEntry] {
        let context = await accountLibraryRequestContext(purpose: .interaction)
        guard context.isLoggedIn else { throw BiliAPIError.missingSESSDATA }
        let folders = try await fetchAccountLibraryFavoriteFolders(context: context)
        var entries = [AccountVideoEntry]()
        var seen = Set<String>()
        var lastError: Error?

        for folder in folders where folder.id > 0 && entries.count < pageSize {
            do {
                let response: BiliResponse<DynamicJSONValue> = try await get(
                    base: baseURL,
                    path: "/x/v3/fav/resource/list",
                    query: Self.favoriteResourceListQuery(
                        folderID: folder.id,
                        page: page,
                        pageSize: pageSize
                    ),
                    cookieHeader: context.cookieHeader
                )
                guard response.code == 0 else {
                    throw BiliAPIError.api(code: response.code, message: response.displayMessage)
                }
                for entry in response.payload?.accountVideoEntries ?? [] where seen.insert(entry.id).inserted {
                    entries.append(entry)
                    if entries.count >= pageSize {
                        break
                    }
                }
            } catch {
                lastError = error
            }
        }

        if entries.isEmpty, let lastError {
            throw lastError
        }
        return entries
    }

    func fetchFavoriteFolderVideos(folderID: Int, page: Int = 1, pageSize: Int = 20) async throws -> [AccountVideoEntry]
    {
        try await fetchFavoriteFolderVideoPage(folderID: folderID, page: page, pageSize: pageSize).entries
    }

    func fetchFavoriteFolderVideoPage(
        folderID: Int,
        page: Int = 1,
        pageSize: Int = 20
    ) async throws -> AccountVideoEntryPage {
        let context = await accountLibraryRequestContext(purpose: .interaction)
        guard context.isLoggedIn else { throw BiliAPIError.missingSESSDATA }
        let response: BiliResponse<DynamicJSONValue> = try await get(
            base: baseURL,
            path: "/x/v3/fav/resource/list",
            query: Self.favoriteResourceListQuery(
                folderID: folderID,
                page: page,
                pageSize: pageSize
            ),
            cookieHeader: context.cookieHeader
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        let entries = response.payload?.accountVideoEntries ?? []
        return AccountVideoEntryPage(
            entries: entries,
            hasMore: Self.hasMoreFlag(in: response.payload) ?? (entries.count >= pageSize),
            nextHistoryCursor: nil
        )
    }

    private func fetchAccountLibraryFavoriteFolders(
        context: AccountLibraryRequestContext
    ) async throws -> [FavoriteFolder] {
        guard let userMID = context.currentUserMID, userMID > 0 else {
            throw BiliAPIError.missingPayload
        }
        let response: BiliResponse<FavoriteFolderListData> = try await get(
            base: baseURL,
            path: "/x/v3/fav/folder/created/list-all",
            query: [
                "up_mid": String(userMID),
                "type": "2",
            ],
            cookieHeader: context.cookieHeader
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        return response.payload?.list ?? []
    }

    private static func favoriteResourceListQuery(
        folderID: Int,
        page: Int,
        pageSize: Int
    ) -> [String: String] {
        [
            "media_id": String(folderID),
            "pn": String(page),
            "ps": String(pageSize),
            "keyword": "",
            "order": "mtime",
            "type": "0",
            "tid": "0",
            "platform": "web",
        ]
    }

    private static func accountHistoryCursor(from payload: DynamicJSONValue?) -> AccountHistoryCursor? {
        guard let object = dynamicObject(payload),
            let cursor = dynamicObject(object["cursor"])
        else { return nil }
        guard let max = dynamicInt(cursor["max"]),
            let viewAt = dynamicInt(cursor["view_at"]) ?? dynamicInt(cursor["viewAt"])
        else { return nil }
        return AccountHistoryCursor(max: max, viewAt: viewAt)
    }

    private static func accountHistoryCursor(
        fromLastEntryIn entries: [AccountVideoEntry]
    ) -> AccountHistoryCursor? {
        guard let last = entries.last,
            let aid = last.aid,
            aid > 0
        else { return nil }
        let viewAt = Int(last.savedAt.timeIntervalSince1970)
        guard viewAt > 0 else { return nil }
        return AccountHistoryCursor(max: aid, viewAt: viewAt)
    }

    private static func hasMoreFlag(in payload: DynamicJSONValue?) -> Bool? {
        guard let object = dynamicObject(payload) else { return nil }
        for key in ["has_more", "hasMore", "more"] {
            if let value = dynamicBool(object[key]) {
                return value
            }
        }
        if let cursor = dynamicObject(object["cursor"]) {
            for key in ["has_more", "hasMore", "more"] {
                if let value = dynamicBool(cursor[key]) {
                    return value
                }
            }
        }
        return nil
    }

    private static func dynamicObject(_ value: DynamicJSONValue?) -> [String: DynamicJSONValue]? {
        guard let value else { return nil }
        guard case .object(let object) = value else { return nil }
        return object
    }

    private static func dynamicInt(_ value: DynamicJSONValue?) -> Int? {
        guard let value else { return nil }
        switch value {
        case .number(let raw), .string(let raw):
            return Int(raw) ?? Double(raw).map(Int.init)
        case .bool(let value):
            return value ? 1 : 0
        case .array, .object, .null:
            return nil
        }
    }

    private static func dynamicBool(_ value: DynamicJSONValue?) -> Bool? {
        guard let value else { return nil }
        switch value {
        case .bool(let value):
            return value
        case .number(let raw), .string(let raw):
            let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["1", "true", "yes"].contains(normalized) { return true }
            if ["0", "false", "no"].contains(normalized) { return false }
            return nil
        case .array, .object, .null:
            return nil
        }
    }
}

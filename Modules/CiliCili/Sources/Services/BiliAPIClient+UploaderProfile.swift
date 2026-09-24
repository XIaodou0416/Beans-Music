import Foundation
import OSLog

extension BiliAPIClient {
    nonisolated func uploaderProfileTask(for mid: Int) async -> Task<UploaderProfile, Error>? {
        await state.uploaderProfileTask(for: mid)
    }

    nonisolated func setUploaderProfileTask(_ task: Task<UploaderProfile, Error>, for mid: Int) async {
        await state.setUploaderProfileTask(task, for: mid)
    }

    nonisolated func clearUploaderProfileTask(for mid: Int) async {
        await state.clearUploaderProfileTask(for: mid)
    }

    func fetchUploaderProfile(mid: Int) async throws -> UploaderProfile {
        guard mid > 0 else { throw BiliAPIError.api(code: -1, message: "UP 主 UID 无效") }
        if let task = await uploaderProfileTask(for: mid) {
            return try await task.value
        }
        let task = Task<UploaderProfile, Error>(priority: .utility) { @MainActor [self] in
            async let cardProfile = uploaderProfileResult("card") {
                try await fetchUploaderCardProfile(mid: mid)
            }
            async let appSpaceProfile = uploaderProfileResult("appSpace") {
                try await fetchUploaderAppSpaceProfile(mid: mid)
            }
            async let spaceProfile = uploaderProfileResult("spaceInfo") {
                try await fetchUploaderSpaceProfile(mid: mid)
            }
            async let relationStat = uploaderProfileResult("relationStat") {
                try await fetchUploaderRelationStat(mid: mid)
            }
            async let upStat = uploaderProfileResult("upStat") {
                try await fetchUploaderUpStat(mid: mid)
            }
            async let viewerRelation = uploaderProfileResult("viewerRelation") {
                try await fetchUploaderViewerRelation(mid: mid)
            }

            let card = await cardProfile
            let appSpace = await appSpaceProfile
            let space = await spaceProfile
            let relation = await relationStat
            let up = await upStat
            let viewer = await viewerRelation
            let base = card ?? appSpace ?? space
            guard base != nil || relation != nil || up != nil || viewer != nil else {
                throw BiliAPIError.missingPayload
            }
            let profile =
                (base
                ?? UploaderProfile(
                    card: nil,
                    follower: nil,
                    following: nil,
                    likeNum: nil,
                    archiveCount: nil
                ))
                .merged(with: appSpace)
                .merged(with: space)
                .merged(with: relation?.profilePatch)
                .merged(with: up?.profilePatch)
                .merged(with: viewer?.profilePatch)
            Self.uploaderLogger.info(
                "profileMerged mid=\(mid, privacy: .public) follower=\(profile.follower ?? -1, privacy: .public) followingCount=\(profile.card?.attention ?? -1, privacy: .public) like=\(profile.likeNum ?? -1, privacy: .public) archive=\(profile.archiveCount ?? -1, privacy: .public) following=\(profile.following == true ? "true" : profile.following == false ? "false" : "nil", privacy: .public)"
            )
            return profile
        }
        await setUploaderProfileTask(task, for: mid)
        do {
            let profile = try await task.value
            await clearUploaderProfileTask(for: mid)
            return profile
        } catch {
            await clearUploaderProfileTask(for: mid)
            throw error
        }
    }

    @MainActor
    func fetchUploaderStatsProfile(mid: Int) async throws -> UploaderProfile {
        guard mid > 0 else { throw BiliAPIError.api(code: -1, message: "UP 主 UID 无效") }

        async let appSpaceProfile = uploaderProfileResult("statsAppSpace") {
            try await fetchUploaderAppSpaceProfile(mid: mid)
        }
        async let relationStat = uploaderProfileResult("statsRelation") {
            try await fetchUploaderRelationStat(mid: mid)
        }
        async let upStat = uploaderProfileResult("statsUp") {
            try await fetchUploaderUpStat(mid: mid)
        }
        async let archiveCount = uploaderProfileResult("statsArchive") {
            let page = try await fetchUploaderVideoPage(mid: mid, page: 1)
            guard let count = page.totalCount else { throw BiliAPIError.missingPayload }
            return count
        }
        async let webInitialProfile = uploaderProfileResult("statsWebInitial") {
            try await fetchUploaderWebInitialProfile(mid: mid)
        }

        let appSpace = await appSpaceProfile
        let relation = await relationStat
        let up = await upStat
        let archive = await archiveCount
        let webInitial = await webInitialProfile
        let profile = UploaderProfile(
            card: nil,
            follower: nil,
            following: nil,
            likeNum: nil,
            archiveCount: nil
        )
        .merged(with: appSpace)
        .merged(with: webInitial)
        .merged(with: relation?.profilePatch)
        .merged(with: up?.profilePatch)
        .merged(
            with: archive.map { count in
                UploaderProfile(
                    card: nil,
                    follower: nil,
                    following: nil,
                    likeNum: nil,
                    archiveCount: count
                )
            })

        guard profile.hasVisibleStats else {
            throw BiliAPIError.missingPayload
        }

        Self.uploaderLogger.info(
            "statsMerged mid=\(mid, privacy: .public) follower=\(profile.visibleFollowerCount ?? -1, privacy: .public) followingCount=\(profile.visibleFollowingCount ?? -1, privacy: .public) like=\(profile.visibleLikeCount ?? -1, privacy: .public) archive=\(profile.visibleArchiveCount ?? -1, privacy: .public)"
        )
        return profile
    }

    private func uploaderProfileResult<T>(
        _ source: String,
        operation: () async throws -> T
    ) async -> T? {
        do {
            let value = try await operation()
            Self.uploaderLogger.info("profileSource source=\(source, privacy: .public) status=ok")
            return value
        } catch {
            Self.uploaderLogger.error(
                "profileSource source=\(source, privacy: .public) status=failed error=\(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    private func fetchUploaderCardProfile(mid: Int) async throws -> UploaderProfile {
        let response: BiliResponse<UploaderProfile> = try await get(
            base: baseURL,
            path: "/x/web-interface/card",
            query: ["mid": String(mid), "photo": "false"],
            userAgent: Self.webUserAgent,
            cookieHeader: await uploaderProfileRequestContext().anonymousCookieHeader,
            responseCachePolicy: .detail
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard let profile = response.payload else { throw BiliAPIError.missingPayload }
        return profile
    }

    private func fetchUploaderAppSpaceProfile(mid: Int) async throws -> UploaderProfile {
        let profile = BiliAppSigner.Profile.androidLogin
        let snapshot = await uploaderProfileRequestContext()
        let fields = [
            "build": profile.build,
            "version": profile.appVersion,
            "c_locale": "zh_CN",
            "channel": profile.channel,
            "mobi_app": profile.mobiApp,
            "platform": profile.platform,
            "s_locale": "zh_CN",
            "statistics": profile.statistics,
            "vmid": String(mid),
        ]
        let headerContext = Self.uploaderAppHeaders(
            cookieHeader: snapshot.anonymousCookieHeader,
            profile: profile
        )
        do {
            let signedProfile = try await requestUploaderAppSpaceProfile(
                mid: mid,
                query: BiliAppSigner.sign(fields, profile: profile),
                profile: profile,
                cookieHeader: snapshot.anonymousCookieHeader,
                additionalHeaders: headerContext
            )
            if signedProfile.hasProfileContent {
                return signedProfile
            }
        } catch {
            Self.uploaderLogger.error(
                "appSpace signed failed mid=\(mid, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
        }

        return try await requestUploaderAppSpaceProfile(
            mid: mid,
            query: fields,
            profile: profile,
            cookieHeader: snapshot.anonymousCookieHeader,
            additionalHeaders: headerContext
        )
    }

    private func requestUploaderAppSpaceProfile(
        mid: Int,
        query: [String: String],
        profile: BiliAppSigner.Profile,
        cookieHeader: String,
        additionalHeaders: [String: String]
    ) async throws -> UploaderProfile {
        let response: BiliResponse<UploaderProfile> = try await get(
            base: appURL,
            path: "/x/v2/space",
            query: query,
            referer: "https://space.bilibili.com/\(mid)",
            userAgent: profile.userAgent,
            cookieHeader: cookieHeader,
            additionalHeaders: additionalHeaders,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard let profile = response.payload, profile.hasProfileContent else { throw BiliAPIError.missingPayload }
        return profile
    }

    private func fetchUploaderSpaceProfile(mid: Int) async throws -> UploaderProfile {
        let keys = try await fetchWBIKeys(priority: URLSessionTask.defaultPriority)
        let signed = WBISigner.sign(
            [
                "mid": String(mid),
                "token": "",
                "platform": "web",
                "web_location": "1550101",
                "dm_img_list": "[]",
                "dm_img_str": Self.randomAlphaNumeric(length: 16),
                "dm_cover_img_str": Self.randomAlphaNumeric(length: 32),
                "dm_img_inter": #"{"ds":[],"wh":[0,0,0],"of":[0,0,0]}"#,
            ], keys: keys)
        let response: BiliResponse<UploaderProfile> = try await get(
            base: baseURL,
            path: "/x/space/wbi/acc/info",
            query: signed,
            referer: "https://space.bilibili.com/\(mid)/dynamic",
            userAgent: Self.webUserAgent,
            cookieHeader: await uploaderProfileRequestContext().anonymousCookieHeader,
            additionalHeaders: ["Origin": "https://space.bilibili.com"],
            responseCachePolicy: .detail
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard let profile = response.payload else { throw BiliAPIError.missingPayload }
        return profile
    }

    private func fetchUploaderWebInitialProfile(mid: Int) async throws -> UploaderProfile {
        guard let spaceURL = URL(string: "https://space.bilibili.com") else {
            throw BiliAPIError.invalidURL
        }
        let request = try await makeRequest(
            base: spaceURL,
            path: "/\(mid)",
            query: [:],
            referer: "https://space.bilibili.com/\(mid)",
            userAgent: Self.webUserAgent,
            cookieHeader: await uploaderProfileRequestContext().anonymousCookieHeader,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        let (data, _) = try await data(for: request, priority: URLSessionTask.defaultPriority)
        guard !data.isEmpty else { throw BiliAPIError.emptyData }
        guard let html = String(data: data, encoding: .utf8),
            let json = Self.extractInitialStateJSON(from: html)
        else {
            throw BiliAPIError.missingPayload
        }
        let initialState = try await Self.decode(
            DynamicJSONValue.self,
            from: Data(json.utf8),
            priority: URLSessionTask.defaultPriority
        )
        guard let profile = Self.uploaderProfile(fromInitialState: initialState, targetMID: mid),
            profile.hasVisibleStats
        else {
            throw BiliAPIError.missingPayload
        }
        return profile
    }

    private func fetchUploaderRelationStat(mid: Int) async throws -> UploaderRelationStat {
        let response: BiliResponse<UploaderRelationStat> = try await get(
            base: baseURL,
            path: "/x/relation/stat",
            query: ["vmid": String(mid)],
            referer: "https://space.bilibili.com/\(mid)",
            userAgent: Self.webUserAgent,
            cookieHeader: await uploaderProfileRequestContext().anonymousCookieHeader,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard let stat = response.payload else { throw BiliAPIError.missingPayload }
        return stat
    }

    private func fetchUploaderUpStat(mid: Int) async throws -> UploaderUpStat {
        let response: BiliResponse<UploaderUpStat> = try await get(
            base: baseURL,
            path: "/x/space/upstat",
            query: ["mid": String(mid)],
            referer: "https://space.bilibili.com/\(mid)",
            userAgent: Self.webUserAgent,
            cookieHeader: await uploaderProfileRequestContext().anonymousCookieHeader,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard let stat = response.payload else { throw BiliAPIError.missingPayload }
        return stat
    }

    private func fetchUploaderViewerRelation(mid: Int) async throws -> UploaderViewerRelation {
        let snapshot = await uploaderProfileRequestContext()
        if snapshot.isLoggedIn, !snapshot.cookieHeader.isEmpty {
            do {
                return try await fetchUploaderViewerRelationWithWeb(mid: mid, cookieHeader: snapshot.cookieHeader)
            } catch {
                if snapshot.appAccessKey?.isEmpty != false {
                    throw error
                }
            }
        }
        if let accessKey = snapshot.appAccessKey, !accessKey.isEmpty {
            return try await fetchUploaderViewerRelationWithAppAccessKey(
                mid: mid,
                accessKey: accessKey,
                cookieHeader: snapshot.cookieHeader
            )
        }
        throw BiliAPIError.missingSESSDATA
    }

    private func fetchUploaderViewerRelationWithWeb(mid: Int, cookieHeader: String) async throws
        -> UploaderViewerRelation
    {
        let response: BiliResponse<UploaderViewerRelation> = try await get(
            base: baseURL,
            path: "/x/relation",
            query: ["fid": String(mid)],
            referer: "https://space.bilibili.com/\(mid)",
            userAgent: Self.webUserAgent,
            cookieHeader: cookieHeader,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard let relation = response.payload else { throw BiliAPIError.missingPayload }
        return relation
    }

    private func fetchUploaderViewerRelationWithAppAccessKey(
        mid: Int,
        accessKey: String,
        cookieHeader: String
    ) async throws -> UploaderViewerRelation {
        let profile = BiliAppSigner.Profile.androidLogin
        let query = BiliAppSigner.sign(
            [
                "access_key": accessKey,
                "build": profile.build,
                "c_locale": "zh_CN",
                "channel": profile.channel,
                "fid": String(mid),
                "mobi_app": profile.mobiApp,
                "platform": profile.platform,
                "s_locale": "zh_CN",
                "statistics": profile.statistics,
            ], profile: profile)
        let response: BiliResponse<UploaderViewerRelation> = try await get(
            base: baseURL,
            path: "/x/relation",
            query: query,
            referer: "https://space.bilibili.com/\(mid)",
            userAgent: profile.userAgent,
            cookieHeader: cookieHeader,
            additionalHeaders: Self.uploaderAppHeaders(cookieHeader: cookieHeader, profile: profile),
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard let relation = response.payload else { throw BiliAPIError.missingPayload }
        return relation
    }

    private static func extractInitialStateJSON(from html: String) -> String? {
        let markers = [
            "window.__INITIAL_STATE__=",
            "window.__INITIAL_STATE__ =",
            "__INITIAL_STATE__=",
        ]
        for marker in markers {
            guard let markerRange = html.range(of: marker),
                let json = extractBalancedJSONObject(from: html[markerRange.upperBound...])
            else { continue }
            return json
        }
        return nil
    }

    private struct UploaderInitialStats {
        var mid: Int?
        var name: String?
        var face: String?
        var sign: String?
        var fans: Int?
        var attention: Int?
        var likeNum: Int?
        var archiveCount: Int?

        var hasAnyValue: Bool {
            mid != nil || name?.isEmpty == false || face?.isEmpty == false || sign?.isEmpty == false
                || fans != nil || attention != nil || likeNum != nil || archiveCount != nil
        }

        var hasVisibleStats: Bool {
            fans != nil || attention != nil || likeNum != nil || archiveCount != nil
        }
    }

    private static func uploaderProfile(
        fromInitialState value: DynamicJSONValue,
        targetMID: Int
    ) -> UploaderProfile? {
        var stats = UploaderInitialStats()
        collectUploaderInitialStats(value, targetMID: targetMID, into: &stats)
        guard stats.hasVisibleStats else { return nil }

        let card: UploaderCard? =
            stats.hasAnyValue
            ? UploaderCard(
                mid: stats.mid ?? targetMID,
                name: stats.name,
                face: stats.face?.normalizedBiliURL(),
                sign: stats.sign,
                fans: stats.fans,
                attention: stats.attention,
                likes: UploaderLikes(likeNum: stats.likeNum)
            )
            : nil

        return UploaderProfile(
            card: card,
            follower: stats.fans,
            following: nil,
            likeNum: stats.likeNum,
            archiveCount: stats.archiveCount
        )
    }

    private static func collectUploaderInitialStats(
        _ value: DynamicJSONValue,
        targetMID: Int,
        into stats: inout UploaderInitialStats
    ) {
        switch value {
        case .array(let values):
            for item in values {
                collectUploaderInitialStats(item, targetMID: targetMID, into: &stats)
            }
        case .object(let object):
            absorbUploaderInitialObject(object, targetMID: targetMID, into: &stats)
            for item in object.values {
                collectUploaderInitialStats(item, targetMID: targetMID, into: &stats)
            }
        case .string, .number, .bool, .null:
            break
        }
    }

    private static func absorbUploaderInitialObject(
        _ object: [String: DynamicJSONValue],
        targetMID: Int,
        into stats: inout UploaderInitialStats
    ) {
        if case .object(let cardObject)? = object["card"] {
            absorbUploaderInitialCardObject(cardObject, targetMID: targetMID, into: &stats)
        }
        absorbUploaderInitialCardObject(object, targetMID: targetMID, into: &stats)
        if case .object(let archiveObject)? = object["archive"] {
            stats.archiveCount = stats.archiveCount ?? uploaderArchiveCount(from: archiveObject)
        }
    }

    private static func absorbUploaderInitialCardObject(
        _ object: [String: DynamicJSONValue],
        targetMID: Int,
        into stats: inout UploaderInitialStats
    ) {
        let objectMID = firstUploaderInt(object, keys: ["mid", "vmid", "uid"])
        guard objectMID == nil || objectMID == targetMID else { return }

        let fans = firstUploaderInt(object, keys: ["fans", "follower"])
        let attention = firstUploaderInt(object, keys: ["attention", "friend", "following"])
        let likeNum = uploaderLikeCount(from: object)
        let hasProfileFields =
            fans != nil || attention != nil || likeNum != nil
            || object["name"]?.textValueForDynamicParsing?.isEmpty == false
            || object["face"]?.textValueForDynamicParsing?.isEmpty == false
            || object["sign"]?.textValueForDynamicParsing?.isEmpty == false
        guard hasProfileFields else { return }

        stats.mid = stats.mid ?? objectMID
        stats.name = stats.name ?? object["name"]?.textValueForDynamicParsing
        stats.face = stats.face ?? object["face"]?.textValueForDynamicParsing
        stats.sign = stats.sign ?? object["sign"]?.textValueForDynamicParsing
        stats.fans = stats.fans ?? fans
        stats.attention = stats.attention ?? attention
        stats.likeNum = stats.likeNum ?? likeNum
    }

    private static func uploaderLikeCount(from object: [String: DynamicJSONValue]) -> Int? {
        if let direct = firstUploaderInt(object, keys: ["like_num"]) { return direct }
        if case .object(let likesObject)? = object["likes"] {
            return firstUploaderInt(likesObject, keys: ["like_num", "count", "likes"])
        }
        return firstUploaderInt(object, keys: ["likes"])
    }

    private static func uploaderArchiveCount(from object: [String: DynamicJSONValue]) -> Int? {
        firstUploaderInt(object, keys: ["count", "archive_count"])
            ?? uploaderArrayCount(object["item"])
            ?? uploaderArrayCount(object["items"])
    }

    private static func firstUploaderInt(
        _ object: [String: DynamicJSONValue],
        keys: [String]
    ) -> Int? {
        keys.lazy.compactMap { uploaderIntValue(object[$0]) }.first
    }

    private static func uploaderArrayCount(_ value: DynamicJSONValue?) -> Int? {
        guard case .array(let values)? = value else { return nil }
        return values.count
    }

    private static func uploaderIntValue(_ value: DynamicJSONValue?) -> Int? {
        switch value {
        case .number(let raw), .string(let raw):
            return Int(raw) ?? Double(raw).map(Int.init)
        case .bool, .array, .object, .null, .none:
            return nil
        }
    }
}

import Foundation

// Independent Swift implementation based on public request contracts, with
// native page organization informed by PiliPlus and cilicili.
extension BilibiliAPI {
    static func number(_ value: Any?) -> Int {
        (value as? NSNumber)?.intValue ?? Int(value as? String ?? "") ?? 0
    }
    private func checkedData(_ root: [String: Any]) throws -> [String: Any] {
        let code = Self.number(root["code"])
        guard root["code"] != nil, code == 0 else {
            let message = Self.text(root["message"] ?? root["msg"])
            throw BilibiliError(message: code == -101 ? "请先登录哔哩哔哩" : "\(message.isEmpty ? "请求失败" : message)（\(code)）")
        }
        return root["data"] as? [String: Any] ?? [:]
    }
    private func form(_ path: String, fields: [String: String]) async throws {
        let credentials = await BilibiliAuth.shared.cookieHeader
        var request: URLRequest
        do { request = try BilibiliNativeRequestPolicy.request(path: path, fields: fields, cookie: credentials) }
        catch { throw BilibiliError(message: "请先扫码登录哔哩哔哩，再进行此操作") }
        Self.headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        // Mutations run once, only in response to a user's explicit action.
        // No automatic retry for coins or comments after a lost response.
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BilibiliError(message: "未能确认操作结果，请刷新状态后再试")
        }
        _ = try checkedData(root)
    }

    func nativeVideo(_ track: Song) async throws -> BilibiliVideoInfo {
        let data = try await video(track.bilibiliID ?? "")
        let owner = data["owner"] as? [String: Any] ?? [:]
        let stats = data["stat"] as? [String: Any] ?? [:]
        let creator = Artist(id: Self.text(owner["mid"]), name: Self.text(owner["name"]), coverURL: Self.image(owner["face"]), source: .bilibili)
        let pages = data["pages"] as? [[String: Any]] ?? []
        let season = data["ugc_season"] as? [String: Any]
        let collection: BilibiliSeries?
        if let season, !Self.text(season["id"]).isEmpty {
            collection = BilibiliSeries(number: Self.text(season["id"]), ownerID: creator.id, ownerName: creator.name,
                                       title: Self.text(season["title"]), cover: Self.image(season["cover"]), description: Self.text(season["intro"]),
                                       count: Self.number(season["ep_count"]), kind: .season)
        } else { collection = nil }
        return BilibiliVideoInfo(song: song(data) ?? track, aid: Self.text(data["aid"]), owner: creator,
                                 description: Self.text(data["desc"]), views: Self.number(stats["view"]), likes: Self.number(stats["like"]),
                                 coins: Self.number(stats["coin"]), favorites: Self.number(stats["favorite"]),
                                 published: Date(timeIntervalSince1970: Double(Self.number(data["pubdate"]))),
                                 parts: pages.compactMap { song(data, part: $0) }, collection: collection)
    }
    func nativeVideoURLs(_ track: Song, quality: Int = 64) async throws -> [URL] {
        let data = try await video(track.bilibiliID ?? "")
        let cid = track.bilibiliID?.split(separator: ":").dropFirst().first.map(String.init) ?? Self.text(data["cid"])
        let result = try await get("/x/player/playurl", ["bvid": Self.text(data["bvid"]), "cid": cid,
                                                       "qn": String(quality), "fnval": "1", "platform": "html5", "high_quality": "1"])
        let urls = BilibiliProtocol.progressiveURLs(result)
        guard !urls.isEmpty else { throw BilibiliError(message: "该视频暂未返回兼容的视频地址，请换清晰度或重试") }
        return urls
    }
    func nativeInteraction(aid: String) async throws -> BilibiliInteractionState {
        let data = try await get("/x/web-interface/archive/relation", ["aid": aid])
        return BilibiliInteractionState(liked: (data["like"] as? Bool) ?? (Self.number(data["like"]) > 0),
                                        coins: Self.number(data["coin"]), favorited: (data["favorite"] as? Bool) ?? false)
    }
    func nativeLike(aid: String, liked: Bool) async throws {
        try await form("/x/web-interface/archive/like", fields: ["aid": aid, "like": liked ? "1" : "2"])
    }
    func nativeCoin(aid: String, count: Int) async throws {
        guard (1...2).contains(count) else { throw BilibiliError(message: "投币数量无效") }
        try await form("/x/web-interface/coin/add", fields: ["aid": aid, "multiply": String(count), "select_like": "0"])
    }
    func nativeFolders(aid: String) async throws -> [BilibiliFavoriteFolder] {
        let mid = await BilibiliAuth.shared.accountID
        guard !mid.isEmpty else { throw BilibiliError(message: "请先登录哔哩哔哩") }
        let data = try await get("/x/v3/fav/folder/created/list-all", ["up_mid": mid, "type": "2", "rid": aid])
        return (data["list"] as? [[String: Any]] ?? []).map {
            BilibiliFavoriteFolder(id: Self.text($0["id"]), title: Self.text($0["title"]), containsVideo: Self.number($0["fav_state"]) == 1)
        }
    }
    func nativeFavorite(aid: String, add: Set<String>, remove: Set<String>) async throws {
        guard !add.isEmpty || !remove.isEmpty else { return }
        try await form("/x/v3/fav/resource/deal", fields: ["rid": aid, "type": "2", "platform": "web",
            "add_media_ids": add.sorted().joined(separator: ","), "del_media_ids": remove.sorted().joined(separator: ",")])
    }
    func nativeFollow(id: String, follow: Bool) async throws {
        try await form("/x/relation/modify", fields: ["fid": id, "act": follow ? "1" : "2", "re_src": "11"])
    }
    func nativeComment(aid: String, message: String, root: String? = nil) async throws {
        let value = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 1000 else { throw BilibiliError(message: "请输入1到1000字的评论") }
        var fields = ["oid": aid, "type": "1", "message": value, "plat": "1"]
        if let root { fields["root"] = root; fields["parent"] = root }
        try await form("/x/v2/reply/add", fields: fields)
    }
    func nativeCommentLike(aid: String, reply: String, like: Bool) async throws {
        try await form("/x/v2/reply/action", fields: ["oid": aid, "type": "1", "rpid": reply, "action": like ? "1" : "0"])
    }
    func nativeReplies(aid: String, page: Int, hot: Bool, root: String? = nil) async throws -> BilibiliReplies {
        var params = ["type": "1", "oid": aid, "pn": String(page), "ps": "20", "sort": hot ? "2" : "0"]
        if let root { params["root"] = root }
        let data = try await get(root == nil ? "/x/v2/reply" : "/x/v2/reply/reply", params)
        let rawRows = data["replies"] as? [[String: Any]] ?? []
        let total = Self.number((data["page"] as? [String: Any])?["count"])
        let rows = rawRows.compactMap { row -> BilibiliReply? in
            let id = Self.text(row["rpid_str"] ?? row["rpid"])
            guard !id.isEmpty else { return nil }
            let member = row["member"] as? [String: Any] ?? [:]
            let content = row["content"] as? [String: Any] ?? [:]
            return BilibiliReply(id: id, author: Artist(id: Self.text(member["mid"]), name: Self.text(member["uname"]), coverURL: Self.image(member["avatar"]), source: .bilibili),
                                 message: Self.text(content["message"]), date: Date(timeIntervalSince1970: Double(Self.number(row["ctime"]))),
                                 likeCount: Self.number(row["like"]), liked: Self.number(row["action"]) == 1, replyCount: Self.number(row["rcount"]))
        }
        return BilibiliReplies(items: rows, total: total, hasMore: !rawRows.isEmpty && page * 20 < total)
    }
}

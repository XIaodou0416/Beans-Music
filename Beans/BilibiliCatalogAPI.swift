import Foundation

extension BilibiliAPI {
    func feedItem(_ row: [String: Any], owner: Artist? = nil) -> BilibiliFeedVideo? {
        var row = row
        if row["duration"] == nil { row["duration"] = row["length"] }
        if row["owner"] == nil, row["author"] == nil, let owner {
            row["owner"] = ["mid": owner.id, "name": owner.name, "face": owner.coverURL?.absoluteString ?? ""]
        }
        guard let track = song(row) else { return nil }
        let uploader = row["owner"] as? [String: Any] ?? [:]
        let stat = row["stat"] as? [String: Any] ?? [:]
        return BilibiliFeedVideo(song: track, ownerAvatarURL: Self.image(uploader["face"] ?? row["upic"]),
                                 playCount: Self.number(stat["view"] ?? row["play"]), danmakuCount: Self.number(stat["danmaku"] ?? row["video_review"]))
    }
    func searchPage(_ query: String, kind: String, page: Int) async throws -> [String: Any] {
        let params = ["keyword": query, "search_type": kind, "page": String(page), "page_size": "20"]
        do { return try await get("/x/web-interface/wbi/search/type", params, signed: true, identity: true, ttl: 120) }
        catch is CancellationError { throw CancellationError() }
        catch { return try await get("/x/web-interface/search/type", params, identity: true, ttl: 120) }
    }
    func videoSearch(_ query: String, page: Int) async throws -> (items: [BilibiliFeedVideo], more: Bool) {
        let data = try await searchPage(query, kind: "video", page: page)
        let rows = data["result"] as? [[String: Any]] ?? []
        return (rows.compactMap { feedItem($0) }, !rows.isEmpty && page < Self.number(data["numPages"]))
    }
    func upSearch(_ query: String, page: Int) async throws -> (items: [Artist], more: Bool) {
        let data = try await searchPage(query, kind: "bili_user", page: page)
        let rows = data["result"] as? [[String: Any]] ?? []
        let items = rows.compactMap { row -> Artist? in
            let id = Self.text(row["mid"])
            guard !id.isEmpty else { return nil }
            return Artist(id: id, name: Self.text(row["uname"]), coverURL: Self.image(row["upic"]), source: .bilibili)
        }
        return (items, !rows.isEmpty && page < Self.number(data["numPages"]))
    }
    func channelVideos(_ channel: BilibiliChannel, page: Int, force: Bool = false) async throws -> (items: [BilibiliFeedVideo], more: Bool) {
        if channel == .recommended {
            let result = try await popularVideos(page: page, force: force)
            return (result.videos, result.hasMore)
        }
        let data = try await get("/x/web-interface/ranking/v2", ["rid": channel.regionID, "type": "all"], identity: true, ttl: force ? 0 : 900)
        let rows = data["list"] as? [[String: Any]] ?? []
        let start = max(0, page - 1) * 20
        return (Array(rows.dropFirst(start).prefix(20)).compactMap { feedItem($0) }, start + 20 < rows.count)
    }
    func upProfile(_ id: String) async throws -> BilibiliUPProfile {
        let data = try await get("/x/web-interface/card", ["mid": id])
        let row = data["card"] as? [String: Any] ?? [:]
        let owner = Artist(id: id, name: Self.text(row["name"]), coverURL: Self.image(row["face"]), source: .bilibili)
        return BilibiliUPProfile(artist: owner, sign: Self.text(row["sign"]), followers: Self.number(data["follower"]), following: data["following"] as? Bool ?? false)
    }
    func upVideos(_ owner: Artist, page: Int) async throws -> (items: [BilibiliFeedVideo], more: Bool) {
        let data = try await get("/x/space/wbi/arc/search", ["mid": owner.id, "ps": "30", "pn": String(page), "order": "pubdate"], signed: true, identity: true, ttl: 120)
        let rows = (data["list"] as? [String: Any])?["vlist"] as? [[String: Any]] ?? []
        let total = Self.number((data["page"] as? [String: Any])?["count"])
        return (rows.compactMap { feedItem($0, owner: owner) }, !rows.isEmpty && page * 30 < total)
    }
}

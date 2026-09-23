import Foundation

extension BilibiliAPI {
    func liveRooms(page: Int) async throws -> (items: [BilibiliLiveRoom], more: Bool) {
        guard (1...200).contains(page) else { throw BilibiliError(message: "直播页码无效") }
        let url = URL(string: "https://api.live.bilibili.com/xlive/web-interface/v1/webMain/getMoreRecList?platform=web&page=\(page)&page_size=20")!
        let (root, _) = try await raw(url, cookieOverride: "")
        guard Self.number(root["code"]) == 0 else { throw BilibiliError(message: "直播列表加载失败") }
        let rows = (root["data"] as? [String: Any])?["recommend_room_list"] as? [[String: Any]] ?? []
        let items = rows.compactMap { row -> BilibiliLiveRoom? in
            let id = Self.text(row["roomid"] ?? row["room_id"])
            guard !id.isEmpty else { return nil }
            let watched = row["watched_show"] as? [String: Any] ?? [:]
            return BilibiliLiveRoom(id: id, title: Self.text(row["title"]), cover: Self.image(row["cover"] ?? row["keyframe"]),
                owner: Artist(id: Self.text(row["uid"]), name: Self.text(row["uname"]), coverURL: Self.image(row["face"]), source: .bilibili),
                viewers: Self.text(watched["text_small"] ?? row["online"]))
        }
        return (items, rows.count >= 20)
    }
    func liveURLs(_ room: String) async throws -> [URL] {
        guard !room.isEmpty, room.allSatisfy(\.isNumber) else { throw BilibiliError(message: "直播间编号无效") }
        let url = URL(string: "https://api.live.bilibili.com/room/v1/Room/playUrl?cid=\(room)&quality=4&platform=h5&ptype=8")!
        let (root, _) = try await raw(url)
        guard Self.number(root["code"]) == 0 else { throw BilibiliError(message: "该直播间当前不可播放") }
        let rows = (root["data"] as? [String: Any])?["durl"] as? [[String: Any]] ?? []
        let urls = rows.compactMap { row -> URL? in
            guard let url = Self.image(row["url"]), url.path.hasSuffix(".m3u8"), ["https", "http"].contains(url.scheme ?? "") else { return nil }
            return url
        }
        guard !urls.isEmpty else { throw BilibiliError(message: "直播已结束或没有可播放地址") }
        return urls
    }
}

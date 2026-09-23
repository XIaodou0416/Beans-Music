import Foundation

/// Fetch a single UP's visible collection page only after opening that UP.
/// No account enumeration, background crawling, or automatic recursive fetches.
extension BilibiliAPI {
    func upCollections(_ owner: Artist, page: Int) async throws -> (items: [BilibiliSeries], more: Bool) {
        guard !owner.id.isEmpty, owner.id.allSatisfy(\.isNumber), (1...200).contains(page) else {
            throw BilibiliError(message: "UP主或页码无效")
        }
        let data = try await get("/x/polymer/web-space/seasons_series_list", ["mid": owner.id, "page_num": String(page), "page_size": "20"], ttl: 180)
        let lists = data["items_lists"] as? [String: Any] ?? [:]
        var items: [BilibiliSeries] = []
        for (key, kind) in [("seasons_list", BilibiliSeries.Kind.season), ("series_list", BilibiliSeries.Kind.series)] {
            for row in lists[key] as? [[String: Any]] ?? [] {
                let meta = row["meta"] as? [String: Any] ?? [:]
                let id = Self.text(meta[kind == .season ? "season_id" : "series_id"])
                guard !id.isEmpty else { continue }
                let archives = row["archives"] as? [[String: Any]] ?? []
                items.append(BilibiliSeries(number: id, ownerID: owner.id, ownerName: owner.name, title: Self.text(meta["name"]),
                    cover: Self.image(meta["cover"] ?? archives.first?["pic"]), description: Self.text(meta["description"]),
                    count: Self.number(meta["total"]), kind: kind))
            }
        }
        let total = Self.number((lists["page"] as? [String: Any])?["total"])
        return (items, !items.isEmpty && page * 20 < total)
    }
    func seriesVideos(_ collection: BilibiliSeries, page: Int) async throws -> (items: [BilibiliFeedVideo], more: Bool) {
        guard !collection.ownerID.isEmpty, collection.ownerID.allSatisfy(\.isNumber),
              !collection.number.isEmpty, collection.number.allSatisfy(\.isNumber), (1...500).contains(page) else {
            throw BilibiliError(message: "合集编号或页码无效")
        }
        let data: [String: Any]
        if collection.kind == .season {
            data = try await get("/x/polymer/web-space/seasons_archives_list", ["mid": collection.ownerID, "season_id": collection.number,
                "sort_reverse": "false", "page_size": "30", "page_num": String(page)], ttl: 180)
        } else {
            data = try await get("/x/series/archives", ["mid": collection.ownerID, "series_id": collection.number,
                "sort": "desc", "ps": "30", "pn": String(page)], ttl: 180)
        }
        let rows = data["archives"] as? [[String: Any]] ?? []
        let total = Self.number((data["page"] as? [String: Any])?["total"])
        let owner = Artist(id: collection.ownerID, name: collection.ownerName, coverURL: nil, source: .bilibili)
        return (rows.compactMap { feedItem($0, owner: owner) }, !rows.isEmpty && page * 30 < total)
    }
}

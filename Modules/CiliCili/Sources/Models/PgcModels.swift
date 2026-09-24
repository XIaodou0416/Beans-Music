import Foundation

nonisolated struct PgcSeasonRoute: Hashable, Identifiable {
    let seasonID: Int
    let title: String
    let cover: String?

    var id: Int { seasonID }

    init?(media: SearchMediaItem) {
        guard let seasonID = media.seasonID else { return nil }
        self.seasonID = seasonID
        self.title = media.title
        self.cover = media.cover?.normalizedBiliURL()
    }
}

nonisolated struct PgcSeasonInfo: Decodable, Hashable, Sendable {
    let seasonID: Int?
    let mediaID: Int?
    let title: String?
    let seasonTitle: String?
    let subtitle: String?
    let cover: String?
    let evaluate: String?
    let episodes: [PgcEpisode]
    let sections: [PgcEpisodeSection]
    let rating: PgcRating?
    let stat: PgcSeasonStat?
    let upInfo: PgcUpInfo?
    let userStatus: PgcUserStatus?

    enum CodingKeys: String, CodingKey {
        case title, subtitle, cover, evaluate, episodes, rating, stat
        case sections = "section"
        case seasonID = "season_id"
        case mediaID = "media_id"
        case seasonTitle = "season_title"
        case upInfo = "up_info"
        case userStatus = "user_status"
    }

    init(
        seasonID: Int?,
        mediaID: Int?,
        title: String?,
        seasonTitle: String?,
        subtitle: String?,
        cover: String?,
        evaluate: String?,
        episodes: [PgcEpisode],
        sections: [PgcEpisodeSection],
        rating: PgcRating?,
        stat: PgcSeasonStat?,
        upInfo: PgcUpInfo?,
        userStatus: PgcUserStatus?
    ) {
        self.seasonID = seasonID
        self.mediaID = mediaID
        self.title = title
        self.seasonTitle = seasonTitle
        self.subtitle = subtitle
        self.cover = cover
        self.evaluate = evaluate
        self.episodes = episodes
        self.sections = sections
        self.rating = rating
        self.stat = stat
        self.upInfo = upInfo
        self.userStatus = userStatus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seasonID = container.pgcDecodeLossyIntIfPresent(forKey: .seasonID)
        mediaID = container.pgcDecodeLossyIntIfPresent(forKey: .mediaID)
        title = container.pgcDecodeLossyStringIfPresent(forKey: .title)
        seasonTitle = container.pgcDecodeLossyStringIfPresent(forKey: .seasonTitle)
        subtitle = container.pgcDecodeLossyStringIfPresent(forKey: .subtitle)
        cover = container.pgcDecodeLossyStringIfPresent(forKey: .cover)
        evaluate = container.pgcDecodeLossyStringIfPresent(forKey: .evaluate)
        episodes = try container.decodeIfPresent([PgcEpisode].self, forKey: .episodes) ?? []
        sections = try container.decodeIfPresent([PgcEpisodeSection].self, forKey: .sections) ?? []
        rating = try container.decodeIfPresent(PgcRating.self, forKey: .rating)
        stat = try container.decodeIfPresent(PgcSeasonStat.self, forKey: .stat)
        upInfo = try container.decodeIfPresent(PgcUpInfo.self, forKey: .upInfo)
        userStatus = try container.decodeIfPresent(PgcUserStatus.self, forKey: .userStatus)
    }

    var displayTitle: String {
        seasonTitle?.removingHTMLTags().pgcTrimmedNonEmpty
            ?? title?.removingHTMLTags().pgcTrimmedNonEmpty
            ?? "番剧"
    }

    var normalizedCover: String? {
        cover?.normalizedBiliURL()
    }

    var owner: VideoOwner? {
        guard let upInfo else { return nil }
        return VideoOwner(
            mid: upInfo.mid ?? 0,
            name: upInfo.name ?? "番剧",
            face: upInfo.avatar?.normalizedBiliURL()
        )
    }

    var continueWatchingEpisode: PgcEpisode? {
        guard let lastEpID = userStatus?.progress?.lastEpID else { return nil }
        return allPlayableEpisodes.first { episode in
            episode.epID == lastEpID || episode.idValue == lastEpID
        }
    }

    var preferredPlaybackEpisode: PgcEpisode? {
        continueWatchingEpisode ?? allPlayableEpisodes.first
    }

    var allPlayableEpisodes: [PgcEpisode] {
        var seen = Set<Int>()
        return (episodes + sections.flatMap(\.episodes)).filter { episode in
            guard episode.videoItem(in: self) != nil else { return false }
            return seen.insert(episode.id).inserted
        }
    }

    var selectableEpisodes: [PgcEpisode] {
        episodes.isEmpty ? allPlayableEpisodes : episodes
    }

    func withFallbackSeasonID(_ fallbackSeasonID: Int) -> PgcSeasonInfo {
        guard seasonID == nil else { return self }
        return PgcSeasonInfo(
            seasonID: fallbackSeasonID,
            mediaID: mediaID,
            title: title,
            seasonTitle: seasonTitle,
            subtitle: subtitle,
            cover: cover,
            evaluate: evaluate,
            episodes: episodes,
            sections: sections,
            rating: rating,
            stat: stat,
            upInfo: upInfo,
            userStatus: userStatus
        )
    }

    func relatedEpisodeVideoItems(excluding detail: VideoItem, limit: Int) -> [VideoItem] {
        let currentEpisodeID = detail.pgcEpisodeID
        let currentCID = detail.cid
        let currentBVID = detail.bvid.trimmingCharacters(in: .whitespacesAndNewlines)
        return allPlayableEpisodes
            .filter { episode in
                if let currentEpisodeID,
                   episode.epID == currentEpisodeID || episode.idValue == currentEpisodeID {
                    return false
                }
                if let currentCID, episode.cid == currentCID {
                    return false
                }
                if let bvid = episode.bvid?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !bvid.isEmpty,
                   bvid == currentBVID {
                    return false
                }
                return true
            }
            .compactMap { episode in
                episode.videoItem(in: self, recommendReason: "同番剧")
            }
            .prefix(limit)
            .map { $0 }
    }
}

nonisolated struct PgcEpisodeSection: Decodable, Hashable, Sendable {
    let episodes: [PgcEpisode]

    enum CodingKeys: String, CodingKey {
        case episodes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        episodes = try container.decodeIfPresent([PgcEpisode].self, forKey: .episodes) ?? []
    }
}

nonisolated struct PgcEpisode: Decodable, Hashable, Identifiable, Sendable {
    let idValue: Int?
    let epID: Int?
    let aid: Int?
    let bvid: String?
    let cid: Int?
    let title: String?
    let longTitle: String?
    let showTitle: String?
    let cover: String?
    let badge: String?
    let duration: Int?
    let pubTime: Int?
    let dimension: VideoDimension?

    enum CodingKeys: String, CodingKey {
        case aid, bvid, cid, title, cover, badge, duration, dimension
        case idValue = "id"
        case epID = "ep_id"
        case longTitle = "long_title"
        case showTitle = "show_title"
        case pubTime = "pub_time"
        case releaseDate = "release_date"
    }

    var id: Int {
        epID ?? idValue ?? cid ?? aid ?? 0
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        idValue = container.pgcDecodeLossyIntIfPresent(forKey: .idValue)
        epID = container.pgcDecodeLossyIntIfPresent(forKey: .epID)
        aid = container.pgcDecodeLossyIntIfPresent(forKey: .aid)
        bvid = container.pgcDecodeLossyStringIfPresent(forKey: .bvid)
        cid = container.pgcDecodeLossyIntIfPresent(forKey: .cid)
        title = container.pgcDecodeLossyStringIfPresent(forKey: .title)
        longTitle = container.pgcDecodeLossyStringIfPresent(forKey: .longTitle)
        showTitle = container.pgcDecodeLossyStringIfPresent(forKey: .showTitle)
        cover = container.pgcDecodeLossyStringIfPresent(forKey: .cover)
        badge = container.pgcDecodeLossyStringIfPresent(forKey: .badge)
        duration = container.pgcDecodeLossyIntIfPresent(forKey: .duration)
        pubTime = container.pgcDecodeLossyIntIfPresent(forKey: .pubTime)
            ?? container.pgcDecodeLossyIntIfPresent(forKey: .releaseDate)
        dimension = try container.decodeIfPresent(VideoDimension.self, forKey: .dimension)
    }

    var displayTitle: String {
        let titleText = title?.removingHTMLTags().pgcTrimmedNonEmpty
        let longTitleText = longTitle?.removingHTMLTags().pgcTrimmedNonEmpty
        if let titleText, let longTitleText {
            return "\(titleText) \(longTitleText)"
        }
        return longTitleText
            ?? showTitle?.removingHTMLTags().pgcTrimmedNonEmpty
            ?? titleText
            ?? "分集"
    }

    var durationSeconds: Int? {
        guard let duration, duration > 0 else { return nil }
        return duration > 10_000 ? duration / 1000 : duration
    }

    func videoItem(in season: PgcSeasonInfo, recommendReason: String? = nil) -> VideoItem? {
        guard let cid, cid > 0 else { return nil }
        let episodeID = epID ?? idValue
        let seasonID = season.seasonID
        let routeID = bvid?.pgcTrimmedNonEmpty
            ?? episodeID.map { "ep\($0)" }
            ?? "pgc-\(seasonID ?? 0)-\(cid)"
        return VideoItem(
            bvid: routeID,
            aid: aid,
            title: displayTitle,
            pic: cover?.normalizedBiliURL() ?? season.normalizedCover,
            desc: season.evaluate?.removingHTMLTags(),
            duration: durationSeconds,
            pubdate: pubTime,
            owner: season.owner,
            stat: season.stat?.videoStat,
            cid: cid,
            pages: [
                VideoPage(
                    cid: cid,
                    page: 1,
                    part: displayTitle,
                    duration: durationSeconds,
                    dimension: dimension
                )
            ],
            dimension: dimension,
            recommendReason: recommendReason,
            pgcSeasonID: seasonID,
            pgcEpisodeID: episodeID
        )
    }
}

nonisolated struct PgcRating: Decodable, Hashable, Sendable {
    let score: Double?

    var displayScore: String? {
        guard let score else { return nil }
        return String(format: "%.1f", score)
    }
}

nonisolated struct PgcSeasonStat: Decodable, Hashable, Sendable {
    let views: Int?
    let reply: Int?
    let likes: Int?
    let coins: Int?
    let favorite: Int?

    enum CodingKeys: String, CodingKey {
        case views, reply, likes, coins, favorite
    }

    var videoStat: VideoStat {
        VideoStat(
            view: views,
            reply: reply,
            like: likes,
            coin: coins,
            favorite: favorite
        )
    }
}

nonisolated struct PgcUpInfo: Decodable, Hashable, Sendable {
    let mid: Int?
    let name: String?
    let avatar: String?

    enum CodingKeys: String, CodingKey {
        case mid, avatar
        case name = "uname"
    }
}

nonisolated struct PgcUserStatus: Decodable, Hashable, Sendable {
    let progress: PgcUserProgress?
    let favored: Int?
}

nonisolated struct PgcUserProgress: Decodable, Hashable, Sendable {
    let lastEpID: Int?

    enum CodingKeys: String, CodingKey {
        case lastEpID = "last_ep_id"
    }
}

nonisolated struct PgcPlayURLResult: Decodable, Sendable {
    let videoInfo: PlayURLData?

    enum CodingKeys: String, CodingKey {
        case videoInfo = "video_info"
    }
}

private extension String {
    nonisolated var pgcTrimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private extension KeyedDecodingContainer {
    nonisolated func pgcDecodeLossyIntIfPresent(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return Int(value)
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int(value)
        }
        return nil
    }

    nonisolated func pgcDecodeLossyStringIfPresent(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return String(format: "%.3f", value)
        }
        return nil
    }
}

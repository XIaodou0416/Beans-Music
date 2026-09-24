import CoreGraphics
import Foundation

enum BiliVideoQuality {
    nonisolated static let supportedQualities = [129, 127, 126, 125, 120, 116, 112, 80, 74, 64, 32, 16, 6]

    nonisolated static func title(for quality: Int?) -> String {
        guard let quality else { return "自动（快速开播）" }
        switch quality {
        case 129:
            return "HDR Vivid"
        case 127:
            return "8K"
        case 126:
            return "杜比视界"
        case 125:
            return "真彩 HDR"
        case 120:
            return "4K"
        case 116:
            return "1080P 高帧率"
        case 112:
            return "1080P 高码率"
        case 80:
            return "1080P"
        case 74:
            return "720P 高帧率"
        case 64:
            return "720P"
        case 32:
            return "480P"
        case 16:
            return "360P"
        case 6:
            return "240P"
        default:
            return "清晰度 \(quality)"
        }
    }

    nonisolated static func compactTitle(for quality: Int, fallback: String) -> String {
        switch quality {
        case 129:
            return "HDR Vivid"
        case 127:
            return "8K"
        case 126:
            return "杜比视界"
        case 125:
            return "HDR"
        case 120:
            return "4K"
        case 116:
            return "1080P60"
        case 112:
            return "1080P+"
        case 80:
            return "1080P"
        case 74:
            return "720P60"
        case 64:
            return "720P"
        case 32:
            return "480P"
        case 16:
            return "360P"
        case 6:
            return "240P"
        default:
            return fallback.isEmpty ? "清晰度 \(quality)" : fallback
        }
    }
}

enum BiliVideoDynamicRange: String, Hashable, Sendable {
    case sdr
    case hdr10
    case hlg
    case dolbyVision

    nonisolated var isHDR: Bool {
        self != .sdr
    }

    nonisolated var hlsVideoRangeAttribute: String? {
        switch self {
        case .sdr:
            return nil
        case .dolbyVision:
            return "PQ"
        case .hdr10:
            return nil
        case .hlg:
            return "HLG"
        }
    }
}

nonisolated struct BiliResponse<T: Decodable>: Decodable {
    let code: Int
    let message: String?
    let msg: String?
    let data: T?
    let result: T?

    nonisolated var payload: T? {
        data ?? result
    }

    nonisolated var displayMessage: String? {
        message ?? msg
    }
}

extension BiliResponse: Sendable where T: Sendable {}

nonisolated struct BiliPage<T: Decodable>: Decodable {
    let list: [T]?
    let item: [T]?
    let result: [T]?
}

extension BiliPage: Sendable where T: Sendable {}

nonisolated struct VideoItem: Identifiable, Decodable, Hashable, Sendable {
    nonisolated var id: String { bvid }

    let bvid: String
    let aid: Int?
    let title: String
    let pic: String?
    let desc: String?
    let duration: Int?
    let pubdate: Int?
    let owner: VideoOwner?
    let stat: VideoStat?
    let cid: Int?
    let pages: [VideoPage]?
    let dimension: VideoDimension?
    let historyResumeTime: TimeInterval?
    let historyCID: Int?
    let recommendReason: String?
    let pgcSeasonID: Int?
    let pgcEpisodeID: Int?

    enum CodingKeys: String, CodingKey {
        case bvid, aid, title, pic, desc, duration, pubdate, owner, stat, cid, pages, dimension
        case historyResumeTime, historyCID, recommendReason, pgcSeasonID, pgcEpisodeID
    }

    init(
        bvid: String,
        aid: Int?,
        title: String,
        pic: String?,
        desc: String?,
        duration: Int?,
        pubdate: Int?,
        owner: VideoOwner?,
        stat: VideoStat?,
        cid: Int?,
        pages: [VideoPage]?,
        dimension: VideoDimension?,
        historyResumeTime: TimeInterval? = nil,
        historyCID: Int? = nil,
        recommendReason: String? = nil,
        pgcSeasonID: Int? = nil,
        pgcEpisodeID: Int? = nil
    ) {
        self.bvid = bvid
        self.aid = aid
        self.title = title
        self.pic = pic
        self.desc = desc
        self.duration = duration
        self.pubdate = pubdate
        self.owner = owner
        self.stat = stat
        self.cid = cid
        self.pages = pages
        self.dimension = dimension
        self.historyResumeTime = historyResumeTime
        self.historyCID = historyCID
        self.recommendReason = recommendReason
        self.pgcSeasonID = pgcSeasonID
        self.pgcEpisodeID = pgcEpisodeID
    }

    nonisolated func mergingFilledValues(from fullDetail: VideoItem) -> VideoItem {
        let mergedOwner: VideoOwner? = {
            guard let detailOwner = fullDetail.owner else { return owner }
            guard let owner else { return detailOwner }
            return owner.mergingFilledValues(from: detailOwner)
        }()
        let mergedDescription: String? = {
            let detailDescription = fullDetail.desc?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let detailDescription, !detailDescription.isEmpty {
                return fullDetail.desc
            }
            let currentDescription = desc?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let currentDescription, !currentDescription.isEmpty {
                return desc
            }
            return fullDetail.desc ?? desc
        }()
        return VideoItem(
            bvid: fullDetail.bvid.isEmpty ? bvid : fullDetail.bvid,
            aid: fullDetail.aid ?? aid,
            title: fullDetail.title.isEmpty ? title : fullDetail.title,
            pic: fullDetail.pic ?? pic,
            desc: mergedDescription,
            duration: fullDetail.duration ?? duration,
            pubdate: fullDetail.pubdate ?? pubdate,
            owner: mergedOwner,
            stat: fullDetail.stat ?? stat,
            cid: cid ?? fullDetail.cid,
            pages: fullDetail.pages ?? pages,
            dimension: fullDetail.dimension ?? dimension,
            historyResumeTime: historyResumeTime ?? fullDetail.historyResumeTime,
            historyCID: historyCID ?? fullDetail.historyCID,
            recommendReason: recommendReason ?? fullDetail.recommendReason,
            pgcSeasonID: pgcSeasonID ?? fullDetail.pgcSeasonID,
            pgcEpisodeID: pgcEpisodeID ?? fullDetail.pgcEpisodeID
        )
    }

    nonisolated var isPGCEpisode: Bool {
        if (pgcEpisodeID ?? 0) > 0 || (pgcSeasonID ?? 0) > 0 {
            return true
        }
        guard bvid.hasPrefix("ep") else { return false }
        return Int(bvid.dropFirst(2)) != nil
    }
}

nonisolated struct VideoOwner: Decodable, Hashable, Sendable {
    let mid: Int
    let name: String
    let face: String?

    enum CodingKeys: String, CodingKey {
        case mid, name, face, avatar
        case faceURL = "face_url"
    }

    init(mid: Int, name: String, face: String?) {
        self.mid = mid
        self.name = name
        self.face = face
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mid = container.decodeLossyIntIfPresent(forKey: .mid) ?? 0
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Unknown"
        face = try container.decodeIfPresent(String.self, forKey: .face)
            ?? container.decodeIfPresent(String.self, forKey: .avatar)
            ?? container.decodeIfPresent(String.self, forKey: .faceURL)
    }

    nonisolated func mergingFilledValues(from richerOwner: VideoOwner) -> VideoOwner {
        let currentName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let richerName = richerOwner.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let mergedName: String
        if !richerName.isEmpty, richerName != "Unknown" {
            mergedName = richerName
        } else if !currentName.isEmpty {
            mergedName = currentName
        } else {
            mergedName = "Unknown"
        }
        let richerFace = richerOwner.face?.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentFace = face?.trimmingCharacters(in: .whitespacesAndNewlines)

        return VideoOwner(
            mid: richerOwner.mid > 0 ? richerOwner.mid : mid,
            name: mergedName,
            face: richerFace?.isEmpty == false ? richerFace : (currentFace?.isEmpty == false ? currentFace : nil)
        )
    }
}

nonisolated struct VideoStat: Decodable, Hashable, Sendable {
    let view: Int?
    let reply: Int?
    let like: Int?
    let coin: Int?
    let favorite: Int?
}

nonisolated struct VideoPage: Identifiable, Decodable, Hashable {
    var id: Int { cid }

    let cid: Int
    let page: Int?
    let part: String?
    let duration: Int?
    let dimension: VideoDimension?
}

nonisolated struct VideoDimension: Decodable, Hashable {
    let width: Int?
    let height: Int?
    let rotate: Int?

    var aspectRatio: Double? {
        guard var width, var height, width > 0, height > 0 else { return nil }
        if abs(rotate ?? 0) == 90 || abs(rotate ?? 0) == 270 {
            swap(&width, &height)
        }
        return Double(width) / Double(height)
    }
}

nonisolated struct UploaderProfile: Decodable, Hashable {
    let card: UploaderCard?
    let follower: Int?
    let following: Bool?
    let likeNum: Int?
    let archiveCount: Int?

    enum CodingKeys: String, CodingKey {
        case card, follower, following
        case fans, relation, likes, archive
        case isFollowed = "is_followed"
        case likeNum = "like_num"
        case archiveCount = "archive_count"
    }

    init(
        card: UploaderCard?,
        follower: Int?,
        following: Bool?,
        likeNum: Int?,
        archiveCount: Int?
    ) {
        self.card = card
        self.follower = follower
        self.following = following
        self.likeNum = likeNum
        self.archiveCount = archiveCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        card = try container.decodeIfPresent(UploaderCard.self, forKey: .card)
            ?? UploaderCard(from: decoder)
        follower = container.decodeLossyIntIfPresent(forKey: .follower)
            ?? container.decodeLossyIntIfPresent(forKey: .fans)
            ?? card?.fans
        if let cardFollowing = card?.relation?.isFollowing {
            following = cardFollowing
        } else if let relation = try? container.decodeIfPresent(UploaderRelationState.self, forKey: .relation),
           let relationFollowing = relation.isFollowing {
            following = relationFollowing
        } else if let isFollowed = container.decodeLossyBoolIfPresent(forKey: .isFollowed) {
            following = isFollowed
        } else {
            following = container.decodeLossyBoolIfPresent(forKey: .following)
        }
        let likes = try container.decodeIfPresent(UploaderLikes.self, forKey: .likes)
        likeNum = container.decodeLossyIntIfPresent(forKey: .likeNum)
            ?? likes?.likeNum
            ?? card?.likes?.likeNum
        if let archive = try container.decodeIfPresent(UploaderArchiveStats.self, forKey: .archive) {
            archiveCount = container.decodeLossyIntIfPresent(forKey: .archiveCount)
                ?? archive.count
        } else {
            archiveCount = container.decodeLossyIntIfPresent(forKey: .archiveCount)
        }
    }

    init(from card: UploaderCard, archiveCount: Int? = nil) {
        self.card = card
        follower = card.fans
        following = card.relation?.isFollowing
        likeNum = card.likes?.likeNum
        self.archiveCount = archiveCount
    }

    nonisolated var visibleFollowerCount: Int? {
        follower ?? card?.fans
    }

    nonisolated var visibleFollowingCount: Int? {
        card?.attention
    }

    nonisolated var visibleLikeCount: Int? {
        likeNum ?? card?.likes?.likeNum
    }

    nonisolated var visibleArchiveCount: Int? {
        archiveCount
    }

    nonisolated var hasVisibleStats: Bool {
        visibleFollowerCount != nil
            || visibleFollowingCount != nil
            || visibleLikeCount != nil
            || visibleArchiveCount != nil
    }

    nonisolated var hasProfileContent: Bool {
        hasVisibleStats || card?.hasProfileContent == true || following != nil
    }

    func merged(with other: UploaderProfile?) -> UploaderProfile {
        guard let other else { return self }
        return UploaderProfile(
            card: card?.merged(with: other.card) ?? other.card,
            follower: other.follower ?? follower,
            following: other.following ?? following,
            likeNum: other.likeNum ?? likeNum,
            archiveCount: other.archiveCount ?? archiveCount
        )
    }
}

nonisolated struct UploaderViewerRelation: Decodable, Hashable {
    let following: Bool?

    enum CodingKeys: String, CodingKey {
        case attribute, special
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let attribute = container.decodeLossyIntIfPresent(forKey: .attribute)
        let special = container.decodeLossyIntIfPresent(forKey: .special)
        if let attribute {
            following = attribute > 0 && attribute != 128
        } else if let special {
            following = special > 0
        } else {
            following = nil
        }
    }
}

extension UploaderViewerRelation {
    nonisolated var profilePatch: UploaderProfile {
        UploaderProfile(
            card: nil,
            follower: nil,
            following: following,
            likeNum: nil,
            archiveCount: nil
        )
    }
}

nonisolated struct UploaderCard: Decodable, Hashable {
    let mid: Int?
    let name: String?
    let face: String?
    let sign: String?
    let fans: Int?
    let attention: Int?
    let relation: UploaderRelationState?
    let likes: UploaderLikes?

    enum CodingKeys: String, CodingKey {
        case mid, name, face, sign, fans, attention, friend, relation, likes
    }

    init(
        mid: Int?,
        name: String?,
        face: String?,
        sign: String?,
        fans: Int?,
        attention: Int?,
        relation: UploaderRelationState? = nil,
        likes: UploaderLikes? = nil
    ) {
        self.mid = mid
        self.name = name
        self.face = face
        self.sign = sign
        self.fans = fans
        self.attention = attention
        self.relation = relation
        self.likes = likes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mid = container.decodeLossyIntIfPresent(forKey: .mid)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        face = try container.decodeIfPresent(String.self, forKey: .face)
        sign = try container.decodeIfPresent(String.self, forKey: .sign)
        fans = container.decodeLossyIntIfPresent(forKey: .fans)
        attention = container.decodeLossyIntIfPresent(forKey: .attention)
            ?? container.decodeLossyIntIfPresent(forKey: .friend)
        relation = try container.decodeIfPresent(UploaderRelationState.self, forKey: .relation)
        likes = try container.decodeIfPresent(UploaderLikes.self, forKey: .likes)
    }

    func merged(with other: UploaderCard?) -> UploaderCard {
        guard let other else { return self }
        return UploaderCard(
            mid: mid ?? other.mid,
            name: name ?? other.name,
            face: face ?? other.face,
            sign: sign ?? other.sign,
            fans: other.fans ?? fans,
            attention: other.attention ?? attention,
            relation: other.relation ?? relation,
            likes: other.likes ?? likes
        )
    }

    nonisolated var hasProfileContent: Bool {
        mid != nil
            || name?.isEmpty == false
            || face?.isEmpty == false
            || sign?.isEmpty == false
            || fans != nil
            || attention != nil
            || relation != nil
            || likes?.likeNum != nil
    }
}

nonisolated struct UploaderRelationState: Decodable, Hashable {
    let isFollowing: Bool?
    let isFollowedByUploader: Bool?
    let status: Int?
    let attribute: Int?

    enum CodingKeys: String, CodingKey {
        case isFollow = "is_follow"
        case isFollowed = "is_followed"
        case status, attribute
    }

    init(isFollowing: Bool?) {
        self.isFollowing = isFollowing
        isFollowedByUploader = nil
        status = nil
        attribute = nil
    }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer() {
            if let value = try? single.decode(Int.self) {
                isFollowing = value > 0 && value != 128
                isFollowedByUploader = nil
                status = value
                attribute = nil
                return
            }
            if let value = try? single.decode(Bool.self) {
                isFollowing = value
                isFollowedByUploader = nil
                status = nil
                attribute = nil
                return
            }
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedStatus = container.decodeLossyIntIfPresent(forKey: .status)
        let decodedAttribute = container.decodeLossyIntIfPresent(forKey: .attribute)
        let decodedIsFollowed = container.decodeLossyBoolIfPresent(forKey: .isFollowed)
        status = decodedStatus
        attribute = decodedAttribute
        isFollowedByUploader = decodedIsFollowed
        if let isFollow = container.decodeLossyBoolIfPresent(forKey: .isFollow) {
            isFollowing = isFollow
        } else if let decodedStatus {
            isFollowing = decodedStatus > 0 && decodedStatus != 128
        } else if let decodedAttribute {
            isFollowing = decodedAttribute > 0 && decodedAttribute != 128
        } else {
            isFollowing = decodedIsFollowed
        }
    }
}

nonisolated struct UploaderLikes: Decodable, Hashable {
    let likeNum: Int?

    enum CodingKeys: String, CodingKey {
        case likeNum = "like_num"
        case count, likes
    }

    init(likeNum: Int?) {
        self.likeNum = likeNum
    }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let value = try? single.decode(Int.self) {
            likeNum = value
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        likeNum = container.decodeLossyIntIfPresent(forKey: .likeNum)
            ?? container.decodeLossyIntIfPresent(forKey: .count)
            ?? container.decodeLossyIntIfPresent(forKey: .likes)
    }
}

nonisolated struct UploaderArchiveStats: Decodable, Hashable {
    let count: Int?

    enum CodingKeys: String, CodingKey {
        case count
        case archiveCount = "archive_count"
        case item, items
    }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let value = try? single.decode(Int.self) {
            count = value
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        count = container.decodeLossyIntIfPresent(forKey: .count)
            ?? container.decodeLossyIntIfPresent(forKey: .archiveCount)
            ?? (try? container.decodeIfPresent([DynamicJSONValue].self, forKey: .item))?.count
            ?? (try? container.decodeIfPresent([DynamicJSONValue].self, forKey: .items))?.count
    }
}

nonisolated struct UploaderRelationStat: Decodable, Hashable {
    let following: Int?
    let follower: Int?

    enum CodingKeys: String, CodingKey {
        case following
        case follower
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        following = container.decodeLossyIntIfPresent(forKey: .following)
        follower = container.decodeLossyIntIfPresent(forKey: .follower)
    }
}

extension UploaderRelationStat {
    nonisolated var profilePatch: UploaderProfile {
        UploaderProfile(
            card: UploaderCard(
                mid: nil,
                name: nil,
                face: nil,
                sign: nil,
                fans: follower,
                attention: following
            ),
            follower: follower,
            following: nil,
            likeNum: nil,
            archiveCount: nil
        )
    }
}

nonisolated struct UploaderUpStat: Decodable, Hashable {
    let likes: Int?
    let archiveCount: Int?

    enum CodingKeys: String, CodingKey {
        case likes
        case like
        case likeNum = "like_num"
        case archive
        case archiveCount = "archive_count"
    }

    enum ArchiveCodingKeys: String, CodingKey {
        case count
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        likes = container.decodeLossyIntIfPresent(forKey: .likes)
            ?? container.decodeLossyIntIfPresent(forKey: .like)
            ?? container.decodeLossyIntIfPresent(forKey: .likeNum)
        if let archiveCount = container.decodeLossyIntIfPresent(forKey: .archiveCount) {
            self.archiveCount = archiveCount
        } else if let archive = try? container.nestedContainer(keyedBy: ArchiveCodingKeys.self, forKey: .archive) {
            archiveCount = archive.decodeLossyIntIfPresent(forKey: .count)
        } else if let archive = try? container.decodeIfPresent(Int.self, forKey: .archive) {
            archiveCount = archive
        } else {
            archiveCount = nil
        }
    }
}

extension UploaderUpStat {
    nonisolated var profilePatch: UploaderProfile {
        UploaderProfile(
            card: nil,
            follower: nil,
            following: nil,
            likeNum: likes,
            archiveCount: archiveCount
        )
    }
}

nonisolated struct UploaderVideoData: Decodable {
    let list: UploaderVideoList?
    let page: UploaderVideoPageInfo?
}

nonisolated struct UploaderVideoList: Decodable {
    let vlist: [UploaderVideoItem]?
}

nonisolated struct UploaderVideoPageInfo: Decodable, Hashable {
    let count: Int?

    enum CodingKeys: String, CodingKey {
        case count
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        count = container.decodeLossyIntIfPresent(forKey: .count)
    }
}

nonisolated struct UploaderVideoPageResult: Hashable, Sendable {
    let videos: [VideoItem]
    let totalCount: Int?
    let hasMore: Bool
    let nextCursor: UploaderVideoPageCursor?
}

nonisolated struct UploaderVideoPageCursor: Hashable, Sendable {
    let aid: String?
    let next: Int?

    var isEmpty: Bool {
        (aid?.isEmpty ?? true) && next == nil
    }
}

nonisolated struct UploaderAppArchiveData: Decodable {
    let count: Int?
    let item: [UploaderAppArchiveItem]?
    let hasNext: Bool?
    let next: Int?

    enum CodingKeys: String, CodingKey {
        case count, item, next
        case hasNext = "has_next"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        count = container.decodeLossyIntIfPresent(forKey: .count)
        item = try container.decodeIfPresent([UploaderAppArchiveItem].self, forKey: .item)
        hasNext = container.decodeLossyBoolIfPresent(forKey: .hasNext)
        next = container.decodeLossyIntIfPresent(forKey: .next)
    }
}

extension UploaderAppArchiveData {
    nonisolated func pageCursor() -> UploaderVideoPageCursor? {
        let cursor = UploaderVideoPageCursor(
            aid: item?.last?.param,
            next: next
        )
        return cursor.isEmpty ? nil : cursor
    }
}

nonisolated struct UploaderAppArchiveItem: Decodable, Hashable {
    let title: String
    let cover: String?
    let param: String?
    let uri: String?
    let bvid: String?
    let cid: Int?
    let duration: Int?
    let length: String?
    let author: String?
    let play: Int?
    let danmaku: Int?
    let pubdate: Int?

    enum CodingKeys: String, CodingKey {
        case title, cover, param, uri, bvid, duration, length, author, play, danmaku, ctime, pubdate
        case cid = "first_cid"
        case publishTime = "publish_time"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = container.decodeLossyStringIfPresent(forKey: .title) ?? "Untitled"
        cover = container.decodeLossyStringIfPresent(forKey: .cover)
        param = container.decodeLossyStringIfPresent(forKey: .param)
        uri = container.decodeLossyStringIfPresent(forKey: .uri)
        bvid = container.decodeLossyStringIfPresent(forKey: .bvid)
        cid = container.decodeLossyIntIfPresent(forKey: .cid)
        duration = container.decodeLossyIntIfPresent(forKey: .duration)
            ?? Self.durationSeconds(container.decodeLossyStringIfPresent(forKey: .length))
        length = container.decodeLossyStringIfPresent(forKey: .length)
        author = container.decodeLossyStringIfPresent(forKey: .author)
        play = container.decodeLossyIntIfPresent(forKey: .play)
        danmaku = container.decodeLossyIntIfPresent(forKey: .danmaku)
        pubdate = container.decodeLossyIntIfPresent(forKey: .pubdate)
            ?? container.decodeLossyIntIfPresent(forKey: .publishTime)
            ?? container.decodeLossyIntIfPresent(forKey: .ctime)
    }

    func asVideoItem(defaultMID: Int) -> VideoItem? {
        let aid = param.flatMap(Int.init)
        let resolvedBVID = resolvedVideoID(aid: aid)
        guard !resolvedBVID.isEmpty else { return nil }
        return VideoItem(
            bvid: resolvedBVID,
            aid: aid,
            title: title,
            pic: cover?.normalizedBiliURL(),
            desc: nil,
            duration: duration,
            pubdate: pubdate,
            owner: VideoOwner(mid: defaultMID, name: author ?? "", face: nil),
            stat: VideoStat(view: play, reply: nil, like: nil, coin: nil, favorite: nil),
            cid: cid,
            pages: nil,
            dimension: nil
        )
    }

    private func resolvedVideoID(aid: Int?) -> String {
        if let bvid, !bvid.isEmpty {
            return bvid
        }
        if let uri, let range = uri.range(of: #"BV[A-Za-z0-9]+"#, options: .regularExpression) {
            return String(uri[range])
        }
        guard let aid, aid > 0 else { return "" }
        return "av\(aid)"
    }

    private static func durationSeconds(_ value: String?) -> Int? {
        guard let value, !value.isEmpty else { return nil }
        let parts = value.split(separator: ":").compactMap { Int($0) }
        if parts.count == 2 {
            return parts[0] * 60 + parts[1]
        }
        if parts.count == 3 {
            return parts[0] * 3600 + parts[1] * 60 + parts[2]
        }
        return nil
    }
}

nonisolated struct UploaderSeasonSeriesResponse: Decodable, Hashable, Sendable {
    let itemsLists: UploaderSeasonSeriesData?

    enum CodingKeys: String, CodingKey {
        case itemsLists = "items_lists"
    }
}

nonisolated struct UploaderSeasonSeriesData: Decodable, Hashable, Sendable {
    let page: UploaderSeasonSeriesPage?
    let seasonsList: [UploaderSeasonSeriesItem]
    let seriesList: [UploaderSeasonSeriesItem]

    enum CodingKeys: String, CodingKey {
        case page
        case seasonsList = "seasons_list"
        case seriesList = "series_list"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        page = try container.decodeIfPresent(UploaderSeasonSeriesPage.self, forKey: .page)
        seasonsList = try container.decodeIfPresent([UploaderSeasonSeriesItem].self, forKey: .seasonsList) ?? []
        seriesList = try container.decodeIfPresent([UploaderSeasonSeriesItem].self, forKey: .seriesList) ?? []
    }

    var items: [UploaderSeasonSeriesItem] {
        seasonsList + seriesList
    }
}

nonisolated struct UploaderSeasonSeriesPage: Decodable, Hashable, Sendable {
    let pageNum: Int?
    let pageSize: Int?
    let total: Int?

    enum CodingKeys: String, CodingKey {
        case pageNum = "page_num"
        case pageSize = "page_size"
        case total
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pageNum = container.decodeLossyIntIfPresent(forKey: .pageNum)
        pageSize = container.decodeLossyIntIfPresent(forKey: .pageSize)
        total = container.decodeLossyIntIfPresent(forKey: .total)
    }

    func hasMore(afterPage requestedPage: Int, receivedCount: Int, fallbackPageSize: Int = 10) -> Bool {
        let currentPage = pageNum ?? requestedPage
        let size = pageSize ?? fallbackPageSize
        if let total {
            return currentPage * size < total
        }
        return receivedCount >= size
    }
}

nonisolated enum UploaderSeasonSeriesKind: Hashable, Sendable {
    case season(Int)
    case series(Int)

    var id: Int {
        switch self {
        case .season(let id), .series(let id):
            return id
        }
    }

    var title: String {
        switch self {
        case .season:
            return "合集"
        case .series:
            return "列表"
        }
    }
}

enum UploaderSeasonSeriesArchiveSort: String, CaseIterable, Identifiable, Sendable {
    case desc
    case asc

    var id: String { rawValue }

    var title: String {
        switch self {
        case .desc:
            return "最新发布"
        case .asc:
            return "最早发布"
        }
    }
}

nonisolated struct UploaderSeasonSeriesItem: Identifiable, Decodable, Hashable, Sendable {
    let meta: UploaderSeasonSeriesMeta?
    let archives: [UploaderSeasonSeriesArchive]

    enum CodingKeys: String, CodingKey {
        case meta, archives
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        meta = try container.decodeIfPresent(UploaderSeasonSeriesMeta.self, forKey: .meta)
        archives = try container.decodeIfPresent([UploaderSeasonSeriesArchive].self, forKey: .archives) ?? []
    }

    var id: String {
        if let seasonID = meta?.seasonID {
            return "season-\(seasonID)"
        }
        if let seriesID = meta?.seriesID {
            return "series-\(seriesID)"
        }
        return "unknown-\(title)-\(meta?.ptime ?? 0)"
    }

    var title: String {
        meta?.displayTitle ?? "未命名合集"
    }

    var cover: String? {
        meta?.cover?.normalizedBiliURL()
    }

    var kindTitle: String {
        meta?.seasonID != nil ? "合集" : "列表"
    }

    var detailKind: UploaderSeasonSeriesKind? {
        if let seasonID = meta?.seasonID {
            return .season(seasonID)
        }
        if let seriesID = meta?.seriesID {
            return .series(seriesID)
        }
        return nil
    }

    var total: Int? {
        meta?.total
    }

    var updateTime: Int? {
        meta?.ptime
    }

    var previewArchive: UploaderSeasonSeriesArchive? {
        archives.first
    }
}

nonisolated struct UploaderSeasonSeriesMeta: Decodable, Hashable, Sendable {
    let cover: String?
    let name: String?
    let title: String?
    let ptime: Int?
    let total: Int?
    let seasonID: Int?
    let seriesID: Int?

    enum CodingKeys: String, CodingKey {
        case cover, name, title, ptime, total
        case seasonID = "season_id"
        case seriesID = "series_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cover = container.decodeLossyStringIfPresent(forKey: .cover)
        name = container.decodeLossyStringIfPresent(forKey: .name)
        title = container.decodeLossyStringIfPresent(forKey: .title)
        ptime = container.decodeLossyIntIfPresent(forKey: .ptime)
        total = container.decodeLossyIntIfPresent(forKey: .total)
        seasonID = container.decodeLossyIntIfPresent(forKey: .seasonID)
        seriesID = container.decodeLossyIntIfPresent(forKey: .seriesID)
    }

    var displayTitle: String? {
        [name, title]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

nonisolated struct UploaderSeasonSeriesArchiveData: Decodable, Hashable, Sendable {
    let archives: [UploaderSeasonSeriesArchive]
    let page: UploaderSeasonSeriesPage?

    enum CodingKeys: String, CodingKey {
        case archives, page
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        archives = try container.decodeIfPresent([UploaderSeasonSeriesArchive].self, forKey: .archives) ?? []
        page = try container.decodeIfPresent(UploaderSeasonSeriesPage.self, forKey: .page)
    }
}

nonisolated struct UploaderSeasonSeriesArchivePageResult: Hashable, Sendable {
    let videos: [VideoItem]
    let totalCount: Int?
    let hasMore: Bool
}

nonisolated struct UploaderSeasonSeriesArchive: Decodable, Hashable, Sendable {
    let aid: Int?
    let bvid: String?
    let title: String
    let pic: String?
    let duration: Int?
    let pubdate: Int?
    let ctime: Int?
    let upMID: Int?
    let stat: UploaderSeasonSeriesArchiveStat?

    enum CodingKeys: String, CodingKey {
        case aid, bvid, title, pic, duration, pubdate, ctime, stat
        case upMID = "upMid"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        aid = container.decodeLossyIntIfPresent(forKey: .aid)
        bvid = container.decodeLossyStringIfPresent(forKey: .bvid)
        title = container.decodeLossyStringIfPresent(forKey: .title) ?? "Untitled"
        pic = container.decodeLossyStringIfPresent(forKey: .pic)
        duration = container.decodeLossyIntIfPresent(forKey: .duration)
        pubdate = container.decodeLossyIntIfPresent(forKey: .pubdate)
        ctime = container.decodeLossyIntIfPresent(forKey: .ctime)
        upMID = container.decodeLossyIntIfPresent(forKey: .upMID)
        stat = try container.decodeIfPresent(UploaderSeasonSeriesArchiveStat.self, forKey: .stat)
    }

    func asVideoItem(defaultOwner: VideoOwner) -> VideoItem? {
        let resolvedBVID: String
        if let bvid, !bvid.isEmpty {
            resolvedBVID = bvid
        } else if let aid, aid > 0 {
            resolvedBVID = "av\(aid)"
        } else {
            return nil
        }

        return VideoItem(
            bvid: resolvedBVID,
            aid: aid,
            title: title,
            pic: pic?.normalizedBiliURL(),
            desc: nil,
            duration: duration,
            pubdate: pubdate ?? ctime,
            owner: VideoOwner(mid: upMID ?? defaultOwner.mid, name: defaultOwner.name, face: defaultOwner.face),
            stat: VideoStat(view: stat?.view, reply: stat?.danmaku, like: nil, coin: nil, favorite: nil),
            cid: nil,
            pages: nil,
            dimension: nil
        )
    }
}

nonisolated struct UploaderSeasonSeriesArchiveStat: Decodable, Hashable, Sendable {
    let view: Int?
    let danmaku: Int?

    enum CodingKeys: String, CodingKey {
        case view, danmaku
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        view = container.decodeLossyIntIfPresent(forKey: .view)
        danmaku = container.decodeLossyIntIfPresent(forKey: .danmaku)
    }
}

nonisolated struct UploaderVideoItem: Decodable, Hashable {
    let bvid: String
    let aid: Int?
    let author: String?
    let mid: Int?
    let title: String
    let pic: String?
    let description: String?
    let length: String?
    let pubdate: Int?
    let play: Int?
    let comment: Int?

    enum CodingKeys: String, CodingKey {
        case bvid, aid, author, mid, title, pic, description, length, pubdate, created, ctime, play, comment
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bvid = try container.decodeIfPresent(String.self, forKey: .bvid) ?? ""
        aid = container.decodeLossyIntIfPresent(forKey: .aid)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        mid = container.decodeLossyIntIfPresent(forKey: .mid)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Untitled"
        pic = try container.decodeIfPresent(String.self, forKey: .pic)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        length = try container.decodeIfPresent(String.self, forKey: .length)
        pubdate = container.decodeLossyIntIfPresent(forKey: .pubdate)
            ?? container.decodeLossyIntIfPresent(forKey: .created)
            ?? container.decodeLossyIntIfPresent(forKey: .ctime)
        play = container.decodeLossyIntIfPresent(forKey: .play)
        comment = container.decodeLossyIntIfPresent(forKey: .comment)
    }

    func asVideoItem(defaultMID: Int) -> VideoItem {
        VideoItem(
            bvid: bvid,
            aid: aid,
            title: title,
            pic: pic?.normalizedBiliURL(),
            desc: description,
            duration: length.flatMap(Self.durationSeconds),
            pubdate: pubdate,
            owner: VideoOwner(mid: mid ?? defaultMID, name: author ?? "", face: nil),
            stat: VideoStat(view: play, reply: comment, like: nil, coin: nil, favorite: nil),
            cid: nil,
            pages: nil,
            dimension: nil
        )
    }

    nonisolated private static func durationSeconds(_ value: String) -> Int {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        if parts.count == 2 {
            return parts[0] * 60 + parts[1]
        }
        if parts.count == 3 {
            return parts[0] * 3600 + parts[1] * 60 + parts[2]
        }
        return 0
    }
}

nonisolated struct AppRecommendNextIndexResult: Hashable, Sendable {
    let value: Int?
    let source: String?
}

nonisolated struct RecommendFeedData: Decodable, Sendable {
    let item: [RecommendFeedItem]?
    let items: [RecommendFeedItem]?
    let config: RecommendFeedConfig?

    nonisolated var feedItems: [RecommendFeedItem] {
        item ?? items ?? []
    }

    nonisolated func appNextIndex(after requestedIndex: Int) -> Int? {
        appNextIndexResult(after: requestedIndex).value
    }

    nonisolated func appNextIndexResult(after requestedIndex: Int) -> AppRecommendNextIndexResult {
        if let configIndex = config?.preferredNextIndex {
            return configIndex
        }
        let positiveIndexes = feedItems.compactMap(\.idx).filter { $0 > 0 }
        if let lastIndex = positiveIndexes.last {
            return AppRecommendNextIndexResult(value: lastIndex, source: "item.idx")
        }
        guard !feedItems.isEmpty else {
            return AppRecommendNextIndexResult(value: nil, source: nil)
        }
        return AppRecommendNextIndexResult(value: requestedIndex + 1, source: "synthetic")
    }
}

nonisolated struct RecommendFeedConfig: Decodable, Hashable, Sendable {
    let idx: Int?
    let nextIdx: Int?
    let nextIndex: Int?
    let freshIdx: Int?
    let feedIdx: Int?
    let offset: Int?

    nonisolated var preferredNextIndex: AppRecommendNextIndexResult? {
        [
            (idx, "config.idx"),
            (nextIdx, "config.next_idx"),
            (nextIndex, "config.next_index"),
            (freshIdx, "config.fresh_idx"),
            (feedIdx, "config.feed_idx"),
            (offset, "config.offset")
        ]
        .compactMap { candidate -> AppRecommendNextIndexResult? in
            let (value, source) = candidate
            guard let value, value > 0 else { return nil }
            return AppRecommendNextIndexResult(value: value, source: source)
        }
        .first
    }

    enum CodingKeys: String, CodingKey {
        case idx
        case nextIdx = "next_idx"
        case nextIndex = "next_index"
        case freshIdx = "fresh_idx"
        case freshIndex = "fresh_index"
        case feedIdx = "feed_idx"
        case feedIndex = "feed_index"
        case offset
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        idx = container.decodeLossyIntIfPresent(forKey: .idx)
        nextIdx = container.decodeLossyIntIfPresent(forKey: .nextIdx)
        nextIndex = container.decodeLossyIntIfPresent(forKey: .nextIndex)
        freshIdx = container.decodeLossyIntIfPresent(forKey: .freshIdx)
            ?? container.decodeLossyIntIfPresent(forKey: .freshIndex)
        feedIdx = container.decodeLossyIntIfPresent(forKey: .feedIdx)
            ?? container.decodeLossyIntIfPresent(forKey: .feedIndex)
        offset = container.decodeLossyIntIfPresent(forKey: .offset)
    }
}

nonisolated struct RecommendFeedReason: Decodable, Hashable, Sendable {
    let content: String?

    enum CodingKeys: String, CodingKey {
        case content, text, reason
    }

    init(from decoder: Decoder) throws {
        if let value = try? decoder.singleValueContainer().decode(String.self) {
            content = value
            return
        }

        let container = try? decoder.container(keyedBy: CodingKeys.self)
        content = container?.decodeLossyStringIfPresent(forKey: .content)
            ?? container?.decodeLossyStringIfPresent(forKey: .text)
            ?? container?.decodeLossyStringIfPresent(forKey: .reason)
    }
}

nonisolated struct RecommendFeedItem: Identifiable, Decodable, Hashable, Sendable {
    nonisolated var id: String { bvid ?? String(aid ?? 0) }

    let idValue: Int?
    let aid: Int?
    let bvid: String?
    let cid: Int?
    let title: String?
    let pic: String?
    let cover: String?
    let uri: String?
    let param: String?
    let goto: String?
    let cardGoto: String?
    let duration: Int?
    let pubdate: Int?
    let idx: Int?
    let owner: VideoOwner?
    let ownerInfo: VideoOwner?
    let args: RecommendFeedItemArgs?
    let descButton: RecommendFeedDescButton?
    let desc: String?
    let recommendReason: RecommendFeedReason?
    let bottomRecommendReason: RecommendFeedReason?
    let topRecommendReason: RecommendFeedReason?
    let recommendReasonStyle: RecommendFeedReason?
    let bottomRecommendReasonStyle: RecommendFeedReason?
    let topRecommendReasonStyle: RecommendFeedReason?
    let stat: VideoStat?
    let dimension: VideoDimension?

    nonisolated var resolvedCardKind: String {
        goto ?? cardGoto ?? "-"
    }

    nonisolated var isVideoCard: Bool {
        let target = goto ?? cardGoto
        return target == nil || target == "av" || target == "video"
    }

    enum CodingKeys: String, CodingKey {
        case aid, bvid, cid, title, pic, cover, uri, param, goto, idx, duration, pubdate, ctime, owner, args, desc, stat, dimension
        case idValue = "id"
        case cardGoto = "card_goto"
        case ownerInfo = "owner_info"
        case descButton = "desc_button"
        case recommendReason = "rcmd_reason"
        case bottomRecommendReason = "bottom_rcmd_reason"
        case topRecommendReason = "top_rcmd_reason"
        case recommendReasonStyle = "rcmd_reason_style"
        case bottomRecommendReasonStyle = "bottom_rcmd_reason_style"
        case topRecommendReasonStyle = "top_rcmd_reason_style"
        case pubDate = "pub_date"
        case publishTime = "publish_time"
        case coverLeftText1 = "cover_left_text_1"
        case coverLeftText2 = "cover_left_text_2"
        case coverRightText = "cover_right_text"
        case playerArgs = "player_args"
    }

    enum PlayerArgsCodingKeys: String, CodingKey {
        case aid
        case cid
        case duration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let playerArgs = try? container.nestedContainer(keyedBy: PlayerArgsCodingKeys.self, forKey: .playerArgs)
        idValue = container.decodeLossyIntIfPresent(forKey: .idValue)
        aid = container.decodeLossyIntIfPresent(forKey: .aid)
            ?? playerArgs?.decodeLossyIntIfPresent(forKey: .aid)
            ?? container.decodeLossyIntIfPresent(forKey: .param)
        bvid = container.decodeLossyStringIfPresent(forKey: .bvid)
        cid = container.decodeLossyIntIfPresent(forKey: .cid)
            ?? playerArgs?.decodeLossyIntIfPresent(forKey: .cid)
        title = container.decodeLossyStringIfPresent(forKey: .title)
        pic = container.decodeLossyStringIfPresent(forKey: .pic)
        cover = container.decodeLossyStringIfPresent(forKey: .cover)
        uri = container.decodeLossyStringIfPresent(forKey: .uri)
        param = container.decodeLossyStringIfPresent(forKey: .param)
        goto = container.decodeLossyStringIfPresent(forKey: .goto)
        cardGoto = container.decodeLossyStringIfPresent(forKey: .cardGoto)
        idx = container.decodeLossyIntIfPresent(forKey: .idx)
        duration = container.decodeLossyIntIfPresent(forKey: .duration)
            ?? playerArgs?.decodeLossyIntIfPresent(forKey: .duration)
            ?? Self.durationSeconds(from: container.decodeLossyStringIfPresent(forKey: .coverRightText))
        pubdate = container.decodeLossyIntIfPresent(forKey: .pubdate)
            ?? container.decodeLossyIntIfPresent(forKey: .pubDate)
            ?? container.decodeLossyIntIfPresent(forKey: .publishTime)
            ?? container.decodeLossyIntIfPresent(forKey: .ctime)
        owner = try container.decodeIfPresent(VideoOwner.self, forKey: .owner)
        ownerInfo = try container.decodeIfPresent(VideoOwner.self, forKey: .ownerInfo)
        args = try container.decodeIfPresent(RecommendFeedItemArgs.self, forKey: .args)
        descButton = try container.decodeIfPresent(RecommendFeedDescButton.self, forKey: .descButton)
        desc = container.decodeLossyStringIfPresent(forKey: .desc)
        recommendReason = try container.decodeIfPresent(RecommendFeedReason.self, forKey: .recommendReason)
        bottomRecommendReason = try container.decodeIfPresent(RecommendFeedReason.self, forKey: .bottomRecommendReason)
        topRecommendReason = try container.decodeIfPresent(RecommendFeedReason.self, forKey: .topRecommendReason)
        recommendReasonStyle = try container.decodeIfPresent(RecommendFeedReason.self, forKey: .recommendReasonStyle)
        bottomRecommendReasonStyle = try container.decodeIfPresent(RecommendFeedReason.self, forKey: .bottomRecommendReasonStyle)
        topRecommendReasonStyle = try container.decodeIfPresent(RecommendFeedReason.self, forKey: .topRecommendReasonStyle)
        stat = (try container.decodeIfPresent(VideoStat.self, forKey: .stat))
            ?? Self.stat(from: container.decodeLossyStringIfPresent(forKey: .coverLeftText1))
            ?? Self.stat(from: container.decodeLossyStringIfPresent(forKey: .coverLeftText2))
        dimension = try container.decodeIfPresent(VideoDimension.self, forKey: .dimension)
    }

    nonisolated func asVideoItem() -> VideoItem? {
        guard isVideoCard else { return nil }
        guard let title,
              let identity = Self.videoIdentity(bvid: bvid, uri: uri, aid: idValue ?? aid)
        else { return nil }
        return VideoItem(
            bvid: identity.bvid,
            aid: idValue ?? aid,
            title: title,
            pic: (pic ?? cover)?.normalizedBiliURL(),
            desc: desc,
            duration: duration,
            pubdate: pubdate,
            owner: Self.mergedOwner([owner, ownerInfo, args?.owner, descButton?.owner]),
            stat: stat,
            cid: cid,
            pages: nil,
            dimension: dimension,
            recommendReason: sanitizedRecommendReason
        )
    }

    private nonisolated var sanitizedRecommendReason: String? {
        let value = [
            recommendReason?.content,
            bottomRecommendReason?.content,
            topRecommendReason?.content,
            recommendReasonStyle?.content,
            bottomRecommendReasonStyle?.content,
            topRecommendReasonStyle?.content
        ]
        .compactMap { raw -> String? in
            guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty,
                  !Self.hiddenRecommendReasons.contains(trimmed)
            else { return nil }
            return trimmed
        }
        .first
        return value
    }

    private nonisolated static let hiddenRecommendReasons: Set<String> = ["已关注", "新关注"]

    private nonisolated static func mergedOwner(_ candidates: [VideoOwner?]) -> VideoOwner? {
        let owners = candidates.compactMap { $0 }
        guard !owners.isEmpty else { return nil }
        let mid = owners.first(where: { $0.mid > 0 })?.mid ?? 0
        let name = owners
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && $0 != "Unknown" } ?? "Unknown"
        let face = owners
            .compactMap { $0.face?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        return VideoOwner(mid: mid, name: name, face: face)
    }

    private nonisolated static func videoIdentity(bvid: String?, uri: String?, aid: Int?) -> (bvid: String, isSynthetic: Bool)? {
        if let bvid, !bvid.isEmpty {
            return (bvid, false)
        }
        if let bvid = Self.bvid(from: uri) {
            return (bvid, false)
        }
        guard let aid, aid > 0 else { return nil }
        return ("av\(aid)", true)
    }

    private nonisolated static func bvid(from uri: String?) -> String? {
        guard let uri, !uri.isEmpty else { return nil }
        if let range = uri.range(of: #"BV[A-Za-z0-9]+"#, options: .regularExpression) {
            return String(uri[range])
        }
        return nil
    }

    private nonisolated static func stat(from text: String?) -> VideoStat? {
        guard let view = compactCountValue(from: text) else { return nil }
        return VideoStat(view: view, reply: nil, like: nil, coin: nil, favorite: nil)
    }

    private nonisolated static func compactCountValue(from text: String?) -> Int? {
        guard let text else { return nil }
        let normalized = text
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "播放", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        if normalized.hasSuffix("万"),
           let value = Double(normalized.dropLast()) {
            return Int((value * 10_000).rounded())
        }
        if normalized.hasSuffix("亿"),
           let value = Double(normalized.dropLast()) {
            return Int((value * 100_000_000).rounded())
        }
        return Int(normalized)
    }

    private nonisolated static func durationSeconds(from text: String?) -> Int? {
        guard let text else { return nil }
        let parts = text.split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 2:
            return parts[0] * 60 + parts[1]
        case 3:
            return parts[0] * 3600 + parts[1] * 60 + parts[2]
        default:
            return nil
        }
    }
}

nonisolated struct RecommendFeedItemArgs: Decodable, Hashable, Sendable {
    let upID: Int?
    let upName: String?
    let upFace: String?

    enum CodingKeys: String, CodingKey {
        case upID = "up_id"
        case upMID = "up_mid"
        case mid
        case uid
        case upName = "up_name"
        case uname
        case name
        case author
        case upFace = "up_face"
        case face
        case avatar
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        upID = container.decodeLossyIntIfPresent(forKey: .upID)
            ?? container.decodeLossyIntIfPresent(forKey: .upMID)
            ?? container.decodeLossyIntIfPresent(forKey: .mid)
            ?? container.decodeLossyIntIfPresent(forKey: .uid)
        upName = container.decodeLossyStringIfPresent(forKey: .upName)
            ?? container.decodeLossyStringIfPresent(forKey: .uname)
            ?? container.decodeLossyStringIfPresent(forKey: .name)
            ?? container.decodeLossyStringIfPresent(forKey: .author)
        upFace = container.decodeLossyStringIfPresent(forKey: .upFace)
            ?? container.decodeLossyStringIfPresent(forKey: .face)
            ?? container.decodeLossyStringIfPresent(forKey: .avatar)
    }

    nonisolated var owner: VideoOwner? {
        guard upID != nil || upName != nil || upFace != nil else { return nil }
        let trimmedName = upName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return VideoOwner(
            mid: upID ?? 0,
            name: trimmedName?.isEmpty == false ? trimmedName! : "Unknown",
            face: upFace?.normalizedBiliURL()
        )
    }
}

nonisolated struct RecommendFeedDescButton: Decodable, Hashable, Sendable {
    let text: String?
    let uri: String?

    enum CodingKeys: String, CodingKey {
        case text, uri
    }

    nonisolated var owner: VideoOwner? {
        let trimmedName = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let mid = Self.mid(from: uri)
        guard mid != nil || trimmedName?.isEmpty == false else { return nil }
        return VideoOwner(
            mid: mid ?? 0,
            name: trimmedName?.isEmpty == false ? trimmedName! : "Unknown",
            face: nil
        )
    }

    private nonisolated static func mid(from uri: String?) -> Int? {
        guard let uri, !uri.isEmpty else { return nil }
        if let range = uri.range(of: #"space/(\d+)"#, options: .regularExpression) {
            let value = uri[range].dropFirst("space/".count)
            return Int(value)
        }
        if let range = uri.range(of: #"vmid=(\d+)"#, options: .regularExpression) {
            let value = uri[range].dropFirst("vmid=".count)
            return Int(value)
        }
        return nil
    }
}

nonisolated struct PlayURLData: Decodable, Sendable {
    let code: Int?
    let message: String?
    let durl: [PlayDURL]?
    let dash: DASHInfo?
    let quality: Int?
    let acceptQuality: [Int]?
    let acceptDescription: [String]?
    let supportFormats: [PlaySupportFormat]?
    let lastPlayTime: TimeInterval?
    let lastPlayCID: Int?

    enum CodingKeys: String, CodingKey {
        case code, message, durl, dash, quality
        case acceptQuality = "accept_quality"
        case acceptDescription = "accept_description"
        case supportFormats = "support_formats"
        case lastPlayTime = "last_play_time"
        case lastPlayCID = "last_play_cid"
    }

    nonisolated func mergingDisplayFormats(from metadata: PlayURLData) -> PlayURLData {
        PlayURLData(
            code: code,
            message: message,
            durl: durl,
            dash: dash,
            quality: quality,
            acceptQuality: mergedQualities(primary: acceptQuality, secondary: metadata.acceptQuality),
            acceptDescription: mergedDescriptions(metadata: metadata),
            supportFormats: mergedSupportFormats(primary: supportFormats, secondary: metadata.supportFormats),
            lastPlayTime: lastPlayTime ?? metadata.lastPlayTime,
            lastPlayCID: lastPlayCID ?? metadata.lastPlayCID
        )
    }

    nonisolated func mergingPlayableStreams(from other: PlayURLData) -> PlayURLData {
        let mergedDURL = durl ?? other.durl
        return PlayURLData(
            code: code ?? other.code,
            message: message ?? other.message,
            durl: mergedDURL,
            dash: dash?.mergingStreams(from: other.dash) ?? other.dash,
            quality: durl == nil && other.durl != nil ? (other.quality ?? quality) : (quality ?? other.quality),
            acceptQuality: mergedQualities(primary: acceptQuality, secondary: other.acceptQuality),
            acceptDescription: mergedDescriptions(metadata: other),
            supportFormats: mergedSupportFormats(primary: supportFormats, secondary: other.supportFormats),
            lastPlayTime: lastPlayTime ?? other.lastPlayTime,
            lastPlayCID: lastPlayCID ?? other.lastPlayCID
        )
    }

    nonisolated func removingHistoryMetadata() -> PlayURLData {
        PlayURLData(
            code: code,
            message: message,
            durl: durl,
            dash: dash,
            quality: quality,
            acceptQuality: acceptQuality,
            acceptDescription: acceptDescription,
            supportFormats: supportFormats,
            lastPlayTime: nil,
            lastPlayCID: nil
        )
    }

    nonisolated func resumeTime(
        duration: TimeInterval?,
        minimumProgress: TimeInterval = TimeInterval(LibraryStore.defaultPlaybackHistorySyncThresholdSeconds)
    ) -> TimeInterval? {
        guard let lastPlayTime, lastPlayTime > 0 else { return nil }
        let seconds: TimeInterval
        if let duration, lastPlayTime <= duration + 1 {
            seconds = lastPlayTime
        } else {
            seconds = lastPlayTime / 1000
        }
        guard seconds >= minimumProgress else { return nil }
        if let duration, duration > 0 {
            let remaining = duration - seconds
            guard remaining > 15, seconds / duration < 0.96 else { return nil }
        }
        return seconds
    }

    nonisolated var hasPlayableStreamPayload: Bool {
        playVariants.contains(where: \.isPlayable)
    }

    nonisolated var hasAnyPlayURLPayload: Bool {
        durl?.contains(where: { $0.playURL != nil }) == true
            || dash?.video?.contains(where: { $0.playURL != nil }) == true
            || dash?.audio?.contains(where: { $0.playURL != nil }) == true
    }

    nonisolated var rawPlayURLSummary: String {
        let videoStreams = dash?.video ?? []
        let audioStreams = dash?.audio ?? []
        let dolbyCount = videoStreams.filter(\.isDolbyVisionVideoCodec).count
        let hevcCount = videoStreams.filter(\.isHEVCVideoCodec).count
        let av1Count = videoStreams.filter(\.isAV1VideoCodec).count
        let avcCount = videoStreams.filter(\.isAVCVideoCodec).count
        let aacCount = audioStreams.filter(\.isAACAudioCodec).count
        let dolbyAudioCount = audioStreams.filter(\.isDolbyCompatibleAudioCodec).count
        return "dashVideo=\(videoStreams.count) dolby=\(dolbyCount) hevc=\(hevcCount) av1=\(av1Count) avc=\(avcCount) dashAudio=\(audioStreams.count) aac=\(aacCount) dolbyAudio=\(dolbyAudioCount) durl=\(durl?.count ?? 0)"
    }

    nonisolated var highestPlayableQuality: Int {
        playVariants
            .filter(\.isPlayable)
            .map(\.quality)
            .max() ?? 0
    }

    nonisolated func hasPlayableQuality(_ quality: Int) -> Bool {
        playVariants.contains { $0.satisfiesPreferredQuality(quality) }
    }

    nonisolated func hasMediaPayloadQuality(_ quality: Int) -> Bool {
        playVariants.contains { variant in
            guard variant.quality == quality,
                  variant.videoURL != nil
            else { return false }
            return variant.audioURL != nil || variant.videoStream == nil
        }
    }

    nonisolated func hasPlayableMediaQuality(_ quality: Int) -> Bool {
        hasPlayableQuality(quality) && hasMediaPayloadQuality(quality)
    }

    nonisolated var advertisedQualities: Set<Int> {
        let explicitQualities = explicitlyAdvertisedQualities
        if !explicitQualities.isEmpty {
            return explicitQualities
        }
        return Set((dash?.video ?? []).compactMap(\.id) + [quality].compactMap { $0 })
    }

    nonisolated func hasExplicitlyUnavailableQuality(_ quality: Int) -> Bool {
        let explicitQualities = explicitlyAdvertisedQualities
        guard !explicitQualities.isEmpty else { return false }
        return !explicitQualities.contains(quality)
    }

    nonisolated private var explicitlyAdvertisedQualities: Set<Int> {
        Set((acceptQuality ?? []) + (supportFormats ?? []).compactMap(\.quality))
    }

    nonisolated func targetQualityAvailabilitySummary(
        _ requestedQuality: Int,
        cdnPreference: PlaybackCDNPreference = .automatic
    ) -> String {
        func qualityList(_ values: [Int]) -> String {
            var seen = Set<Int>()
            let unique = values.filter { seen.insert($0).inserted }
            return unique.isEmpty ? "-" : unique.map(String.init).joined(separator: ",")
        }

        func streamSummary(_ stream: DASHStream) -> String {
            let codec = stream.codecs?.replacingOccurrences(of: " ", with: "") ?? "-"
            let frameRate = stream.displayFrameRate ?? "?"
            let resolution = stream.resolutionLabel ?? "?"
            let payload = stream.playURL(cdnPreference: cdnPreference) == nil ? "noURL" : "url"
            let hardware = stream.isHardwareDecodingCompatibleVideo ? "hw" : "noHW"
            return "q\(stream.id.map(String.init) ?? "-"):\(codec)@\(frameRate)/\(resolution)/\(payload)/\(hardware)"
        }

        let accept = qualityList(acceptQuality ?? [])
        let support = qualityList((supportFormats ?? []).compactMap(\.quality))
        let allVideoStreams = (dash?.video ?? []).filter { $0.id != nil }
        let visibleVideoStreams = allVideoStreams.prefix(8).map(streamSummary)
        let omittedStreamCount = max(allVideoStreams.count - visibleVideoStreams.count, 0)
        let dashSummary = visibleVideoStreams.isEmpty
            ? "-"
            : visibleVideoStreams.joined(separator: ",") + (omittedStreamCount > 0 ? ",+\(omittedStreamCount)" : "")
        let targetStreams = allVideoStreams.filter { $0.id == requestedQuality }
        let targetRates = targetStreams.compactMap { DASHStream.numericFrameRate(from: $0.frameRate) }
        let hasTargetPayload = targetStreams.contains { $0.playURL(cdnPreference: cdnPreference) != nil }
        let isPlayable = hasPlayableMediaQuality(requestedQuality)
        let reason: String
        if isPlayable {
            reason = "playable"
        } else if hasExplicitlyUnavailableQuality(requestedQuality) {
            reason = "notAdvertised"
        } else if targetStreams.isEmpty {
            reason = "noVideoStream"
        } else if !hasTargetPayload {
            reason = "videoURLMissing"
        } else if targetStreams.allSatisfy({ !$0.isHardwareDecodingCompatibleVideo }) {
            reason = "hardwareFiltered"
        } else if !targetRates.isEmpty && targetRates.allSatisfy({ $0 < 50 }) {
            reason = "notHighFrameRate"
        } else if targetRates.isEmpty {
            reason = "frameRateUnknown"
        } else if dash?.bestAudioStream?.playURL(cdnPreference: cdnPreference) == nil {
            reason = "audioMissing"
        } else {
            reason = "codecOrPairingFiltered"
        }

        let playableTitle = isPlayable ? "yes" : "no"
        return "targetAvailability target=\(requestedQuality) accept=\(accept) support=\(support) dash=\(dashSummary) playable=\(playableTitle) reason=\(reason)"
    }

    nonisolated private var mediaStreamQualities: Set<Int> {
        var streamedQualities = Set((dash?.video ?? []).compactMap(\.id))
        if durl?.contains(where: { $0.playURL != nil }) == true,
           let quality {
            streamedQualities.insert(quality)
        }
        return streamedQualities
    }

    nonisolated func shouldRefetchForPreferredQuality(_ quality: Int) -> Bool {
        let playableVariants = playVariants.filter(\.isPlayable)
        guard !playableVariants.isEmpty else { return false }
        guard !hasPlayableMediaQuality(quality) else { return false }
        return advertisedQualities.isEmpty || advertisedQualities.contains(quality)
    }

    nonisolated var playVariants: [PlayVariant] {
        playVariants(cdnPreference: .automatic)
    }

    nonisolated func playVariants(cdnPreference: PlaybackCDNPreference) -> [PlayVariant] {
        playVariants(
            cdnPreference: cdnPreference,
            codecPreference: VideoCodecPreference.stored(),
            requiresHardwareDecode: PlaybackHardwareDecodePolicy.stored(),
            prefersBackupAudioURL: PlaybackAudioURLPolicy.stored()
        )
    }

    nonisolated func playVariants(
        cdnPreference: PlaybackCDNPreference,
        codecPreference: VideoCodecPreference,
        requiresHardwareDecode: Bool = PlaybackHardwareDecodePolicy.defaultValue,
        prefersBackupAudioURL: Bool = PlaybackAudioURLPolicy.stored()
    ) -> [PlayVariant] {
        let bestAudio = dash?.bestAudioStream
        let videosByQuality = Dictionary(grouping: dash?.video ?? [], by: { $0.id ?? 0 })
        let descriptions = Dictionary(uniqueKeysWithValues: zip(acceptQuality ?? [], acceptDescription ?? []))
        let supportByQuality = (supportFormats ?? []).reduce(into: [Int: PlaySupportFormat]()) { result, format in
            guard let quality = format.quality, result[quality] == nil else { return }
            result[quality] = format
        }
        var orderedQualities = [Int]()
        var variants: [PlayVariant] = []

        func appendQuality(_ quality: Int?) {
            guard let quality, !orderedQualities.contains(quality) else { return }
            orderedQualities.append(quality)
        }

        func audioPlayURL(for stream: DASHStream) -> URL? {
            stream.playURL(cdnPreference: cdnPreference, prefersBackup: prefersBackupAudioURL)
        }

        supportFormats?.forEach { appendQuality($0.quality) }
        acceptQuality?.forEach { appendQuality($0) }
        dash?.video?.forEach { appendQuality($0.id) }
        if orderedQualities.isEmpty {
            appendQuality(quality)
        }

        for quality in orderedQualities {
            let support = supportByQuality[quality]
            let videoStreams = videosByQuality[quality] ?? []
            let streamCandidates = videoStreams.filter { stream in
                stream.isHardwareDecodingCompatibleVideo
            }
            let stream = DashStreamDispatcher.selectBestStream(
                from: streamCandidates,
                preference: codecPreference
            )
            guard let stream,
                  let streamURL = stream.playURL(cdnPreference: cdnPreference),
                  let bestAudio,
                  let audioURL = audioPlayURL(for: bestAudio)
            else { continue }
            variants.append(PlayVariant(
                quality: quality,
                title: support?.title ?? descriptions[quality] ?? Self.qualityTitle(quality),
                videoURL: streamURL,
                audioURL: audioURL,
                videoStream: stream,
                audioStream: bestAudio,
                codec: stream.codecLabel ?? support?.codecLabel,
                resolution: stream.resolutionLabel,
                frameRate: stream.frameRate,
                bandwidth: stream.bandwidth,
                isHDR: Self.isHDR(quality: quality, title: support?.title ?? descriptions[quality]),
                badge: support?.badge
            ))
        }

        let shouldUseProgressiveFallback = !requiresHardwareDecode
            || !variants.contains(where: \.isPlayable)
        if shouldUseProgressiveFallback, let durl, !durl.isEmpty {
            let progressiveQuality = quality ?? orderedQualities.first ?? 0
            let support = supportByQuality[progressiveQuality]
            let title = support?.title ?? descriptions[progressiveQuality] ?? Self.qualityTitle(progressiveQuality)
            for item in durl {
                guard let streamURL = item.playURL(cdnPreference: cdnPreference),
                      !variants.contains(where: { $0.videoURL == streamURL })
                else { continue }
                variants.append(PlayVariant(
                    quality: progressiveQuality,
                    title: title,
                    videoURL: streamURL,
                    audioURL: nil,
                    videoStream: nil,
                    audioStream: nil,
                    codec: support?.codecLabel,
                    resolution: nil,
                    frameRate: nil,
                    bandwidth: nil,
                    isHDR: Self.isHDR(quality: progressiveQuality, title: support?.title ?? descriptions[progressiveQuality]),
                    badge: support?.badge
                ))
            }
        }

        appendAdvertisedLockedVariants(
            orderedQualities: orderedQualities,
            supportByQuality: supportByQuality,
            descriptions: descriptions,
            videosByQuality: videosByQuality,
            codecPreference: codecPreference,
            requiresHardwareDecode: requiresHardwareDecode,
            into: &variants
        )

        return variants
    }

    nonisolated func videoListenAudioVariants(
        cdnPreference: PlaybackCDNPreference,
        prefersBackupAudioURL: Bool = PlaybackAudioURLPolicy.stored()
    ) -> [VideoListenAudioVariant] {
        var seen = Set<String>()
        return (dash?.audio ?? [])
            .filter(\.isHardwareDecodingCompatibleAudio)
            .compactMap { stream -> VideoListenAudioVariant? in
                let preference: PlaybackCDNPreference = prefersBackupAudioURL ? .backupURL : cdnPreference
                guard let url = stream.playURL(cdnPreference: preference) else { return nil }
                let variant = VideoListenAudioVariant(stream: stream, url: url)
                guard seen.insert(variant.id).inserted else { return nil }
                return variant
            }
            .sorted { lhs, rhs in
                if lhs.kind.sortRank != rhs.kind.sortRank {
                    return lhs.kind.sortRank < rhs.kind.sortRank
                }
                return (lhs.stream.bandwidth ?? 0) > (rhs.stream.bandwidth ?? 0)
            }
    }

    nonisolated private func appendAdvertisedLockedVariants(
        orderedQualities: [Int],
        supportByQuality: [Int: PlaySupportFormat],
        descriptions: [Int: String],
        videosByQuality: [Int: [DASHStream]],
        codecPreference: VideoCodecPreference,
        requiresHardwareDecode: Bool,
        into variants: inout [PlayVariant]
    ) {
        for quality in orderedQualities {
            guard quality > 0,
                  !variants.contains(where: { $0.quality == quality })
            else { continue }

            let support = supportByQuality[quality]
            let advertisedStreams = videosByQuality[quality] ?? []
            let representativeCandidates = advertisedStreams.filter { stream in
                !requiresHardwareDecode || stream.isHardwareDecodingCompatibleVideo
            }
            let representativeStream = DashStreamDispatcher.selectBestStream(
                from: representativeCandidates,
                preference: codecPreference
            )
            variants.append(PlayVariant(
                quality: quality,
                title: support?.title ?? descriptions[quality] ?? Self.qualityTitle(quality),
                videoURL: nil,
                audioURL: nil,
                videoStream: representativeStream,
                audioStream: nil,
                codec: representativeStream?.codecLabel ?? support?.codecLabel,
                resolution: representativeStream?.resolutionLabel,
                frameRate: representativeStream?.frameRate,
                bandwidth: representativeStream?.bandwidth,
                isHDR: Self.isHDR(quality: quality, title: support?.title ?? descriptions[quality]),
                badge: support?.badge,
                isAvailabilityPending: advertisedStreams.isEmpty
            ))
        }
    }

    nonisolated private static func qualityTitle(_ quality: Int) -> String {
        BiliVideoQuality.title(for: quality)
    }

    nonisolated private static func isHDR(quality: Int, title: String?) -> Bool {
        quality == 129
            || quality == 125
            || quality == 126
            || title?.localizedCaseInsensitiveContains("HDR") == true
            || title?.localizedCaseInsensitiveContains("Vivid") == true
            || title?.contains("杜比视界") == true
    }

    nonisolated private func mergedQualities(primary: [Int]?, secondary: [Int]?) -> [Int]? {
        var result = [Int]()
        func append(_ quality: Int) {
            guard !result.contains(quality) else { return }
            result.append(quality)
        }
        secondary?.forEach(append)
        primary?.forEach(append)
        return result.isEmpty ? nil : result
    }

    nonisolated private func mergedDescriptions(metadata: PlayURLData) -> [String]? {
        let primary = Dictionary(uniqueKeysWithValues: zip(acceptQuality ?? [], acceptDescription ?? []))
        let secondary = Dictionary(uniqueKeysWithValues: zip(metadata.acceptQuality ?? [], metadata.acceptDescription ?? []))
        guard let qualities = mergedQualities(primary: acceptQuality, secondary: metadata.acceptQuality) else {
            return acceptDescription ?? metadata.acceptDescription
        }
        return qualities.map { primary[$0] ?? secondary[$0] ?? Self.qualityTitle($0) }
    }

    nonisolated private func mergedSupportFormats(primary: [PlaySupportFormat]?, secondary: [PlaySupportFormat]?) -> [PlaySupportFormat]? {
        var result = [PlaySupportFormat]()
        func append(_ format: PlaySupportFormat) {
            guard let quality = format.quality, !result.contains(where: { $0.quality == quality }) else { return }
            result.append(format)
        }
        secondary?.forEach(append)
        primary?.forEach(append)
        return result.isEmpty ? nil : result
    }
}

nonisolated enum VideoListenAudioKind: String, Hashable, Sendable {
    case lossless
    case dolby
    case aac
    case other

    var sortRank: Int {
        switch self {
        case .lossless: return 0
        case .dolby: return 1
        case .aac: return 2
        case .other: return 3
        }
    }
}

nonisolated struct VideoListenAudioVariant: Identifiable, Hashable, Sendable {
    let stream: DASHStream
    let url: URL

    var kind: VideoListenAudioKind {
        if stream.isLosslessAudioCodec {
            return .lossless
        }
        if stream.isDolbyCompatibleAudioCodec {
            return .dolby
        }
        if stream.isAACAudioCodec {
            return .aac
        }
        return .other
    }

    var preferenceKey: String {
        let codec = stream.codecs?.lowercased() ?? "unknown"
        if let streamID = stream.id, streamID > 0 {
            return "stream-\(streamID)-\(codec)"
        }
        return "codec-\(codec)"
    }

    var id: String { preferenceKey }

    var title: String {
        switch kind {
        case .lossless:
            return stream.codecLabel ?? "无损音频"
        case .dolby:
            return "杜比音频"
        case .aac:
            return "AAC"
        case .other:
            return stream.codecLabel ?? "音频"
        }
    }

    var subtitle: String {
        [bitrateTitle, stream.codecs]
            .compactMap { value in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: " · ")
    }

    var systemImage: String {
        switch kind {
        case .lossless:
            return "waveform.circle"
        case .dolby:
            return "dot.radiowaves.left.and.right"
        case .aac:
            return "waveform"
        case .other:
            return "speaker.wave.2"
        }
    }

    var diagnosticSummary: String {
        [title, bitrateTitle, stream.codecs]
            .compactMap { value in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: " · ")
    }

    private var bitrateTitle: String? {
        guard let bandwidth = stream.bandwidth, bandwidth > 0 else { return nil }
        if bandwidth >= 1_000_000 {
            return String(format: "%.2f Mbps", Double(bandwidth) / 1_000_000)
        }
        return "\(Int((Double(bandwidth) / 1_000).rounded())) kbps"
    }
}

nonisolated struct PlayVariant: Identifiable, Hashable, Sendable {
    nonisolated var id: String {
        "\(quality)-\(videoURL?.absoluteString ?? "locked")"
    }

    let quality: Int
    let title: String
    let videoURL: URL?
    let audioURL: URL?
    let videoStream: DASHStream?
    let audioStream: DASHStream?
    let codec: String?
    let resolution: String?
    let frameRate: String?
    let bandwidth: Int?
    let isHDR: Bool
    let badge: String?
    let dynamicRangeOverride: BiliVideoDynamicRange?
    let isAvailabilityPending: Bool

    init(
        quality: Int,
        title: String,
        videoURL: URL?,
        audioURL: URL?,
        videoStream: DASHStream?,
        audioStream: DASHStream?,
        codec: String?,
        resolution: String?,
        frameRate: String?,
        bandwidth: Int?,
        isHDR: Bool,
        badge: String?,
        dynamicRangeOverride: BiliVideoDynamicRange? = nil,
        isAvailabilityPending: Bool = false
    ) {
        self.quality = quality
        self.title = title
        self.videoURL = videoURL
        self.audioURL = audioURL
        self.videoStream = videoStream
        self.audioStream = audioStream
        self.codec = codec
        self.resolution = resolution
        self.frameRate = frameRate
        self.bandwidth = bandwidth
        self.isHDR = isHDR
        self.badge = badge
        self.dynamicRangeOverride = dynamicRangeOverride
        self.isAvailabilityPending = isAvailabilityPending
    }

    nonisolated var dynamicRange: BiliVideoDynamicRange {
        if let dynamicRangeOverride {
            return dynamicRangeOverride
        }
        if quality == 126 || title.contains("杜比视界") {
            return .dolbyVision
        }
        if title.localizedCaseInsensitiveContains("HLG") || badge?.localizedCaseInsensitiveContains("HLG") == true {
            return .hlg
        }
        return isHDR ? .hdr10 : .sdr
    }

    nonisolated var isPlayable: Bool {
        videoURL != nil && isDynamicRangePlaybackCompatible
    }

    nonisolated var isSelectableFromQualityMenu: Bool {
        isPlayable || isAvailabilityPending
    }

    nonisolated var isHardwareDecodingCompatible: Bool {
        guard isDynamicRangePlaybackCompatible else { return false }
        if let videoStream {
            guard videoStream.isHardwareDecodingCompatibleVideo else { return false }
        } else {
            return false
        }

        if let audioStream {
            guard audioStream.isHardwareDecodingCompatibleAudio else { return false }
        }

        return videoURL != nil
    }

    nonisolated private var isDynamicRangePlaybackCompatible: Bool {
        PlaybackCodecPolicy.canDecode(dynamicRange: dynamicRange)
    }

    nonisolated var isProgressiveFastStart: Bool {
        audioURL == nil && videoStream == nil
    }

    nonisolated func satisfiesPreferredQuality(_ preferredQuality: Int) -> Bool {
        guard isPlayable, quality == preferredQuality else { return false }
        guard [116, 74].contains(preferredQuality) else { return true }
        if let frameRate = DASHStream.numericFrameRate(from: frameRate) {
            return frameRate >= 50
        }
        return title.contains("高帧")
            || title.contains("60")
            || badge?.contains("高帧") == true
            || badge?.contains("60") == true
    }

    nonisolated func replacingPlaybackURLs(videoURL: URL?, audioURL: URL?) -> PlayVariant {
        PlayVariant(
            quality: quality,
            title: title,
            videoURL: videoURL,
            audioURL: audioURL,
            videoStream: videoStream,
            audioStream: audioStream,
            codec: codec,
            resolution: resolution,
            frameRate: frameRate,
            bandwidth: bandwidth,
            isHDR: isHDR,
            badge: badge,
            dynamicRangeOverride: dynamicRangeOverride,
            isAvailabilityPending: isAvailabilityPending
        )
    }

    nonisolated var videoAspectRatio: Double? {
        if let videoStream,
           let width = videoStream.width,
           let height = videoStream.height,
           width > 0,
           height > 0 {
            return Double(width) / Double(height)
        }
        guard let resolution else { return nil }
        let parts = resolution
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .split(separator: "x")
        guard parts.count == 2,
              let width = Double(parts[0]),
              let height = Double(parts[1]),
              width > 0,
              height > 0
        else {
            return nil
        }
        return width / height
    }

    nonisolated var isPortraitVideo: Bool {
        guard let videoAspectRatio else { return false }
        return videoAspectRatio < 0.9
    }

    nonisolated var qualityBadge: String? {
        if quality == 129 || title.localizedCaseInsensitiveContains("Vivid") {
            return "HDR Vivid"
        }
        if quality == 126 {
            return "杜比"
        }
        if isHDR {
            return "HDR"
        }
        if let badge, !badge.isEmpty {
            return badge
        }
        return nil
    }

    nonisolated var subtitle: String {
        var parts = [String]()
        if let resolution {
            parts.append(resolution)
        }
        if let frameRateLabel {
            parts.append(frameRateLabel)
        }
        if let bitrateLabel {
            parts.append(bitrateLabel)
        }
        if let codec {
            parts.append(codec)
        }
        if isHDR {
            parts.append("HDR")
        }
        if let badge, !badge.isEmpty, !parts.contains(badge) {
            parts.append(badge)
        }
        if !isPlayable, !isAvailabilityPending {
            parts.append(unavailableReason)
        }
        return parts.joined(separator: " · ")
    }

    nonisolated var qualityMenuTitle: String {
        let title = BiliVideoQuality.title(for: quality)
        guard !isPlayable, !isAvailabilityPending else { return title }
        return "\(title)（\(unavailableReason)）"
    }

    nonisolated var compactAccessoryTitle: String {
        let normalizedTitle = title.replacingOccurrences(of: " ", with: "")
        return BiliVideoQuality.compactTitle(for: quality, fallback: normalizedTitle)
    }

    nonisolated private var unavailableReason: String {
        if videoURL != nil,
           let dynamicRangeReason = PlaybackCodecPolicy.unsupportedDynamicRangeReason(for: dynamicRange) {
            return dynamicRangeReason
        }
        if let videoStream, !videoStream.isHardwareDecodingCompatibleVideo {
            return "当前设备暂不可播"
        }
        return "需要登录或权限"
    }

    nonisolated private var playbackExperienceLabel: String? {
        switch quality {
        case 116, 74:
            return "流畅优先"
        case 112:
            return "细节优先"
        default:
            break
        }
        if let frameRate = DASHStream.numericFrameRate(from: frameRate), frameRate >= 50 {
            return "流畅优先"
        }
        return nil
    }

    nonisolated private var dynamicRangeMenuLabel: String? {
        guard let qualityBadge,
              !title.localizedCaseInsensitiveContains(qualityBadge)
        else { return nil }
        return qualityBadge
    }

    nonisolated private var frameRateLabel: String? {
        if let displayFrameRate = DASHStream.displayFrameRate(from: frameRate) {
            return "\(displayFrameRate)fps"
        }
        if [116, 74].contains(quality) {
            return "60fps"
        }
        if title.contains("高帧") || title.contains("60") || badge?.contains("高帧") == true || badge?.contains("60") == true {
            return "60fps"
        }
        return nil
    }

    nonisolated private var bitrateLabel: String? {
        guard let bandwidth, bandwidth > 0 else { return nil }
        if bandwidth >= 1_000_000 {
            return String(format: "%.1f Mbps", Double(bandwidth) / 1_000_000)
        }
        return "\(Int((Double(bandwidth) / 1_000).rounded())) kbps"
    }
}

nonisolated struct PlaySupportFormat: Decodable, Sendable {
    let quality: Int?
    let format: String?
    let newDescription: String?
    let displayDescription: String?
    let legacyDescription: String?
    let superscript: String?
    let codecs: [String]?

    enum CodingKeys: String, CodingKey {
        case quality, format, superscript, codecs
        case newDescription = "new_description"
        case displayDescription = "display_desc"
        case legacyDescription = "description"
    }

    nonisolated var title: String? {
        for value in [newDescription, legacyDescription, displayDescription] {
            if let value, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    nonisolated var badge: String? {
        guard let superscript, !superscript.isEmpty else { return nil }
        return superscript
    }

    nonisolated var codecLabel: String? {
        guard let codecs, !codecs.isEmpty else { return nil }
        var labels = [String]()
        for codec in codecs {
            guard let label = DASHStream.codecLabel(for: codec), !labels.contains(label) else { continue }
            labels.append(label)
        }
        return labels.isEmpty ? nil : labels.joined(separator: "/")
    }
}

nonisolated struct PlayDURL: Decodable, Sendable {
    let url: String
    let backupURL: [String]?

    enum CodingKeys: String, CodingKey {
        case url
        case backupURL = "backup_url"
    }

    nonisolated var playURL: URL? {
        playURL(cdnPreference: .automatic)
    }

    nonisolated func playURL(cdnPreference: PlaybackCDNPreference) -> URL? {
        let primary = URL(string: url)
        let backups = backupURL?.compactMap(URL.init(string:)) ?? []
        return cdnPreference.preferredURLs(primary: primary, backups: backups).primary
    }
}

nonisolated struct DASHInfo: Decodable, Sendable {
    let duration: Int?
    let video: [DASHStream]?
    let audio: [DASHStream]?

    enum CodingKeys: String, CodingKey {
        case duration, video, audio, dolby, flac
    }

    enum NestedMediaCodingKeys: String, CodingKey {
        case audio, video
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        duration = container.decodeLossyIntIfPresent(forKey: .duration)
        let dolbyContainer = try? container
            .nestedContainer(keyedBy: NestedMediaCodingKeys.self, forKey: .dolby)
        video = Self.mergedStreams(
            primary: try container.decodeIfPresent([DASHStream].self, forKey: .video),
            secondary: try dolbyContainer?.decodeIfPresent([DASHStream].self, forKey: .video)
        )

        let flacAudio = try (try? container
            .nestedContainer(keyedBy: NestedMediaCodingKeys.self, forKey: .flac))?
            .decodeIfPresent(DASHStream.self, forKey: .audio)
        let dolbyAudio = try dolbyContainer?.decodeIfPresent([DASHStream].self, forKey: .audio)
        audio = Self.mergedStreams(
            primary: (flacAudio.map { [$0] } ?? []) + (dolbyAudio ?? []),
            secondary: try container.decodeIfPresent([DASHStream].self, forKey: .audio)
        )
    }

    init(
        duration: Int?,
        video: [DASHStream]?,
        audio: [DASHStream]?
    ) {
        self.duration = duration
        self.video = video
        self.audio = audio
    }

    nonisolated var bestAudioStream: DASHStream? {
        audio?
            .filter(\.isHardwareDecodingCompatibleAudio)
            .sorted { lhs, rhs in
                if lhs.audioPlaybackRank != rhs.audioPlaybackRank {
                    return lhs.audioPlaybackRank < rhs.audioPlaybackRank
                }
                return (lhs.bandwidth ?? 0) > (rhs.bandwidth ?? 0)
            }
            .first
    }

    nonisolated func mergingStreams(from other: DASHInfo?) -> DASHInfo {
        DASHInfo(
            duration: duration ?? other?.duration,
            video: Self.mergedStreams(primary: video, secondary: other?.video),
            audio: Self.mergedStreams(primary: audio, secondary: other?.audio)
        )
    }

    nonisolated private static func mergedStreams(primary: [DASHStream]?, secondary: [DASHStream]?) -> [DASHStream]? {
        var result = primary ?? []
        let existingKeys = Set(result.map(Self.streamKey))

        var seenKeys = existingKeys
        for stream in secondary ?? [] {
            let key = Self.streamKey(stream)
            guard seenKeys.insert(key).inserted else { continue }
            result.append(stream)
        }

        return result.isEmpty ? nil : result
    }

    nonisolated private static func streamKey(_ stream: DASHStream) -> String {
        [
            String(stream.id ?? 0),
            stream.codecs ?? "",
            stream.mimeType ?? "",
            stream.baseURL
        ].joined(separator: "|")
    }
}

nonisolated struct DASHStream: Decodable, Hashable, Sendable {
    let id: Int?
    let baseURL: String
    let backupURL: [String]?
    let bandwidth: Int?
    let codecs: String?
    let codecid: Int?
    let width: Int?
    let height: Int?
    let frameRate: String?
    let mimeType: String?
    let segmentBase: DASHSegmentBase?

    enum CodingKeys: String, CodingKey {
        case id, bandwidth, codecs, codecid, width, height
        case mimeType = "mimeType"
        case mimeTypeAlt = "mime_type"
        case baseURL = "baseUrl"
        case baseURLAlt = "base_url"
        case backupURL = "backupUrl"
        case backupURLAlt = "backup_url"
        case frameRate
        case frameRateAlt = "frame_rate"
        case segmentBase = "SegmentBase"
        case segmentBaseAlt = "segment_base"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeLossyIntIfPresent(forKey: .id)
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL)
            ?? container.decodeIfPresent(String.self, forKey: .baseURLAlt)
            ?? ""
        backupURL = try container.decodeIfPresent([String].self, forKey: .backupURL)
            ?? container.decodeIfPresent([String].self, forKey: .backupURLAlt)
        bandwidth = container.decodeLossyIntIfPresent(forKey: .bandwidth)
        codecs = try container.decodeIfPresent(String.self, forKey: .codecs)
        codecid = container.decodeLossyIntIfPresent(forKey: .codecid)
        width = container.decodeLossyIntIfPresent(forKey: .width)
        height = container.decodeLossyIntIfPresent(forKey: .height)
        frameRate = container.decodeLossyStringIfPresent(forKey: .frameRate)
            ?? container.decodeLossyStringIfPresent(forKey: .frameRateAlt)
        mimeType = container.decodeLossyStringIfPresent(forKey: .mimeType)
            ?? container.decodeLossyStringIfPresent(forKey: .mimeTypeAlt)
        segmentBase = try container.decodeIfPresent(DASHSegmentBase.self, forKey: .segmentBase)
            ?? container.decodeIfPresent(DASHSegmentBase.self, forKey: .segmentBaseAlt)
    }

    nonisolated var playURL: URL? {
        playURL(cdnPreference: .automatic)
    }

    nonisolated func playURL(cdnPreference: PlaybackCDNPreference) -> URL? {
        let primary = URL(string: baseURL)
        return cdnPreference.preferredURLs(primary: primary, backups: backupPlayURLs).primary
    }

    nonisolated func playURL(cdnPreference: PlaybackCDNPreference, prefersBackup: Bool) -> URL? {
        let preference: PlaybackCDNPreference = prefersBackup ? .backupURL : cdnPreference
        return playURL(cdnPreference: preference)
    }

    nonisolated var backupPlayURLs: [URL] {
        backupURL?.compactMap(URL.init(string:)) ?? []
    }

    nonisolated func backupPlayURLs(cdnPreference: PlaybackCDNPreference) -> [URL] {
        let primary = URL(string: baseURL)
        return cdnPreference.preferredURLs(primary: primary, backups: backupPlayURLs).backups
    }

    nonisolated func backupPlayURLs(cdnPreference: PlaybackCDNPreference, prefersBackup: Bool) -> [URL] {
        let preference: PlaybackCDNPreference = prefersBackup ? .backupURL : cdnPreference
        return backupPlayURLs(cdnPreference: preference)
    }

    nonisolated func playbackURLCandidates(cdnPreference: PlaybackCDNPreference) -> [URL] {
        let primary = URL(string: baseURL)
        let preferred = cdnPreference.preferredURLs(primary: primary, backups: backupPlayURLs)
        return Self.removingDuplicateURLs(
            [preferred.primary].compactMap { $0 } + preferred.backups + [primary].compactMap { $0 } + backupPlayURLs
        )
    }

    nonisolated func fallbackPlayURLs(cdnPreference: PlaybackCDNPreference, selectedURL: URL?) -> [URL] {
        playbackURLCandidates(cdnPreference: cdnPreference)
            .filter { $0 != selectedURL }
    }

    nonisolated private static func removingDuplicateURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.absoluteString).inserted }
    }

    nonisolated var codecLabel: String? {
        Self.codecLabel(for: codecs, codecid: codecid)
    }

    nonisolated var isHEVCVideoCodec: Bool {
        if let codecs, !codecs.isEmpty {
            let lowered = codecs.lowercased()
            return lowered.contains("hvc1")
                || lowered.contains("hev1")
                || lowered.contains("dvh1")
                || lowered.contains("dvhe")
        }
        return codecid == 12
    }

    nonisolated var isDolbyVisionVideoCodec: Bool {
        guard let codecs, !codecs.isEmpty else { return false }
        let lowered = codecs.lowercased()
        return lowered.contains("dvh1") || lowered.contains("dvhe")
    }

    nonisolated var isAVCVideoCodec: Bool {
        if let codecs, !codecs.isEmpty {
            let lowered = codecs.lowercased()
            return lowered.contains("avc1") || lowered.contains("avc3")
        }
        return codecid == 7
    }

    nonisolated var isAV1VideoCodec: Bool {
        if let codecs, !codecs.isEmpty {
            return codecs.lowercased().contains("av01")
        }
        return codecid == 13
    }

    nonisolated var isAACAudioCodec: Bool {
        guard let codecs, !codecs.isEmpty else {
            // Bilibili occasionally omits audio codec metadata on DASH audio
            // tracks that are still mp4a in practice; keep those eligible so
            // the HLS bridge can advertise the conservative AAC default.
            return true
        }
        return codecs.lowercased().contains("mp4a")
    }

    nonisolated var isDolbyCompatibleAudioCodec: Bool {
        guard let codecs, !codecs.isEmpty else { return false }
        let lowered = codecs.lowercased()
        return lowered.contains("ec-3") || lowered.contains("ac-3")
    }

    nonisolated var isLosslessAudioCodec: Bool {
        guard let codecs, !codecs.isEmpty else { return false }
        let lowered = codecs.lowercased()
        return lowered.contains("flac") || lowered.contains("alac")
    }

    nonisolated var audioPlaybackRank: Int {
        if isAACAudioCodec {
            return 0
        }
        if isDolbyCompatibleAudioCodec {
            return 1
        }
        if isLosslessAudioCodec {
            return 2
        }
        return 3
    }

    nonisolated static func codecLabel(for codecs: String?, codecid: Int? = nil) -> String? {
        if let codecs, !codecs.isEmpty {
            if codecs.localizedCaseInsensitiveContains("dvh1") || codecs.localizedCaseInsensitiveContains("dvhe") {
                return "Dolby Vision"
            }
            if codecs.localizedCaseInsensitiveContains("hev") || codecs.localizedCaseInsensitiveContains("hvc") {
                return "HEVC"
            }
            if codecs.localizedCaseInsensitiveContains("av01") {
                return "AV1"
            }
            if codecs.localizedCaseInsensitiveContains("avc") {
                return "AVC"
            }
            if codecs.localizedCaseInsensitiveContains("mp4a") {
                return "AAC"
            }
            if codecs.localizedCaseInsensitiveContains("ec-3")
                || codecs.localizedCaseInsensitiveContains("ac-3") {
                return "Dolby Audio"
            }
            if codecs.localizedCaseInsensitiveContains("flac") {
                return "FLAC"
            }
            if codecs.localizedCaseInsensitiveContains("alac") {
                return "ALAC"
            }
            return codecs
        }
        switch codecid {
        case 7:
            return "AVC"
        case 12:
            return "HEVC"
        case 13:
            return "AV1"
        default:
            return nil
        }
    }

    nonisolated var resolutionLabel: String? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return "\(width)x\(height)"
    }

    nonisolated var hlsDimensions: CGSize? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }

    nonisolated var displayFrameRate: String? {
        Self.displayFrameRate(from: frameRate)
    }

    nonisolated var isHardwareDecodingCompatibleVideo: Bool {
        if isAV1VideoCodec {
            return PlaybackCodecPolicy.canDecodeAV1
        }

        if isHEVCVideoCodec {
            return PlaybackCodecPolicy.canDecodeHEVC
        }

        if PlaybackCodecPolicy.requiresHEVCPlayback,
           !PlaybackCodecPolicy.allowsNonHEVCHardwareFallback {
            return false
        }

        if let codecs, !codecs.isEmpty {
            let lowered = codecs.lowercased()
            return lowered.contains("avc1")
                || lowered.contains("avc3")
                || lowered.contains("dvh1")
                || lowered.contains("dvhe")
        }

        switch codecid {
        case 7:
            return true
        default:
            return false
        }
    }

    nonisolated var isHardwareDecodingCompatibleAudio: Bool {
        if PlaybackCodecPolicy.requiresAACAudioPlayback {
            return isAACAudioCodec || isDolbyCompatibleAudioCodec || isLosslessAudioCodec
        }

        if let codecs, !codecs.isEmpty {
            let lowered = codecs.lowercased()
            return lowered.contains("mp4a")
                || lowered.contains("alac")
                || lowered.contains("ac-3")
                || lowered.contains("ec-3")
                || lowered.contains("opus")
        }
        return true
    }

    nonisolated static func displayFrameRate(from rawValue: String?) -> String? {
        guard let value = numericFrameRate(from: rawValue) else {
            guard let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty
            else { return nil }
            return trimmed
        }
        return formatFrameRate(value)
    }

    nonisolated static func numericFrameRate(from rawValue: String?) -> Double? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let value = Double(trimmed) {
            return value
        }

        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        if parts.count == 2,
           let numerator = Double(parts[0]),
           let denominator = Double(parts[1]),
           denominator != 0 {
            return numerator / denominator
        }

        return nil
    }

    nonisolated static func preferPlayable(_ lhs: DASHStream, _ rhs: DASHStream) -> Bool {
        if lhs.isHardwareDecodingCompatibleVideo != rhs.isHardwareDecodingCompatibleVideo {
            return lhs.isHardwareDecodingCompatibleVideo && !rhs.isHardwareDecodingCompatibleVideo
        }
        return codecRank(lhs) != codecRank(rhs)
            ? codecRank(lhs) > codecRank(rhs)
            : (lhs.bandwidth ?? 0) > (rhs.bandwidth ?? 0)
    }

    nonisolated private static func codecRank(_ stream: DASHStream) -> Int {
        if let codecs = stream.codecs?.lowercased() {
            if codecs.contains("av01") {
                return 1
            }
            if codecs.contains("dvh1") || codecs.contains("dvhe") {
                return 5
            }
            if codecs.contains("hvc1") || codecs.contains("hev1") {
                return 4
            }
            if codecs.contains("avc1") || codecs.contains("avc3") {
                return 3
            }
        }
        switch stream.codecid {
        case 13:
            return 1
        case 12:
            return 4
        case 7:
            return 3
        default:
            return 0
        }
    }

    nonisolated private static func formatFrameRate(_ value: Double) -> String {
        let roundedValue = value.rounded()
        if abs(roundedValue - value) < 0.05 {
            return String(Int(roundedValue))
        }
        return String(format: "%.1f", value)
    }
}

nonisolated struct DASHSegmentBase: Decodable, Hashable, Sendable {
    let initialization: String?
    let indexRange: String?

    enum CodingKeys: String, CodingKey {
        case initialization
        case initializationAlt = "Initialization"
        case indexRange = "indexRange"
        case indexRangeAlt = "index_range"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        initialization = container.decodeLossyStringIfPresent(forKey: .initialization)
            ?? container.decodeLossyStringIfPresent(forKey: .initializationAlt)
        indexRange = container.decodeLossyStringIfPresent(forKey: .indexRange)
            ?? container.decodeLossyStringIfPresent(forKey: .indexRangeAlt)
    }

    nonisolated var initializationByteRange: HTTPByteRange? {
        HTTPByteRange(rawValue: initialization)
    }

    nonisolated var indexByteRange: HTTPByteRange? {
        HTTPByteRange(rawValue: indexRange)
    }
}

nonisolated struct HTTPByteRange: Hashable, Sendable {
    let start: Int64
    let endInclusive: Int64

    nonisolated var length: Int64 {
        max(endInclusive - start + 1, 0)
    }

    nonisolated init(start: Int64, endInclusive: Int64) {
        self.start = start
        self.endInclusive = endInclusive
    }

    nonisolated init?(httpHeaderValue: String?) {
        guard let httpHeaderValue else { return nil }
        let normalizedValue = httpHeaderValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard normalizedValue.hasPrefix("bytes=") else { return nil }
        let payload = String(normalizedValue.dropFirst("bytes=".count))
        if let range = HTTPByteRange(rawValue: payload) {
            self = range
            return
        }
        let parts = payload
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        if parts[0].isEmpty,
           let suffixLength = Int64(parts[1]),
           suffixLength > 0 {
            start = -suffixLength
            endInclusive = -1
            return
        }
        if parts[1].isEmpty,
           let start = Int64(parts[0]),
           start >= 0 {
            self.start = start
            endInclusive = Int64.max
            return
        }
        return nil
    }

    nonisolated init?(rawValue: String?) {
        guard let rawValue else { return nil }
        let parts = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let start = Int64(parts[0]),
              let end = Int64(parts[1]),
              start >= 0,
              end >= start
        else { return nil }
        self.start = start
        self.endInclusive = end
    }

    nonisolated func clamped(toLength length: Int64) -> HTTPByteRange? {
        guard length > 0 else { return nil }
        if start < 0, endInclusive == -1 {
            let suffixLength = min(-start, length)
            return HTTPByteRange(start: length - suffixLength, endInclusive: length - 1)
        }
        let lowerBound = min(max(start, 0), length - 1)
        let upperBound = min(max(endInclusive, lowerBound), length - 1)
        return HTTPByteRange(start: lowerBound, endInclusive: upperBound)
    }
}

nonisolated struct CommentPage: Decodable, Sendable {
    let replies: [Comment]?
    let topReplies: [Comment]?
    let root: Comment?
    let cursor: CommentCursor?

    enum CodingKeys: String, CodingKey {
        case replies, root, cursor
        case topReplies = "top_replies"
    }

    init(
        replies: [Comment]?,
        topReplies: [Comment]?,
        root: Comment? = nil,
        cursor: CommentCursor?
    ) {
        self.replies = replies
        self.topReplies = topReplies
        self.root = root
        self.cursor = cursor
    }
}

nonisolated struct CommentCursor: Decodable, Sendable {
    let next: String?
    let nextOffset: String?
    let isEnd: Bool?

    var effectiveNext: String? {
        Self.nonEmpty(next) ?? Self.nonEmpty(nextOffset)
    }

    enum CodingKeys: String, CodingKey {
        case next
        case nextOffset = "next_offset"
        case isEnd = "is_end"
        case paginationReply = "pagination_reply"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        next = container.decodeLossyStringIfPresent(forKey: .next)
        let nestedPagination = try? container.decodeIfPresent(CommentCursorPaginationReply.self, forKey: .paginationReply)
        nextOffset = container.decodeLossyStringIfPresent(forKey: .nextOffset)
            ?? nestedPagination?.nextOffset
        isEnd = container.decodeLossyBoolIfPresent(forKey: .isEnd)
            ?? nestedPagination?.isEnd
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

nonisolated private struct CommentCursorPaginationReply: Decodable, Sendable {
    let nextOffset: String?
    let isEnd: Bool?

    enum CodingKeys: String, CodingKey {
        case nextOffset = "next_offset"
        case isEnd = "is_end"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nextOffset = container.decodeLossyStringIfPresent(forKey: .nextOffset)
        isEnd = container.decodeLossyBoolIfPresent(forKey: .isEnd)
    }
}

nonisolated struct Comment: Identifiable, Decodable, Hashable, Sendable {
    let rpid: Int
    let rootID: Int?
    let parentID: Int?
    let dialogID: Int?
    let member: CommentMember?
    let content: CommentContent?
    let like: Int?
    let ctime: Int?
    let replies: [Comment]?
    let replyCount: Int?
    let likeState: Int?

    var id: Int { rpid }

    var containsGoodsPromotion: Bool {
        content?.containsGoodsPromotion == true
            || replies?.contains(where: \.containsGoodsPromotion) == true
    }

    enum CodingKeys: String, CodingKey {
        case rpid, member, content, like, ctime, replies
        case action
        case rootID = "root"
        case parentID = "parent"
        case dialogID = "dialog"
        case replyCount = "rcount"
        case likeState = "like_state"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rpid = container.decodeLossyIntIfPresent(forKey: .rpid) ?? 0
        rootID = container.decodeLossyIntIfPresent(forKey: .rootID)
        parentID = container.decodeLossyIntIfPresent(forKey: .parentID)
        dialogID = container.decodeLossyIntIfPresent(forKey: .dialogID)
        member = try container.decodeIfPresent(CommentMember.self, forKey: .member)
        content = try container.decodeIfPresent(CommentContent.self, forKey: .content)
        like = container.decodeLossyIntIfPresent(forKey: .like)
        ctime = container.decodeLossyIntIfPresent(forKey: .ctime)
        replies = try container.decodeIfPresent([Comment].self, forKey: .replies)
        replyCount = container.decodeLossyIntIfPresent(forKey: .replyCount)
        likeState = container.decodeLossyIntIfPresent(forKey: .action)
            ?? container.decodeLossyIntIfPresent(forKey: .likeState)
    }
}

nonisolated struct CommentMember: Decodable, Hashable, Sendable {
    let mid: String?
    let uname: String?
    let avatar: String?
    let levelInfo: CommentLevelInfo?

    enum CodingKeys: String, CodingKey {
        case mid, uname, avatar
        case levelInfo = "level_info"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mid = container.decodeLossyStringIfPresent(forKey: .mid)
        uname = try container.decodeIfPresent(String.self, forKey: .uname)
        avatar = try container.decodeIfPresent(String.self, forKey: .avatar)
        levelInfo = try container.decodeIfPresent(CommentLevelInfo.self, forKey: .levelInfo)
    }

    nonisolated var videoOwner: VideoOwner? {
        guard let numericMID else { return nil }
        let trimmedName = uname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return VideoOwner(
            mid: numericMID,
            name: trimmedName.isEmpty ? "用户 \(numericMID)" : trimmedName,
            face: avatar
        )
    }

    private nonisolated var numericMID: Int? {
        let rawMID = mid?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let numericMID = Int(rawMID), numericMID > 0 else { return nil }
        return numericMID
    }
}

nonisolated struct CommentLevelInfo: Decodable, Hashable, Sendable {
    let currentLevel: Int?

    enum CodingKeys: String, CodingKey {
        case currentLevel = "current_level"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currentLevel = container.decodeLossyIntIfPresent(forKey: .currentLevel)
    }
}

nonisolated struct CommentContent: Decodable, Hashable, Sendable {
    let message: String?
    let emotes: [String: CommentEmote]
    let pictures: [DynamicImageItem]
    let jumpURLs: DynamicJSONValue?
    let mentions: [BiliMention]
    private let hasGoodsMetadata: Bool

    enum CodingKeys: String, CodingKey {
        case message
        case emote
        case emotes
        case jumpURL = "jump_url"
        case jumpURLs = "jump_urls"
        case urls
        case pictures
        case pics
        case images
    }

    init(from decoder: Decoder) throws {
        let raw = try? DynamicJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = container.decodeLossyStringIfPresent(forKey: .message)
        let emoteMap = try container.decodeIfPresent([String: CommentEmote].self, forKey: .emote)
        let emotesMap = try container.decodeIfPresent([String: CommentEmote].self, forKey: .emotes)
        emotes = emoteMap ?? emotesMap ?? [:]
        jumpURLs = (try? container.decodeIfPresent(DynamicJSONValue.self, forKey: .jumpURL))
            ?? (try? container.decodeIfPresent(DynamicJSONValue.self, forKey: .jumpURLs))
            ?? (try? container.decodeIfPresent(DynamicJSONValue.self, forKey: .urls))
        pictures = (try? container.decodeIfPresent([DynamicImageItem].self, forKey: .pictures))
            ?? (try? container.decodeIfPresent([DynamicImageItem].self, forKey: .pics))
            ?? (try? container.decodeIfPresent([DynamicImageItem].self, forKey: .images))
            ?? []
        mentions = BiliMentionExtractor.commentMentions(raw: raw, message: message, jumpURLs: jumpURLs)
        hasGoodsMetadata = raw?.containsGoodsMetadata == true
    }

    func emote(for text: String) -> CommentEmote? {
        emotes[text] ?? emotes.values.first { $0.text == text }
    }

    var containsGoodsPromotion: Bool {
        hasGoodsMetadata
            || message.map(BiliContentFilter.isGoodsText) == true
            || jumpURLs?.containsGoodsMetadata == true
    }
}

nonisolated struct CommentEmote: Decodable, Hashable, Sendable {
    let text: String?
    let url: String?
    let gifURL: String?
    let width: Int?
    let height: Int?

    enum CodingKeys: String, CodingKey {
        case text, url, width, height
        case gifURL = "gif_url"
        case gifUrl = "gifUrl"
        case meta
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = container.decodeLossyStringIfPresent(forKey: .text)
        url = container.decodeLossyStringIfPresent(forKey: .url)
        gifURL = container.decodeLossyStringIfPresent(forKey: .gifURL)
            ?? container.decodeLossyStringIfPresent(forKey: .gifUrl)
        width = container.decodeLossyIntIfPresent(forKey: .width)
        height = container.decodeLossyIntIfPresent(forKey: .height)
    }

    var displayURL: String? {
        (url ?? gifURL)?.normalizedBiliURL()
    }
}

nonisolated struct AccountVideoEntry: Identifiable, Hashable {
    var id: String { bvid }

    let bvid: String
    let aid: Int?
    let title: String
    let pic: String?
    let duration: Int?
    let owner: VideoOwner?
    let stat: VideoStat?
    let cid: Int?
    let savedAt: Date
    let playbackTime: TimeInterval?
    let playbackDuration: TimeInterval?
    let pgcSeasonID: Int?
    let pgcEpisodeID: Int?

    var videoItem: VideoItem {
        VideoItem(
            bvid: bvid,
            aid: aid,
            title: title,
            pic: pic,
            desc: nil,
            duration: duration,
            pubdate: nil,
            owner: owner,
            stat: stat,
            cid: cid,
            pages: nil,
            dimension: nil,
            historyResumeTime: resumeTime,
            historyCID: cid,
            pgcSeasonID: pgcSeasonID,
            pgcEpisodeID: pgcEpisodeID
        )
    }

    var resumeTime: TimeInterval? {
        guard let playbackTime,
              playbackTime >= TimeInterval(LibraryStore.defaultPlaybackHistorySyncThresholdSeconds)
        else { return nil }
        if let playbackDuration, playbackDuration > 0 {
            let remaining = playbackDuration - playbackTime
            guard remaining > 15, playbackTime / playbackDuration < 0.96 else { return nil }
        }
        return playbackTime
    }

    var playbackProgress: Double? {
        guard let playbackTime, playbackTime > 0 else { return nil }
        guard let playbackDuration, playbackDuration > 0 else { return nil }
        return min(max(playbackTime / playbackDuration, 0), 1)
    }
}

nonisolated struct VideoHistoryProgress: Decodable, Hashable {
    let progress: TimeInterval?
    let lastPlayCid: Int?

    enum CodingKeys: String, CodingKey {
        case progress
        case lastPlayCid = "last_play_cid"
        case cid
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        progress = container.decodeLossyDoubleIfPresent(forKey: .progress)
        lastPlayCid = container.decodeLossyIntIfPresent(forKey: .lastPlayCid)
            ?? container.decodeLossyIntIfPresent(forKey: .cid)
    }

    func resumeTime(
        duration: TimeInterval?,
        minimumProgress: TimeInterval = TimeInterval(LibraryStore.defaultPlaybackHistorySyncThresholdSeconds)
    ) -> TimeInterval? {
        guard let progress, progress >= minimumProgress else { return nil }
        if let duration, duration > 0 {
            let remaining = duration - progress
            guard remaining > 15, progress / duration < 0.96 else { return nil }
        }
        return progress
    }
}

nonisolated struct SearchTypeData<Result: Decodable>: Decodable {
    let result: [Result]?
}

extension SearchTypeData: Sendable where Result: Sendable {}

nonisolated struct SearchVideoItem: Identifiable, Decodable, Hashable, Sendable {
    var id: String { bvid }

    let bvid: String
    let aid: Int?
    let title: String
    let pic: String?
    let author: String?
    let mid: Int?
    let play: Int?
    let duration: String?
    let description: String?
    let pubdate: Int?

    enum CodingKeys: String, CodingKey {
        case bvid, aid, title, pic, author, mid, play, duration, description, pubdate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bvid = try container.decodeIfPresent(String.self, forKey: .bvid) ?? ""
        aid = container.decodeLossyIntIfPresent(forKey: .aid)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Untitled"
        pic = try container.decodeIfPresent(String.self, forKey: .pic)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        mid = container.decodeLossyIntIfPresent(forKey: .mid)
        play = container.decodeLossyIntIfPresent(forKey: .play)
        duration = container.decodeLossyStringIfPresent(forKey: .duration)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        pubdate = container.decodeLossyIntIfPresent(forKey: .pubdate)
    }

    func asVideoItem() -> VideoItem {
        VideoItem(
            bvid: bvid,
            aid: aid,
            title: title.removingHTMLTags(),
            pic: pic?.normalizedBiliURL(),
            desc: description,
            duration: duration.flatMap(Self.durationSeconds),
            pubdate: pubdate,
            owner: VideoOwner(mid: mid ?? 0, name: author ?? "", face: nil),
            stat: VideoStat(view: play, reply: nil, like: nil, coin: nil, favorite: nil),
            cid: nil,
            pages: nil,
            dimension: nil
        )
    }

    nonisolated private static func durationSeconds(_ value: String) -> Int {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        if parts.count == 2 {
            return parts[0] * 60 + parts[1]
        }
        if parts.count == 3 {
            return parts[0] * 3600 + parts[1] * 60 + parts[2]
        }
        return 0
    }
}

nonisolated struct SearchUserItem: Identifiable, Decodable, Hashable, Sendable {
    var id: Int { mid }

    let mid: Int
    let name: String
    let face: String?
    let sign: String?
    let fans: Int?
    let videos: Int?
    let officialDescription: String?
    let isFollowing: Bool?

    enum CodingKeys: String, CodingKey {
        case mid, fans, videos
        case name = "uname"
        case face = "upic"
        case sign = "usign"
        case officialVerify = "official_verify"
        case isFollowing = "is_atten"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mid = container.decodeLossyIntIfPresent(forKey: .mid) ?? 0
        name = ((try? container.decodeIfPresent(String.self, forKey: .name)) ?? "Unknown").removingHTMLTags()
        face = try? container.decodeIfPresent(String.self, forKey: .face)
        sign = try? container.decodeIfPresent(String.self, forKey: .sign)
        fans = container.decodeLossyIntIfPresent(forKey: .fans)
        videos = container.decodeLossyIntIfPresent(forKey: .videos)
        officialDescription = try? container.decodeIfPresent(SearchUserOfficialVerify.self, forKey: .officialVerify)?.desc
        isFollowing = container.decodeLossyBoolIfPresent(forKey: .isFollowing)
    }

    var owner: VideoOwner {
        VideoOwner(mid: mid, name: name, face: face?.normalizedBiliURL())
    }
}

nonisolated struct SearchUserOfficialVerify: Decodable, Hashable, Sendable {
    let desc: String?
}

nonisolated struct SearchMediaItem: Identifiable, Decodable, Hashable, Sendable {
    var id: String {
        if let mediaID {
            return "media-\(mediaID)"
        }
        if let seasonID {
            return "season-\(seasonID)"
        }
        return title
    }

    let mediaID: Int?
    let seasonID: Int?
    let title: String
    let cover: String?
    let description: String?
    let typeName: String?
    let indexShow: String?
    let rating: String?
    let stylesText: String?
    let url: String?
    let gotoURL: String?

    enum CodingKeys: String, CodingKey {
        case title, cover, url, rating, styles
        case mediaID = "media_id"
        case seasonID = "season_id"
        case description = "desc"
        case typeName = "season_type_name"
        case indexShow = "index_show"
        case gotoURL = "goto_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mediaID = container.decodeLossyIntIfPresent(forKey: .mediaID)
        seasonID = container.decodeLossyIntIfPresent(forKey: .seasonID)
        title = ((try? container.decodeIfPresent(String.self, forKey: .title)) ?? "Untitled").removingHTMLTags()
        cover = try? container.decodeIfPresent(String.self, forKey: .cover)
        description = try? container.decodeIfPresent(String.self, forKey: .description)
        typeName = try? container.decodeIfPresent(String.self, forKey: .typeName)
        indexShow = try? container.decodeIfPresent(String.self, forKey: .indexShow)
        rating = (try? container.decodeIfPresent(SearchMediaRating.self, forKey: .rating))?.displayScore
            ?? container.decodeLossyStringIfPresent(forKey: .rating)
        stylesText = (try? container.decodeIfPresent([String].self, forKey: .styles))?.joined(separator: " / ")
            ?? container.decodeLossyStringIfPresent(forKey: .styles)
        url = try? container.decodeIfPresent(String.self, forKey: .url)
        gotoURL = try? container.decodeIfPresent(String.self, forKey: .gotoURL)
    }

    var destinationURL: URL? {
        for rawURL in [url, gotoURL] {
            guard let rawURL, !rawURL.isEmpty else { continue }
            let normalized = rawURL.normalizedBiliURL()
            if let url = URL(string: normalized) {
                return url
            }
        }
        if let seasonID {
            return URL(string: "https://www.bilibili.com/bangumi/play/ss\(seasonID)")
        }
        if let mediaID {
            return URL(string: "https://www.bilibili.com/bangumi/media/md\(mediaID)")
        }
        return nil
    }
}

nonisolated struct SearchMediaRating: Decodable, Hashable, Sendable {
    let score: Double?

    enum CodingKeys: String, CodingKey {
        case score
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        score = (try? container.decodeIfPresent(Double.self, forKey: .score))
            ?? container.decodeLossyStringIfPresent(forKey: .score).flatMap(Double.init)
    }

    var displayScore: String? {
        guard let score else { return nil }
        return String(format: "%.1f", score)
    }
}

nonisolated struct SearchArticleItem: Identifiable, Decodable, Hashable, Sendable {
    var id: Int { articleID }

    let articleID: Int
    let title: String
    let description: String?
    let author: String?
    let imageURLs: [String]
    let view: Int?
    let reply: Int?
    let like: Int?
    let pubTime: Int?
    let url: String?

    enum CodingKeys: String, CodingKey {
        case title, author, view, reply, like, url
        case articleID = "id"
        case description = "desc"
        case imageURLs = "image_urls"
        case pubTime = "pub_time"
        case pubTimeAlt = "pubdate"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        articleID = container.decodeLossyIntIfPresent(forKey: .articleID) ?? 0
        title = ((try? container.decodeIfPresent(String.self, forKey: .title)) ?? "Untitled").removingHTMLTags()
        description = try? container.decodeIfPresent(String.self, forKey: .description)
        author = try? container.decodeIfPresent(String.self, forKey: .author)
        imageURLs = ((try? container.decodeIfPresent([String].self, forKey: .imageURLs)) ?? [])
            .map { $0.normalizedBiliURL() }
        view = container.decodeLossyIntIfPresent(forKey: .view)
        reply = container.decodeLossyIntIfPresent(forKey: .reply)
        like = container.decodeLossyIntIfPresent(forKey: .like)
        pubTime = container.decodeLossyIntIfPresent(forKey: .pubTime)
            ?? container.decodeLossyIntIfPresent(forKey: .pubTimeAlt)
        url = try? container.decodeIfPresent(String.self, forKey: .url)
    }

    var destinationURL: URL? {
        if let url, !url.isEmpty, let destination = URL(string: url.normalizedBiliURL()) {
            return destination
        }
        guard articleID > 0 else { return nil }
        return URL(string: "https://www.bilibili.com/read/cv\(articleID)")
    }
}

nonisolated struct SearchSuggestResponse: Decodable, Sendable {
    let tag: [SearchSuggestItem]?
}

nonisolated struct SearchSuggestItem: Identifiable, Decodable, Hashable, Sendable {
    var id: String { value }

    let value: String
    let ref: Int?
}

nonisolated struct HotSearchData: Decodable, Sendable {
    let trending: HotSearchTrending?
}

nonisolated struct HotSearchTrending: Decodable, Sendable {
    let list: [HotSearchItem]?
}

nonisolated struct HotSearchItem: Identifiable, Decodable, Hashable, Sendable {
    var id: String { keyword }

    let keyword: String
    let showName: String?
    let icon: String?

    enum CodingKeys: String, CodingKey {
        case keyword, icon
        case showName = "show_name"
    }
}

nonisolated struct EmptyBiliPayload: Decodable, Sendable {}

nonisolated struct VideoInteractionState: Hashable, Sendable {
    var isLiked = false
    var coinCount = 0
    var isFavorited = false
    var isFollowing = false

    var isCoined: Bool {
        coinCount > 0
    }
}

nonisolated struct VideoArchiveRelationState: Decodable, Hashable {
    let isLiked: Bool
    let coinCount: Int
    let isFavorited: Bool
    let isFollowing: Bool

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isLiked = container.decodeLossyBoolIfPresent(forKey: .like) ?? false
        coinCount = container.decodeLossyIntIfPresent(forKey: .coin) ?? 0
        isFavorited = container.decodeLossyBoolIfPresent(forKey: .favorite) ?? false
        isFollowing = container.decodeLossyBoolIfPresent(forKey: .attention) ?? false
    }

    var interactionState: VideoInteractionState {
        VideoInteractionState(
            isLiked: isLiked,
            coinCount: coinCount,
            isFavorited: isFavorited,
            isFollowing: isFollowing
        )
    }

    private enum CodingKeys: String, CodingKey {
        case like
        case coin
        case favorite
        case attention
    }
}

nonisolated struct VideoCoinState: Decodable, Hashable {
    let multiply: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        multiply = container.decodeLossyIntIfPresent(forKey: .multiply)
    }

    private enum CodingKeys: String, CodingKey {
        case multiply
    }
}

nonisolated struct VideoFavoriteState: Decodable, Hashable {
    let favoured: Bool?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        favoured = container.decodeLossyBoolIfPresent(forKey: .favoured)
    }

    private enum CodingKeys: String, CodingKey {
        case favoured
    }
}

nonisolated struct FavoriteFolderListData: Decodable, Hashable {
    let list: [FavoriteFolder]?
}

nonisolated struct FavoriteFolder: Identifiable, Decodable, Hashable {
    let id: Int
    let title: String?
    let favState: Int?
    let mediaCount: Int?
    let cover: String?
    let intro: String?
    let attr: Int?
    let state: Int?
    let ctime: Int?
    let mtime: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, cover, intro, attr, state, ctime, mtime
        case mediaID = "media_id"
        case favState = "fav_state"
        case mediaCount = "media_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeLossyIntIfPresent(forKey: .id)
            ?? container.decodeLossyIntIfPresent(forKey: .mediaID)
            ?? 0
        title = try container.decodeIfPresent(String.self, forKey: .title)
        favState = container.decodeLossyIntIfPresent(forKey: .favState)
        mediaCount = container.decodeLossyIntIfPresent(forKey: .mediaCount)
        cover = try container.decodeIfPresent(String.self, forKey: .cover)
        intro = try container.decodeIfPresent(String.self, forKey: .intro)
        attr = container.decodeLossyIntIfPresent(forKey: .attr)
        state = container.decodeLossyIntIfPresent(forKey: .state)
        ctime = container.decodeLossyIntIfPresent(forKey: .ctime)
        mtime = container.decodeLossyIntIfPresent(forKey: .mtime)
    }

    var displayTitle: String {
        let normalizedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedTitle?.isEmpty == false ? normalizedTitle! : "未命名收藏夹"
    }

    var isFavorited: Bool {
        favState == 1
    }
}

nonisolated private func firstNonBlankDynamicText(_ values: [String?]) -> String? {
    values
        .compactMap { $0?.removingHTMLTags().trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty }
}

nonisolated private func joinedDynamicText(_ values: [String?], separator: String = "") -> String? {
    let text = values
        .compactMap { $0?.removingHTMLTags().trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: separator)
    return text.isEmpty ? nil : text
}

nonisolated struct BiliMention: Hashable, Sendable {
    let text: String
    let mid: Int?
    let url: String?

    init?(text: String?, mid: Int? = nil, url: String? = nil) {
        guard let displayText = Self.normalizedDisplayText(text) else { return nil }
        let resolvedMID = mid ?? Self.userMID(in: url)
        self.text = displayText
        self.mid = resolvedMID
        let normalizedURL = url?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.url = normalizedURL?.isEmpty == false ? normalizedURL : nil
    }

    var name: String {
        text.hasPrefix("@") ? String(text.dropFirst()) : text
    }

    var destinationURL: URL? {
        if let mid, mid > 0 {
            var components = URLComponents()
            components.scheme = "https"
            components.host = "space.bilibili.com"
            components.path = "/\(mid)"
            if !name.isEmpty {
                components.queryItems = [URLQueryItem(name: "name", value: name)]
            }
            return components.url
        }

        guard let url else { return nil }
        let normalized = url.normalizedBiliURL()
        if let mid = Self.userMID(in: normalized), mid > 0 {
            return URL(string: "https://space.bilibili.com/\(mid)")
        }
        return URL(string: normalized)
    }

    private static func normalizedDisplayText(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw
            .removingHTMLTags()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "：:"))
        guard !trimmed.isEmpty else { return nil }
        return trimmed.hasPrefix("@") ? trimmed : "@\(trimmed)"
    }

    static func userMID(in rawURL: String?) -> Int? {
        guard let rawURL = rawURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawURL.isEmpty
        else { return nil }

        let normalized = rawURL.normalizedBiliURL()
        if let components = URLComponents(string: normalized) {
            if let queryMID = components.queryItems?.first(where: {
                ["mid", "uid", "vmid"].contains($0.name.lowercased())
            })?.value.flatMap(Int.init) {
                return queryMID
            }

            let host = components.host?.lowercased()
            let pathID = components.path
                .split(separator: "/")
                .compactMap { Int($0) }
                .first
            if host == "space.bilibili.com" || host == "space" {
                return pathID
            }
        }

        let patterns = [
            #"(?i)space\.bilibili\.com/(\d+)"#,
            #"(?i)bilibili://space/(\d+)"#,
            #"(?i)(?:^|[?&])(?:mid|uid|vmid)=(\d+)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
            guard let match = regex.firstMatch(in: normalized, range: range),
                  let matchRange = Range(match.range(at: 1), in: normalized)
            else { continue }
            if let mid = Int(normalized[matchRange]) {
                return mid
            }
        }
        return nil
    }
}

nonisolated enum BiliMentionExtractor {
    static func commentMentions(
        raw: DynamicJSONValue?,
        message _: String?,
        jumpURLs: DynamicJSONValue?
    ) -> [BiliMention] {
        unique(mentions(in: raw, context: .commentRoot) + mentions(in: jumpURLs, context: .jumpURLs))
    }

    static func richTextMention(
        object: [String: DynamicJSONValue],
        type: String?,
        text: String?
    ) -> BiliMention? {
        guard isMentionType(type) else { return nil }
        let url = firstText([
            object["jump_url"],
            object["jumpUrl"],
            object["url"],
            object["uri"],
            object["link"]
        ])
        let mid = firstInt([
            object["rid"],
            object["mid"],
            object["uid"],
            object["user_id"],
            object["user_mid"],
            object["vmid"]
        ]) ?? BiliMention.userMID(in: url)
        let mentionText = firstNonBlankDynamicText([
            text,
            textValue(object["orig_text"]),
            textValue(object["text"]),
            textValue(object["name"]),
            textValue(object["uname"])
        ])
        return BiliMention(text: mentionText, mid: mid, url: url)
    }

    private enum Context {
        case commentRoot
        case jumpURLs
        case memberList
        case nested
    }

    private static func mentions(in value: DynamicJSONValue?, context: Context) -> [BiliMention] {
        guard let value else { return [] }
        switch value {
        case .array(let values):
            return unique(values.flatMap { mentions(in: $0, context: context == .jumpURLs ? .jumpURLs : .memberList) })
        case .object(let object):
            var result = [BiliMention]()
            result.append(contentsOf: mentionsFromNameToMIDMaps(object))

            for (key, child) in object where key.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("@") {
                let url = firstNavigationalText(in: child)
                let mid = firstMID(in: child) ?? BiliMention.userMID(in: url)
                if let mention = BiliMention(text: key, mid: mid, url: url) {
                    result.append(mention)
                }
            }

            if context == .memberList,
               let mention = mentionObject(object) {
                result.append(mention)
            }

            for key in ["members", "member", "at_members", "atMembers", "users", "user", "jump_url", "jump_urls", "jumpURL", "jumpURLs"] {
                guard let child = object[key] else { continue }
                let childContext: Context = key.lowercased().contains("jump") ? .jumpURLs : .memberList
                result.append(contentsOf: mentions(in: child, context: childContext))
            }

            if context == .jumpURLs || context == .nested {
                for child in object.values {
                    result.append(contentsOf: mentions(in: child, context: .nested))
                }
            }

            return unique(result)
        case .string, .number, .bool, .null:
            return []
        }
    }

    private static func mentionsFromNameToMIDMaps(_ object: [String: DynamicJSONValue]) -> [BiliMention] {
        let keys = [
            "at_name_to_mid",
            "atNameToMid",
            "at_name_to_mid_map",
            "atNameToMidMap"
        ]
        return keys.flatMap { key -> [BiliMention] in
            guard case .object(let map)? = object[key] else { return [] }
            return map.compactMap { name, value in
                BiliMention(text: name, mid: intValue(value))
            }
        }
    }

    private static func mentionObject(_ object: [String: DynamicJSONValue]) -> BiliMention? {
        let url = firstText([
            object["jump_url"],
            object["jumpUrl"],
            object["space_url"],
            object["spaceUrl"],
            object["url"],
            object["uri"],
            object["link"]
        ])
        let mid = firstInt([
            object["mid"],
            object["uid"],
            object["user_id"],
            object["user_mid"],
            object["vmid"],
            object["rid"]
        ]) ?? BiliMention.userMID(in: url)
        let text = firstNonBlankDynamicText([
            textValue(object["uname"]),
            textValue(object["name"]),
            textValue(object["nickname"]),
            textValue(object["text"]),
            textValue(object["orig_text"])
        ])

        guard mid != nil || text?.hasPrefix("@") == true || BiliMention.userMID(in: url) != nil else {
            return nil
        }
        return BiliMention(text: text, mid: mid, url: url)
    }

    private static func firstMID(in value: DynamicJSONValue) -> Int? {
        switch value {
        case .object(let object):
            return firstInt([
                object["mid"],
                object["uid"],
                object["user_id"],
                object["user_mid"],
                object["vmid"],
                object["rid"]
            ]) ?? BiliMention.userMID(in: firstNavigationalText(in: value))
        case .array(let values):
            return values.lazy.compactMap(firstMID).first
        case .string(let string), .number(let string):
            return BiliMention.userMID(in: string)
        case .bool, .null:
            return nil
        }
    }

    private static func firstNavigationalText(in value: DynamicJSONValue) -> String? {
        switch value {
        case .string(let string), .number(let string):
            return string
        case .array(let values):
            return values.lazy.compactMap(firstNavigationalText).first
        case .object(let object):
            let preferred = firstText([
                object["jump_url"],
                object["jumpUrl"],
                object["space_url"],
                object["spaceUrl"],
                object["url"],
                object["uri"],
                object["link"],
                object["native_url"],
                object["raw_url"]
            ])
            if let preferred {
                return preferred
            }
            return object.values.lazy.compactMap(firstNavigationalText).first
        case .bool, .null:
            return nil
        }
    }

    private static func firstText(_ values: [DynamicJSONValue?]) -> String? {
        firstNonBlankDynamicText(values.map(textValue))
    }

    private static func firstInt(_ values: [DynamicJSONValue?]) -> Int? {
        values.lazy.compactMap(intValue).first
    }

    private static func textValue(_ value: DynamicJSONValue?) -> String? {
        guard let value else { return nil }
        switch value {
        case .string(let string), .number(let string):
            return string
        case .bool, .array, .object, .null:
            return nil
        }
    }

    private static func intValue(_ value: DynamicJSONValue?) -> Int? {
        guard let value else { return nil }
        switch value {
        case .string(let string), .number(let string):
            return Int(string)
        case .bool(let bool):
            return bool ? 1 : 0
        case .array, .object, .null:
            return nil
        }
    }

    private static func isMentionType(_ type: String?) -> Bool {
        guard let type else { return false }
        return type.uppercased().contains("AT")
    }

    private static func unique(_ mentions: [BiliMention]) -> [BiliMention] {
        var seen = Set<String>()
        var result = [BiliMention]()
        for mention in mentions {
            let key = "\(mention.text)|\(mention.mid.map(String.init) ?? "")|\(mention.url ?? "")"
            guard seen.insert(key).inserted else { continue }
            result.append(mention)
        }
        return result
    }
}

nonisolated enum DynamicTextSegment: Hashable {
    case text(String)
    case emoji(text: String, url: String?)
    case link(title: String, url: String)
    case mention(text: String, mid: Int?, url: String?)

    var displayText: String {
        switch self {
        case .text(let text):
            return text
        case .emoji(let text, _):
            return text
        case .link:
            return "查看链接"
        case .mention(let text, _, _):
            return text
        }
    }

    static func displayText(from segments: [DynamicTextSegment]) -> String? {
        firstNonBlankDynamicText([segments.map(\.displayText).joined()])
    }
}

nonisolated private func firstNonEmptyDynamicSegments(_ values: [[DynamicTextSegment]]) -> [DynamicTextSegment] {
    values.first { segments in
        DynamicTextSegment.displayText(from: segments)?.isEmpty == false
    } ?? []
}

nonisolated private func normalizedDynamicSegments(_ segments: [DynamicTextSegment]) -> [DynamicTextSegment] {
    var result = [DynamicTextSegment]()
    for segment in segments {
        switch segment {
        case .text(let value):
            guard !value.isEmpty else { continue }
            if case .text(let previous) = result.last {
                result.removeLast()
                result.append(.text(previous + value))
            } else {
                result.append(.text(value))
            }
        case .emoji(let text, let url):
            guard !text.isEmpty else { continue }
            result.append(.emoji(text: text, url: url))
        case .link(let title, let url):
            guard !url.isEmpty else { continue }
            result.append(.link(title: title.isEmpty ? "查看链接" : title, url: url))
        case .mention(let text, let mid, let url):
            guard !text.isEmpty else { continue }
            result.append(.mention(text: text, mid: mid, url: url))
        }
    }
    return result
}

nonisolated private func dynamicPlainTextSegments(_ text: String?) -> [DynamicTextSegment] {
    guard let text, !text.isEmpty else { return [] }

    let pattern = #"(?i)(?:https?:)?//[^\s<>"']+"#
    var result = [DynamicTextSegment]()
    var cursor = text.startIndex

    while cursor < text.endIndex,
          let range = text.range(of: pattern, options: .regularExpression, range: cursor..<text.endIndex) {
        if range.lowerBound > cursor {
            result.append(.text(String(text[cursor..<range.lowerBound])))
        }

        let rawURL = String(text[range])
        let trimmed = dynamicURLByTrimmingTrailingPunctuation(rawURL)
        if let url = normalizedOpenDynamicURL(trimmed.url) {
            result.append(.link(title: "查看链接", url: url))
        } else {
            result.append(.text(rawURL))
        }

        if !trimmed.trailing.isEmpty {
            result.append(.text(trimmed.trailing))
        }

        cursor = range.upperBound
    }

    if cursor < text.endIndex {
        result.append(.text(String(text[cursor...])))
    }

    return normalizedDynamicSegments(result)
}

nonisolated private func normalizedOpenDynamicURL(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let normalized = raw
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .normalizedBiliURL()
    guard let components = URLComponents(string: normalized),
          let scheme = components.scheme?.lowercased(),
          (scheme == "http" || scheme == "https"),
          components.host?.isEmpty == false
    else {
        return nil
    }
    return normalized
}

nonisolated private func dynamicURLByTrimmingTrailingPunctuation(_ raw: String) -> (url: String, trailing: String) {
    let punctuation = CharacterSet(charactersIn: ".,，。!！?？;；:：、)]}）】》\"'")
    var url = raw
    var trailing = ""
    while let last = url.last,
          let scalar = String(last).unicodeScalars.first,
          punctuation.contains(scalar) {
        trailing.insert(last, at: trailing.startIndex)
        url.removeLast()
    }
    return (url, trailing)
}

nonisolated private func shouldRenderDynamicLinkNode(type: String?, url: String?) -> Bool {
    let uppercasedType = (type ?? "").uppercased()
    if uppercasedType.contains("AT")
        || uppercasedType.contains("TOPIC")
        || uppercasedType.contains("EMOJI") {
        return false
    }
    if uppercasedType.contains("WEB")
        || uppercasedType.contains("LINK")
        || uppercasedType.contains("URL")
        || uppercasedType.contains("ARTICLE")
        || uppercasedType.contains("GOODS")
        || uppercasedType.contains("VOTE")
        || uppercasedType.contains("LOTTERY") {
        return true
    }
    return normalizedOpenDynamicURL(url) != nil
}

nonisolated private func uniqueDynamicImages(_ groups: [[DynamicImageItem]]) -> [DynamicImageItem] {
    var seen = Set<String>()
    var result = [DynamicImageItem]()
    for item in groups.flatMap({ $0 }) {
        let key = item.normalizedURL ?? item.url
        guard !key.isEmpty, seen.insert(key).inserted else { continue }
        result.append(item)
    }
    return result
}

enum BiliContentFilter {
    nonisolated static let goodsURLPrefix = "https://gaoneng.bilibili.com/tetris"
    nonisolated static let dynamicAdKeywords = [
        "领券",
        "满减",
        "美团",
        "清仓",
        "热卖",
        "闪购",
        "神券",
        "手淘",
        "淘宝",
        "推广",
        "下单",
        "转转",
        "按摩仪",
        "拼多多",
        "优惠券",
        "百亿补贴",
        "长按复制",
        "全网最低",
        "券后价格",
        "手机京东",
        "长按copy",
        "长按Fu制",
        "全网zui低"
    ]

    nonisolated static func isGoodsDynamicAdditionalType(_ type: String?) -> Bool {
        guard let type else { return false }
        return type.uppercased().contains("ADDITIONAL_TYPE_GOODS")
    }

    nonisolated static func isGoodsKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        return normalized.contains("goods")
            || normalized.contains("commodity")
            || normalized.contains("commerce")
            || normalized.contains("shopping")
            || normalized.contains("shop")
            || normalized.contains("mall")
    }

    nonisolated static func isGoodsText(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return normalized.contains(goodsURLPrefix)
            || normalized.contains("additional_type_goods")
            || normalized.contains("desc_type_goods")
            || normalized.contains("goods_cm_control")
            || normalized.contains("goods_item_id")
            || normalized.contains("goods_prefetched_cache")
            || normalized.contains("gaoneng.bilibili.com/tetris")
            || normalized.contains("mall.bilibili.com")
            || normalized.contains("b23.tv/mall")
            || normalized.contains("bilibili.com/mall")
            || normalized.contains("会员购")
            || normalized.contains("小黄车")
            || normalized.contains("small_shop")
    }

    nonisolated static func isDynamicAdCandidateType(_ type: String?) -> Bool {
        guard let type else { return false }
        switch type.uppercased() {
        case "DYNAMIC_TYPE_DRAW", "DYNAMIC_TYPE_WORD", "DYNAMIC_TYPE_ARTICLE":
            return true
        default:
            return false
        }
    }

    nonisolated static func isDynamicAdText(_ text: String?) -> Bool {
        guard let text, !text.isEmpty else { return false }
        return dynamicAdKeywords.contains { keyword in
            text.range(
                of: keyword,
                options: [.caseInsensitive, .widthInsensitive]
            ) != nil
        }
    }
}

nonisolated private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

nonisolated enum DynamicJSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(String)
    case bool(Bool)
    case array([DynamicJSONValue])
    case object([String: DynamicJSONValue])
    case null

    init(from decoder: Decoder) throws {
        if var array = try? decoder.unkeyedContainer() {
            var values = [DynamicJSONValue]()
            while !array.isAtEnd {
                if let value = try? array.decode(DynamicJSONValue.self) {
                    values.append(value)
                } else {
                    _ = try? array.decode(DynamicDiscardedValue.self)
                }
            }
            self = .array(values)
            return
        }

        if let object = try? decoder.container(keyedBy: DynamicCodingKey.self) {
            var values = [String: DynamicJSONValue]()
            for key in object.allKeys {
                values[key.stringValue] = try? object.decode(DynamicJSONValue.self, forKey: key)
            }
            self = .object(values)
            return
        }

        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            self = .null
        } else if let value = try? single.decode(String.self) {
            self = .string(value)
        } else if let value = try? single.decode(Int.self) {
            self = .number(String(value))
        } else if let value = try? single.decode(Double.self) {
            self = .number(String(format: "%.3f", value))
        } else if let value = try? single.decode(Bool.self) {
            self = .bool(value)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .string(let value), .number(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .bool(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .array(let values):
            var container = encoder.unkeyedContainer()
            for value in values {
                try container.encode(value)
            }
        case .object(let object):
            var container = encoder.container(keyedBy: DynamicCodingKey.self)
            for (key, value) in object {
                if let codingKey = DynamicCodingKey(stringValue: key) {
                    try container.encode(value, forKey: codingKey)
                }
            }
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }

    var textValue: String? {
        switch self {
        case .string(let value), .number(let value):
            return value
        case .bool, .array, .object, .null:
            return nil
        }
    }

    var dynamicDisplayText: String? {
        switch self {
        case .string(let value), .number(let value):
            return value
        case .array(let values):
            return joinedDynamicText(values.map(\.dynamicDisplayText))
        case .object(let object):
            if let richText = object["rich_text_nodes"]?.richTextNodesDisplayText {
                return richText
            }
            return firstNonBlankDynamicText([
                object["text"]?.dynamicDisplayText,
                object["orig_text"]?.dynamicDisplayText,
                object["raw_text"]?.dynamicDisplayText,
                object["content"]?.dynamicDisplayText,
                object["summary"]?.dynamicDisplayText,
                object["desc"]?.dynamicDisplayText,
                object["title"]?.dynamicDisplayText
            ])
        case .bool, .null:
            return nil
        }
    }

    var dynamicTextSegments: [DynamicTextSegment] {
        switch self {
        case .string(let value), .number(let value):
            return dynamicPlainTextSegments(value)
        case .array(let values):
            return normalizedDynamicSegments(values.flatMap(\.dynamicTextSegments))
        case .object(let object):
            if let richText = object["rich_text_nodes"]?.richTextNodesSegments, !richText.isEmpty {
                return richText
            }
            return firstNonEmptyDynamicSegments([
                object["text"]?.dynamicTextSegments ?? [],
                object["orig_text"]?.dynamicTextSegments ?? [],
                object["raw_text"]?.dynamicTextSegments ?? [],
                object["content"]?.dynamicTextSegments ?? [],
                object["summary"]?.dynamicTextSegments ?? [],
                object["desc"]?.dynamicTextSegments ?? [],
                object["title"]?.dynamicTextSegments ?? []
            ])
        case .bool, .null:
            return []
        }
    }

    var richTextNodesDisplayText: String? {
        DynamicTextSegment.displayText(from: richTextNodesSegments)
    }

    var richTextNodesSegments: [DynamicTextSegment] {
        switch self {
        case .array(let values):
            return normalizedDynamicSegments(values.flatMap(\.richTextNodeSegments))
        case .object:
            return richTextNodeSegments
        case .string(let value), .number(let value):
            return dynamicPlainTextSegments(value)
        case .bool, .null:
            return []
        }
    }

    var richTextNodeDisplayText: String? {
        DynamicTextSegment.displayText(from: richTextNodeSegments)
    }

    var richTextNodeSegments: [DynamicTextSegment] {
        switch self {
        case .object(let object):
            let type = object["type"]?.textValue
            let emojiObject = object["emoji"]?.objectValue
            let text = firstNonBlankDynamicText([
                object["text"]?.textValue,
                object["orig_text"]?.textValue,
                object["raw_text"]?.textValue,
                emojiObject?["text"]?.textValue
            ])
            let emojiText = firstNonBlankDynamicText([
                emojiObject?["text"]?.textValue,
                object["emoji"]?.textValue,
                text
            ])
            let emojiURL = firstNonBlankDynamicText([
                emojiObject?["icon_url"]?.textValue,
                emojiObject?["url"]?.textValue,
                emojiObject?["gif_url"]?.textValue,
                emojiObject?["image_url"]?.textValue,
                emojiObject?["img_url"]?.textValue,
                emojiObject?["webp_url"]?.textValue,
                object["icon_url"]?.textValue,
                object["emoji_url"]?.textValue
            ])?.normalizedBiliURL()

            if emojiObject != nil || (type ?? "").uppercased().contains("EMOJI") {
                if let emojiText, !emojiText.isEmpty {
                    return [.emoji(text: emojiText, url: emojiURL)]
                }
            }

            if let mention = BiliMentionExtractor.richTextMention(object: object, type: type, text: text) {
                return [.mention(text: mention.text, mid: mention.mid, url: mention.url)]
            }

            let linkCandidate = firstNonBlankDynamicText([
                object["jump_url"]?.textValue,
                object["url"]?.textValue,
                object["uri"]?.textValue,
                object["link"]?.textValue
            ])
            if shouldRenderDynamicLinkNode(type: type, url: linkCandidate),
               let url = normalizedOpenDynamicURL(linkCandidate ?? text) {
                return [.link(title: "查看链接", url: url)]
            }

            return dynamicPlainTextSegments(text)
        case .string(let value), .number(let value):
            return dynamicPlainTextSegments(value)
        case .array, .bool, .null:
            return []
        }
    }

    var dynamicImageItems: [DynamicImageItem] {
        switch self {
        case .array(let values):
            return values.flatMap(\.dynamicImageItems)
        case .object(let object):
            var groups = [[DynamicImageItem]]()
            if let image = imageItem(from: object) {
                groups.append([image])
            }
            for key in ["pics", "images", "items", "covers"] {
                groups.append(object[key]?.dynamicImageItems ?? [])
            }
            return uniqueDynamicImages(groups)
        case .string, .number, .bool, .null:
            return []
        }
    }

    var dynamicMajorFallbackDisplayText: String? {
        switch self {
        case .object(let object):
            return firstNonBlankDynamicText([
                object["common"]?.dynamicDisplayText,
                object["article"]?.dynamicDisplayText,
                object["pgc"]?.dynamicDisplayText,
                object["courses"]?.dynamicDisplayText,
                object["music"]?.dynamicDisplayText,
                object["medialist"]?.dynamicDisplayText,
                object["ugc_season"]?.dynamicDisplayText
            ])
        case .array(let values):
            return firstNonBlankDynamicText(values.map(\.dynamicMajorFallbackDisplayText))
        case .string, .number, .bool, .null:
            return nil
        }
    }

    var dynamicMajorFallbackTextSegments: [DynamicTextSegment] {
        switch self {
        case .object(let object):
            return firstNonEmptyDynamicSegments([
                object["common"]?.dynamicTextSegments ?? [],
                object["article"]?.dynamicTextSegments ?? [],
                object["pgc"]?.dynamicTextSegments ?? [],
                object["courses"]?.dynamicTextSegments ?? [],
                object["music"]?.dynamicTextSegments ?? [],
                object["medialist"]?.dynamicTextSegments ?? [],
                object["ugc_season"]?.dynamicTextSegments ?? []
            ])
        case .array(let values):
            return firstNonEmptyDynamicSegments(values.map(\.dynamicMajorFallbackTextSegments))
        case .string, .number, .bool, .null:
            return []
        }
    }

    var dynamicMajorFallbackImageItems: [DynamicImageItem] {
        switch self {
        case .object(let object):
            return uniqueDynamicImages([
                object["common"]?.dynamicImageItems ?? [],
                object["article"]?.dynamicImageItems ?? [],
                object["pgc"]?.dynamicImageItems ?? [],
                object["courses"]?.dynamicImageItems ?? [],
                object["music"]?.dynamicImageItems ?? [],
                object["medialist"]?.dynamicImageItems ?? [],
                object["ugc_season"]?.dynamicImageItems ?? []
            ])
        case .array(let values):
            return uniqueDynamicImages(values.map(\.dynamicMajorFallbackImageItems))
        case .string, .number, .bool, .null:
            return []
        }
    }

    var dynamicMajorFallbackArchive: DynamicArchive? {
        switch self {
        case .object(let object):
            for key in ["common", "ugc_season", "medialist", "archive", "video"] {
                if let archive = object[key]?.dynamicVideoArchiveCandidate {
                    return archive
                }
            }
            return dynamicVideoArchiveCandidate
        case .array(let values):
            return values.lazy.compactMap(\.dynamicMajorFallbackArchive).first
        case .string, .number, .bool, .null:
            return nil
        }
    }

    var dynamicMajorFallbackLive: DynamicLive? {
        switch self {
        case .object(let object):
            for key in ["live", "live_rcmd", "common", "additional"] {
                guard let data = try? JSONEncoder().encode(object[key]) else { continue }
                if let live = try? JSONDecoder().decode(DynamicLive.self, from: data),
                   live.hasLiveIdentity {
                    return live
                }
            }
            return nil
        case .array(let values):
            return values.lazy.compactMap(\.dynamicMajorFallbackLive).first
        case .string, .number, .bool, .null:
            return nil
        }
    }

    var containsGoodsMetadata: Bool {
        switch self {
        case .string(let value), .number(let value):
            return BiliContentFilter.isGoodsText(value)
        case .bool, .null:
            return false
        case .array(let values):
            return values.contains(where: \.containsGoodsMetadata)
        case .object(let object):
            for (key, value) in object {
                if BiliContentFilter.isGoodsKey(key), !value.isEmptyMetadataValue {
                    return true
                }
                if BiliContentFilter.isGoodsText(key) || value.containsGoodsMetadata {
                    return true
                }
            }
            return false
        }
    }

    var accountVideoEntries: [AccountVideoEntry] {
        switch self {
        case .array(let values):
            return values.compactMap(\.accountVideoEntry)
        case .object(let object):
            for key in ["list", "medias", "items", "archives"] {
                let entries = object[key]?.accountVideoEntries ?? []
                if !entries.isEmpty {
                    return entries
                }
            }
            if let entry = accountVideoEntry {
                return [entry]
            }
            return []
        case .string, .number, .bool, .null:
            return []
        }
    }

    var intValueForDynamicParsing: Int? {
        intValue
    }

    var textValueForDynamicParsing: String? {
        textValue
    }

    var objectValueForDynamicParsing: [String: DynamicJSONValue]? {
        objectValue
    }

    private var dynamicVideoArchiveCandidate: DynamicArchive? {
        guard case .object(let object) = self else { return nil }
        return DynamicArchive(fallbackObject: object)
    }

    private var accountVideoEntry: AccountVideoEntry? {
        guard case .object(let object) = self else { return nil }
        let history = object["history"]?.objectValue
        let upper = object["upper"]?.objectValue
        let ownerObject = object["owner"]?.objectValue
        let statObject = object["stat"]?.objectValue ?? object["cnt_info"]?.objectValue
        let routeURL = firstNonBlankDynamicText([
            object["uri"]?.textValue,
            object["url"]?.textValue,
            object["link"]?.textValue
        ])
        let historyBusiness = history?["business"]?.textValue?.lowercased()
        let isPGCHistory = historyBusiness?.contains("pgc") == true
        let routePGCEpisodeID = Self.pgcID(from: routeURL, prefix: "ep")
        let rawPGCEpisodeID = Self.positiveID(history?["epid"]?.intValue)
            ?? Self.positiveID(history?["ep_id"]?.intValue)
            ?? Self.positiveID(object["epid"]?.intValue)
            ?? Self.positiveID(object["ep_id"]?.intValue)
            ?? (isPGCHistory ? Self.positiveID(history?["oid"]?.intValue) : nil)
        let isPGC = routePGCEpisodeID != nil
            || rawPGCEpisodeID != nil
            || isPGCHistory
            || routeURL?.contains("/bangumi/play/") == true
        let pgcEpisodeID = isPGC
            ? routePGCEpisodeID ?? rawPGCEpisodeID
            : nil
        let pgcSeasonID = isPGC
            ? Self.positiveID(object["season_id"]?.intValue)
                ?? Self.positiveID(history?["season_id"]?.intValue)
                ?? Self.pgcID(from: routeURL, prefix: "ss")
            : nil

        let routeBVID = firstNonBlankDynamicText([
            object["bvid"]?.textValue,
            history?["bvid"]?.textValue,
            object["bvid_str"]?.textValue
        ]) ?? Self.bvid(from: routeURL)
        let bvid = routeBVID
            ?? pgcEpisodeID.map { "ep\($0)" }
            ?? pgcSeasonID.map { "ss\($0)" }
        guard let bvid, !bvid.isEmpty else { return nil }

        let aid = object["aid"]?.intValue
            ?? history?["aid"]?.intValue
            ?? (!isPGC ? object["id"]?.intValue : nil)
            ?? (!isPGC ? object["rid"]?.intValue : nil)
            ?? (!isPGC ? history?["oid"]?.intValue : nil)
        let title = firstNonBlankDynamicText([
            object["title"]?.textValue,
            object["long_title"]?.textValue,
            object["name"]?.textValue
        ]) ?? "未命名视频"
        let pic = firstNonBlankDynamicText([
            object["pic"]?.textValue,
            object["cover"]?.textValue,
            object["cover_url"]?.textValue,
            object["thumbnail"]?.textValue
        ])?.normalizedBiliURL()
        let duration = object["duration"]?.intValue
        let cid = object["cid"]?.intValue ?? history?["cid"]?.intValue
        let ownerMID = upper?["mid"]?.intValue
            ?? ownerObject?["mid"]?.intValue
            ?? object["author_mid"]?.intValue
            ?? object["mid"]?.intValue
        let ownerName = firstNonBlankDynamicText([
            upper?["name"]?.textValue,
            ownerObject?["name"]?.textValue,
            object["author_name"]?.textValue,
            object["author"]?.textValue,
            object["owner_name"]?.textValue
        ])
        let ownerFace = firstNonBlankDynamicText([
            upper?["face"]?.textValue,
            ownerObject?["face"]?.textValue,
            object["author_face"]?.textValue,
            object["owner_face"]?.textValue
        ])?.normalizedBiliURL()
        let owner = (ownerMID != nil || ownerName != nil || ownerFace != nil)
            ? VideoOwner(mid: ownerMID ?? 0, name: ownerName ?? "", face: ownerFace)
            : nil
        let stat = VideoStat(
            view: statObject?["play"]?.intValue ?? statObject?["view"]?.intValue,
            reply: statObject?["reply"]?.intValue,
            like: statObject?["like"]?.intValue,
            coin: statObject?["coin"]?.intValue,
            favorite: statObject?["collect"]?.intValue ?? statObject?["favorite"]?.intValue
        )
        let timestamp = object["view_at"]?.doubleValue
            ?? object["fav_time"]?.doubleValue
            ?? object["add_at"]?.doubleValue
            ?? object["mtime"]?.doubleValue
            ?? object["ctime"]?.doubleValue
        let progress = object["progress"]?.doubleValue
        let playbackTime = progress.map { $0 < 0 ? TimeInterval(duration ?? 0) : TimeInterval($0) }

        return AccountVideoEntry(
            bvid: bvid,
            aid: aid,
            title: title,
            pic: pic,
            duration: duration,
            owner: owner,
            stat: stat,
            cid: cid,
            savedAt: timestamp.map { Date(timeIntervalSince1970: $0) } ?? Date(),
            playbackTime: playbackTime,
            playbackDuration: duration.map(TimeInterval.init),
            pgcSeasonID: pgcSeasonID,
            pgcEpisodeID: pgcEpisodeID
        )
    }

    private func imageItem(from object: [String: DynamicJSONValue]) -> DynamicImageItem? {
        let url = firstNonBlankDynamicText([
            object["src"]?.textValue,
            object["url"]?.textValue,
            object["img_src"]?.textValue,
            object["raw_url"]?.textValue,
            object["image_url"]?.textValue,
            object["cover"]?.textValue,
            object["cover_url"]?.textValue,
            object["pic"]?.textValue,
            object["thumb"]?.textValue,
            object["thumbnail"]?.textValue,
            object["gif_url"]?.textValue,
            object["gifUrl"]?.textValue,
            object["animated_url"]?.textValue,
            object["animatedUrl"]?.textValue
        ])
        guard let url, !url.isEmpty else { return nil }
        let livePhotoValue = object["live_photo"] ?? object["livePhoto"]
        let livePhotoFlag: String? = {
            if dynamicTruthy(object["is_live_photo"]) || dynamicTruthy(object["isLivePhoto"]) {
                return "live-photo"
            }
            guard let value = livePhotoValue else { return nil }
            if dynamicTruthy(value) { return "live-photo" }
            return value.textValue
        }()
        let livePhotoObjectURL: String? = {
            guard case .object(let values) = livePhotoValue else { return nil }
            return firstNonBlankDynamicText([
                values["video_url"]?.textValue,
                values["video_src"]?.textValue,
                values["live_video_url"]?.textValue,
                values["liveVideoUrl"]?.textValue,
                values["videoUrl"]?.textValue,
                values["url"]?.textValue,
                values["src"]?.textValue
            ])
        }()
        return DynamicImageItem(
            url: url,
            width: firstDynamicInt([
                object["width"],
                object["img_width"],
                object["image_width"],
                object["w"]
            ]),
            height: firstDynamicInt([
                object["height"],
                object["img_height"],
                object["image_height"],
                object["h"]
            ]),
            size: firstDynamicDouble([
                object["size"],
                object["img_size"],
                object["image_size"]
            ]),
            mediaType: firstNonBlankDynamicText([
                object["media_type"]?.textValue,
                object["mediaType"]?.textValue,
                object["mime_type"]?.textValue,
                object["mimeType"]?.textValue,
                object["image_type"]?.textValue,
                object["imageType"]?.textValue,
                object["img_type"]?.textValue,
                object["picture_type"]?.textValue,
                object["type"]?.textValue,
                object["format"]?.textValue,
                livePhotoFlag
            ]),
            isLivePhoto: dynamicTruthy(object["is_live_photo"])
                || dynamicTruthy(object["isLivePhoto"])
                || dynamicTruthy(livePhotoValue),
            liveVideoURL: firstNonBlankDynamicText([
                object["live_video_url"]?.textValue,
                object["liveVideoUrl"]?.textValue,
                object["video_url"]?.textValue,
                object["videoUrl"]?.textValue,
                object["video_src"]?.textValue,
                object["videoSrc"]?.textValue,
                object["live_url"]?.textValue,
                object["liveUrl"]?.textValue,
                livePhotoObjectURL
            ]),
            isAnimatedGIF: dynamicTruthy(object["is_gif"]) || dynamicTruthy(object["isGif"]),
            animatedImageURL: firstNonBlankDynamicText([
                object["gif_url"]?.textValue,
                object["gifUrl"]?.textValue,
                object["animated_url"]?.textValue,
                object["animatedUrl"]?.textValue
            ])
        )
    }

    private func dynamicTruthy(_ value: DynamicJSONValue?) -> Bool {
        switch value {
        case .bool(let value):
            return value
        case .number(let value), .string(let value):
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return ["1", "true", "yes", "on", "live", "live-photo", "livephoto"].contains(normalized)
        default:
            return false
        }
    }

    private func firstDynamicInt(_ values: [DynamicJSONValue?]) -> Int? {
        values.lazy.compactMap(\.?.intValue).first
    }

    private func firstDynamicDouble(_ values: [DynamicJSONValue?]) -> Double? {
        values.lazy.compactMap(\.?.doubleValue).first
    }

    private var intValue: Int? {
        switch self {
        case .number(let value), .string(let value):
            return Int(value)
        case .bool(let value):
            return value ? 1 : 0
        case .array, .object, .null:
            return nil
        }
    }

    private var doubleValue: Double? {
        switch self {
        case .number(let value), .string(let value):
            return Double(value)
        case .bool, .array, .object, .null:
            return nil
        }
    }

    private var objectValue: [String: DynamicJSONValue]? {
        if case .object(let object) = self {
            return object
        }
        return nil
    }

    private var isEmptyMetadataValue: Bool {
        switch self {
        case .null:
            return true
        case .string(let value), .number(let value):
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .bool:
            return false
        case .array(let values):
            return values.isEmpty
        case .object(let object):
            return object.isEmpty
        }
    }

    private static func bvid(from text: String?) -> String? {
        guard let text else { return nil }
        guard let range = text.range(of: #"BV[A-Za-z0-9]{10,}"#, options: .regularExpression) else { return nil }
        return String(text[range])
    }

    private static func pgcID(from text: String?, prefix: String) -> Int? {
        guard let text,
              let range = text.range(of: "\(prefix)/?[0-9]+", options: .regularExpression)
        else { return nil }
        let digits = String(text[range].filter(\.isNumber))
        return positiveID(Int(digits))
    }

    private static func positiveID(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
    }
}

nonisolated private struct DynamicDiscardedValue: Decodable {}

nonisolated struct DynamicFeedData: Decodable, Hashable {
    let items: [DynamicFeedItem]?
    let hasMore: Bool?
    let offset: String?

    enum CodingKeys: String, CodingKey {
        case items, offset
        case hasMore = "has_more"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([DynamicFeedItem].self, forKey: .items)
        hasMore = container.decodeLossyBoolIfPresent(forKey: .hasMore)
        offset = container.decodeLossyStringIfPresent(forKey: .offset)
    }
}

nonisolated struct DynamicDetailData: Decodable, Hashable {
    let item: DynamicFeedItem?
}

nonisolated struct DynamicPortalData: Decodable, Hashable {
    let liveUsers: DynamicPortalLiveUsers?
    let upList: DynamicPortalUpList?

    enum CodingKeys: String, CodingKey {
        case liveUsers = "live_users"
        case upList = "up_list"
    }
}

nonisolated struct DynamicPortalLiveUsers: Decodable, Hashable {
    let count: Int?
    let items: [DynamicPortalLiveUser]

    enum CodingKeys: String, CodingKey {
        case count, items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        count = container.decodeLossyIntIfPresent(forKey: .count)
        items = try container.decodeIfPresent([DynamicPortalLiveUser].self, forKey: .items) ?? []
    }
}

nonisolated struct DynamicPortalUpList: Decodable, Hashable {
    let items: [DynamicPortalUpItem]
    let hasMore: Bool?
    let offset: String?

    enum CodingKeys: String, CodingKey {
        case items, offset
        case hasMore = "has_more"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([DynamicPortalUpItem].self, forKey: .items) ?? []
        hasMore = container.decodeLossyBoolIfPresent(forKey: .hasMore)
        offset = container.decodeLossyStringIfPresent(forKey: .offset)
    }
}

nonisolated struct DynamicPortalUpItem: Decodable, Hashable {
    let mid: Int
    let uname: String
    let face: String?
    let hasUpdate: Bool?

    enum CodingKeys: String, CodingKey {
        case mid, uname, name, face
        case hasUpdate = "has_update"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mid = container.decodeLossyIntIfPresent(forKey: .mid) ?? 0
        uname = container.decodeLossyStringIfPresent(forKey: .uname)
            ?? container.decodeLossyStringIfPresent(forKey: .name)
            ?? ""
        face = container.decodeLossyStringIfPresent(forKey: .face)?.normalizedBiliURL()
        hasUpdate = container.decodeLossyBoolIfPresent(forKey: .hasUpdate)
    }

    var owner: VideoOwner {
        VideoOwner(mid: mid, name: uname, face: face)
    }
}

nonisolated struct DynamicPortalLiveUser: Decodable, Hashable {
    let mid: Int
    let uname: String
    let face: String?
    let roomID: Int?
    let title: String?

    enum CodingKeys: String, CodingKey {
        case mid, uname, name, face, title
        case roomID = "room_id"
        case roomIDAlt = "roomid"
        case roomIDCamel = "roomId"
        case jumpURL = "jump_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mid = container.decodeLossyIntIfPresent(forKey: .mid) ?? 0
        uname = container.decodeLossyStringIfPresent(forKey: .uname)
            ?? container.decodeLossyStringIfPresent(forKey: .name)
            ?? ""
        face = container.decodeLossyStringIfPresent(forKey: .face)?.normalizedBiliURL()
        title = container.decodeLossyStringIfPresent(forKey: .title)
        roomID = container.decodeLossyIntIfPresent(forKey: .roomID)
            ?? container.decodeLossyIntIfPresent(forKey: .roomIDAlt)
            ?? container.decodeLossyIntIfPresent(forKey: .roomIDCamel)
            ?? Self.roomID(from: container.decodeLossyStringIfPresent(forKey: .jumpURL))
    }

    var owner: VideoOwner {
        VideoOwner(mid: mid, name: uname, face: face)
    }

    var liveRoom: LiveRoom? {
        guard let roomID, roomID > 0 else { return nil }
        let roomTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return LiveRoom(
            roomID: roomID,
            title: roomTitle.isEmpty ? uname : roomTitle,
            uname: uname,
            uid: mid > 0 ? mid : nil,
            face: face,
            cover: nil,
            keyframe: nil,
            online: nil,
            areaName: nil,
            parentAreaName: nil,
            liveStatus: 1
        )
    }

    private static func roomID(from text: String?) -> Int? {
        guard let text else { return nil }
        guard let range = text.range(of: #"\d+"#, options: .regularExpression) else { return nil }
        return Int(text[range])
    }
}

nonisolated struct DynamicFeedItem: Identifiable, Decodable, Hashable {
    nonisolated var id: String { idStr }

    let idStr: String
    let type: String?
    let basic: DynamicBasic?
    let modules: DynamicModules?
    let original: DynamicOriginalItem?

    var author: DynamicAuthor? {
        modules?.moduleAuthor
    }

    var displayText: String? {
        firstNonBlankDynamicText([
            modules?.moduleDynamic?.desc?.displayText,
            modules?.moduleDynamic?.major?.displayText
        ])
    }

    var textSegments: [DynamicTextSegment] {
        firstNonEmptyDynamicSegments([
            modules?.moduleDynamic?.desc?.segments ?? [],
            modules?.moduleDynamic?.major?.segments ?? []
        ])
    }

    var archive: DynamicArchive? {
        modules?.moduleDynamic?.major?.resolvedArchive
    }

    var live: DynamicLive? {
        modules?.moduleDynamic?.major?.live
    }

    var paidContent: DynamicPaidContent? {
        modules?.moduleDynamic?.paidContent
    }

    var imageItems: [DynamicImageItem] {
        uniqueDynamicImages([
            modules?.moduleDynamic?.major?.imageItems ?? [],
            modules?.moduleDynamic?.desc?.imageItems ?? []
        ])
    }

    var isForward: Bool {
        type == "DYNAMIC_TYPE_FORWARD"
    }

    var containsGoodsPromotion: Bool {
        modules?.moduleDynamic?.containsGoodsPromotion == true
            || original?.containsGoodsPromotion == true
    }

    var containsDynamicAdPromotion: Bool {
        (BiliContentFilter.isDynamicAdCandidateType(type)
            && modules?.moduleDynamic?.containsDynamicAdPromotion == true)
            || original?.containsDynamicAdPromotion == true
    }

    var replyCount: Int? {
        modules?.moduleStat?.comment?.count
            ?? modules?.moduleStat?.reply?.count
            ?? modules?.moduleStat?.comments?.count
    }

    var repostCount: Int? {
        modules?.moduleStat?.forward?.count
            ?? modules?.moduleStat?.repost?.count
    }

    var likeCount: Int? {
        modules?.moduleStat?.like?.count
    }

    var isLiked: Bool {
        modules?.moduleStat?.like?.status == true
    }

    var commentOID: String? {
        firstNonBlankDynamicText([
            basic?.commentIDStr,
            basic?.ridStr,
            idStr
        ])
    }

    var commentType: Int? {
        basic?.commentType
    }

    var contentDiagnosticSummary: String {
        let majorKeys = modules?.moduleDynamic?.major?.diagnosticKeys.joined(separator: ",") ?? "-"
        let additional = modules?.moduleDynamic?.additional
        let additionalKeys = additional?.diagnosticKeys.joined(separator: ",") ?? "-"
        return "id=\(idStr) type=\(type ?? "-") major=[\(majorKeys)] additionalType=\(additional?.type ?? "-") additional=[\(additionalKeys)] originalType=\(original?.type ?? "-")"
    }

    enum CodingKeys: String, CodingKey {
        case idStr = "id_str"
        case idValue = "id"
        case type, basic, modules
        case original = "orig"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        idStr = container.decodeLossyStringIfPresent(forKey: .idStr)
            ?? container.decodeLossyStringIfPresent(forKey: .idValue)
            ?? UUID().uuidString
        type = try container.decodeIfPresent(String.self, forKey: .type)
        basic = try? container.decodeIfPresent(DynamicBasic.self, forKey: .basic)
        modules = try container.decodeIfPresent(DynamicModules.self, forKey: .modules)
        original = try? container.decodeIfPresent(DynamicOriginalItem.self, forKey: .original)
    }
}

nonisolated struct DynamicBasic: Decodable, Hashable {
    let commentIDStr: String?
    let commentType: Int?
    let ridStr: String?

    enum CodingKeys: String, CodingKey {
        case commentIDStr = "comment_id_str"
        case commentType = "comment_type"
        case ridStr = "rid_str"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        commentIDStr = container.decodeLossyStringIfPresent(forKey: .commentIDStr)
        commentType = container.decodeLossyIntIfPresent(forKey: .commentType)
        ridStr = container.decodeLossyStringIfPresent(forKey: .ridStr)
    }
}

nonisolated struct DynamicOriginalItem: Identifiable, Decodable, Hashable {
    var id: String { idStr }

    let idStr: String
    let type: String?
    let modules: DynamicModules?
    let visible: Bool?

    var author: DynamicAuthor? {
        modules?.moduleAuthor
    }

    var displayText: String? {
        firstNonBlankDynamicText([
            modules?.moduleDynamic?.desc?.displayText,
            modules?.moduleDynamic?.major?.displayText
        ])
    }

    var textSegments: [DynamicTextSegment] {
        firstNonEmptyDynamicSegments([
            modules?.moduleDynamic?.desc?.segments ?? [],
            modules?.moduleDynamic?.major?.segments ?? []
        ])
    }

    var archive: DynamicArchive? {
        modules?.moduleDynamic?.major?.resolvedArchive
    }

    var live: DynamicLive? {
        modules?.moduleDynamic?.major?.live
    }

    var paidContent: DynamicPaidContent? {
        modules?.moduleDynamic?.paidContent
    }

    var imageItems: [DynamicImageItem] {
        uniqueDynamicImages([
            modules?.moduleDynamic?.major?.imageItems ?? [],
            modules?.moduleDynamic?.desc?.imageItems ?? []
        ])
    }

    var hasDisplayableContent: Bool {
        displayText?.isEmpty == false
            || DynamicTextSegment.displayText(from: textSegments)?.isEmpty == false
            || archive != nil
            || live != nil
            || paidContent != nil
            || !imageItems.isEmpty
    }

    var containsGoodsPromotion: Bool {
        modules?.moduleDynamic?.containsGoodsPromotion == true
    }

    var containsDynamicAdPromotion: Bool {
        BiliContentFilter.isDynamicAdCandidateType(type)
            && modules?.moduleDynamic?.containsDynamicAdPromotion == true
    }

    enum CodingKeys: String, CodingKey {
        case idStr = "id_str"
        case idValue = "id"
        case type, modules, visible
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        idStr = container.decodeLossyStringIfPresent(forKey: .idStr)
            ?? container.decodeLossyStringIfPresent(forKey: .idValue)
            ?? UUID().uuidString
        type = try container.decodeIfPresent(String.self, forKey: .type)
        modules = try container.decodeIfPresent(DynamicModules.self, forKey: .modules)
        visible = container.decodeLossyBoolIfPresent(forKey: .visible)
    }
}

nonisolated extension DynamicFeedItem {
    func matchesBlockedDynamicKeywords(_ keywords: [String]) -> Bool {
        let normalizedKeywords = keywords.compactMap(Self.normalizedBlockedDynamicKeyword)
        guard !normalizedKeywords.isEmpty else { return false }

        let searchText = keywordFilterTextSources.joined(separator: "\n")
        guard !searchText.isEmpty else { return false }
        return normalizedKeywords.contains { keyword in
            searchText.range(
                of: keyword,
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
            ) != nil
        }
    }

    fileprivate var keywordFilterTextSources: [String] {
        compactNonBlankDynamicFilterTexts([
            displayText,
            DynamicTextSegment.displayText(from: textSegments),
            archive?.title,
            archive?.desc,
            live?.displayTitle,
            paidContent?.title,
            paidContent?.subtitle
        ]) + (original?.keywordFilterTextSources ?? [])
    }

    private static func normalizedBlockedDynamicKeyword(_ keyword: String) -> String? {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

nonisolated extension DynamicOriginalItem {
    fileprivate var keywordFilterTextSources: [String] {
        compactNonBlankDynamicFilterTexts([
            displayText,
            DynamicTextSegment.displayText(from: textSegments),
            archive?.title,
            archive?.desc,
            live?.displayTitle,
            paidContent?.title,
            paidContent?.subtitle
        ])
    }
}

nonisolated private func compactNonBlankDynamicFilterTexts(_ values: [String?]) -> [String] {
    values.compactMap { value in
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

nonisolated struct DynamicModules: Decodable, Hashable {
    let moduleAuthor: DynamicAuthor?
    let moduleDynamic: DynamicModuleDynamic?
    let moduleStat: DynamicModuleStat?

    enum CodingKeys: String, CodingKey {
        case moduleAuthor = "module_author"
        case moduleDynamic = "module_dynamic"
        case moduleStat = "module_stat"
    }
}

nonisolated struct DynamicAuthor: Decodable, Hashable {
    let mid: Int?
    let name: String?
    let face: String?
    let pubTime: String?
    let pubTS: Int?

    enum CodingKeys: String, CodingKey {
        case mid, name, face
        case pubTime = "pub_time"
        case pubTS = "pub_ts"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mid = container.decodeLossyIntIfPresent(forKey: .mid)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        face = try container.decodeIfPresent(String.self, forKey: .face)
        pubTime = try container.decodeIfPresent(String.self, forKey: .pubTime)
        pubTS = container.decodeLossyIntIfPresent(forKey: .pubTS)
    }

    var owner: VideoOwner {
        VideoOwner(mid: mid ?? 0, name: name ?? "", face: face)
    }
}

nonisolated struct DynamicModuleDynamic: Decodable, Hashable {
    let desc: DynamicText?
    let major: DynamicMajor?
    let additional: DynamicAdditional?

    enum CodingKeys: String, CodingKey {
        case desc, major, additional
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        desc = try? container.decodeIfPresent(DynamicText.self, forKey: .desc)
        major = try? container.decodeIfPresent(DynamicMajor.self, forKey: .major)
        additional = try? container.decodeIfPresent(DynamicAdditional.self, forKey: .additional)
    }

    var paidContent: DynamicPaidContent? {
        major?.paidContent ?? additional?.paidContent
    }

    var containsGoodsPromotion: Bool {
        additional?.containsGoodsPromotion == true
            || desc?.containsGoodsPromotion == true
            || major?.containsGoodsPromotion == true
    }

    var containsDynamicAdPromotion: Bool {
        desc?.containsDynamicAdPromotion == true
            || major?.containsDynamicAdPromotion == true
    }
}

nonisolated struct DynamicText: Decodable, Hashable {
    let text: String?
    let segments: [DynamicTextSegment]
    let imageItems: [DynamicImageItem]
    let containsGoodsPromotion: Bool

    var displayText: String? {
        firstNonBlankDynamicText([
            DynamicTextSegment.displayText(from: segments),
            text
        ])
    }

    enum CodingKeys: String, CodingKey {
        case text, content
        case rawText = "raw_text"
        case origText = "orig_text"
        case richTextNodes = "rich_text_nodes"
    }

    init(from decoder: Decoder) throws {
        let raw = try DynamicJSONValue(from: decoder)
        text = raw.dynamicDisplayText
        segments = raw.dynamicTextSegments
        imageItems = raw.dynamicImageItems
        containsGoodsPromotion = raw.containsGoodsMetadata
    }

    var containsDynamicAdPromotion: Bool {
        BiliContentFilter.isDynamicAdText(displayText)
    }
}

nonisolated struct DynamicAdditional: Decodable, Hashable {
    let type: String?
    let raw: DynamicJSONValue

    enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: Decoder) throws {
        raw = try DynamicJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = container.decodeLossyStringIfPresent(forKey: .type)
    }

    var containsGoodsPromotion: Bool {
        BiliContentFilter.isGoodsDynamicAdditionalType(type)
            || raw.containsGoodsMetadata
    }

    var paidContent: DynamicPaidContent? {
        DynamicPaidContent(raw: raw, sourceKey: type, preferredKind: nil)
    }

    var diagnosticKeys: [String] {
        raw.objectValueForDynamicParsing?.keys.sorted() ?? []
    }
}

nonisolated struct DynamicRichTextNode: Decodable, Hashable {
    let text: String?
    let origText: String?
    let emoji: DynamicRichTextEmoji?

    enum CodingKeys: String, CodingKey {
        case text, emoji
        case origText = "orig_text"
    }

    var displayText: String {
        firstNonBlankDynamicText([text, origText, emoji?.text]) ?? ""
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = container.decodeLossyStringIfPresent(forKey: .text)
        origText = container.decodeLossyStringIfPresent(forKey: .origText)
        emoji = try? container.decodeIfPresent(DynamicRichTextEmoji.self, forKey: .emoji)
    }
}

nonisolated struct DynamicRichTextEmoji: Decodable, Hashable {
    let text: String?

    enum CodingKeys: String, CodingKey {
        case text
    }

    init(from decoder: Decoder) throws {
        if let value = try? decoder.singleValueContainer().decode(String.self) {
            text = value
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = container.decodeLossyStringIfPresent(forKey: .text)
    }
}

nonisolated struct DynamicMajor: Decodable, Hashable {
    let archive: DynamicArchive?
    let opus: DynamicOpus?
    let draw: DynamicDraw?
    let live: DynamicLive?
    let paidContent: DynamicPaidContent?
    private let fallbackArchive: DynamicArchive?
    let fallbackDisplayText: String?
    let fallbackSegments: [DynamicTextSegment]
    let fallbackImageItems: [DynamicImageItem]
    let diagnosticKeys: [String]

    var resolvedArchive: DynamicArchive? {
        if let archive, archive.bvid?.isEmpty == false {
            return archive
        }
        return fallbackArchive ?? archive
    }

    var displayText: String? {
        firstNonBlankDynamicText([
            draw?.displayText,
            opus?.displayText,
            fallbackDisplayText
        ])
    }

    var segments: [DynamicTextSegment] {
        firstNonEmptyDynamicSegments([
            draw?.segments ?? [],
            opus?.segments ?? [],
            fallbackSegments
        ])
    }

    var imageItems: [DynamicImageItem] {
        uniqueDynamicImages([
            draw?.items ?? [],
            opus?.pics ?? [],
            fallbackImageItems
        ])
    }

    var containsGoodsPromotion: Bool {
        draw?.containsGoodsPromotion == true
            || opus?.containsGoodsPromotion == true
    }

    var containsDynamicAdPromotion: Bool {
        draw?.containsDynamicAdPromotion == true
            || opus?.containsDynamicAdPromotion == true
            || BiliContentFilter.isDynamicAdText(fallbackDisplayText)
            || BiliContentFilter.isDynamicAdText(DynamicTextSegment.displayText(from: fallbackSegments))
    }

    enum CodingKeys: String, CodingKey {
        case archive, opus, draw, live
        case liveRcmd = "live_rcmd"
        case common
    }

    init(from decoder: Decoder) throws {
        let raw = try DynamicJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        archive = try? container.decodeIfPresent(DynamicArchive.self, forKey: .archive)
        opus = try? container.decodeIfPresent(DynamicOpus.self, forKey: .opus)
        draw = try? container.decodeIfPresent(DynamicDraw.self, forKey: .draw)
        live = (try? container.decodeIfPresent(DynamicLive.self, forKey: .live))
            ?? (try? container.decodeIfPresent(DynamicLive.self, forKey: .liveRcmd))
            ?? (try? container.decodeIfPresent(DynamicLive.self, forKey: .common))
            ?? raw.dynamicMajorFallbackLive
        paidContent = DynamicPaidContent(raw: raw, sourceKey: nil, preferredKind: nil)
        fallbackArchive = raw.dynamicMajorFallbackArchive
        fallbackDisplayText = raw.dynamicMajorFallbackDisplayText
        fallbackSegments = raw.dynamicMajorFallbackTextSegments
        fallbackImageItems = raw.dynamicMajorFallbackImageItems
        diagnosticKeys = raw.objectValueForDynamicParsing?.keys.sorted() ?? []
    }
}

nonisolated struct DynamicPaidContent: Hashable {
    enum Kind: String, Hashable {
        case video
        case article
        case course
        case collection
        case unknown
    }

    let kind: Kind
    let title: String
    let subtitle: String?
    let cover: String?
    let jumpURL: String?
    let bvid: String?
    let aid: Int?
    let cvid: Int?
    let badgeText: String
    let isChargeExclusive: Bool
    let isLocked: Bool

    init?(
        raw: DynamicJSONValue,
        sourceKey: String?,
        preferredKind: Kind?
    ) {
        guard case .object(let rootObject) = raw else { return nil }

        let rootType = rootObject["type"]?.textValueForDynamicParsing
        let candidates = Self.candidateObjects(from: rootObject, sourceKey: sourceKey)
        for candidate in candidates {
            if let content = Self.content(
                from: candidate.object,
                sourceKey: candidate.key,
                rootType: rootType,
                preferredKind: preferredKind
            ) {
                self = content
                return
            }
        }
        return nil
    }

    private init(
        kind: Kind,
        title: String,
        subtitle: String?,
        cover: String?,
        jumpURL: String?,
        bvid: String?,
        aid: Int?,
        cvid: Int?,
        badgeText: String,
        isChargeExclusive: Bool,
        isLocked: Bool
    ) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.cover = cover
        self.jumpURL = jumpURL
        self.bvid = bvid
        self.aid = aid
        self.cvid = cvid
        self.badgeText = badgeText
        self.isChargeExclusive = isChargeExclusive
        self.isLocked = isLocked
    }

    var normalizedCoverURL: String? {
        cover?.normalizedBiliURL()
    }

    var normalizedJumpURL: URL? {
        if let jumpURL, let url = URL(string: jumpURL.normalizedBiliURL()) {
            return url
        }
        if let bvid, !bvid.isEmpty {
            return URL(string: "https://www.bilibili.com/video/\(bvid)")
        }
        if let cvid, cvid > 0 {
            return URL(string: "https://www.bilibili.com/read/cv\(cvid)")
        }
        return nil
    }

    var isChargeArticleLike: Bool {
        guard isChargeExclusive else { return false }
        if kind == .article || cvid != nil {
            return true
        }
        let corpus = compactNonBlankDynamicFilterTexts([
            title,
            subtitle,
            badgeText
        ]).joined(separator: " ").lowercased()
        return corpus.contains("专栏") || corpus.contains("article")
    }

    func chargePageURL(author: DynamicAuthor?) -> URL? {
        if let mid = author?.mid, mid > 0 {
            return URL(string: "https://www.bilibili.com/h5/upower/index?mid=\(mid)")
        }
        guard let url = normalizedJumpURL,
              url.absoluteString.lowercased().contains("upower")
        else { return nil }
        return url
    }

    func asVideoItem(author: DynamicAuthor?) -> VideoItem? {
        guard kind == .video, let bvid, !bvid.isEmpty else { return nil }
        return VideoItem(
            bvid: bvid,
            aid: aid,
            title: title,
            pic: normalizedCoverURL,
            desc: subtitle,
            duration: nil,
            pubdate: author?.pubTS,
            owner: author?.owner,
            stat: nil,
            cid: nil,
            pages: nil,
            dimension: nil
        )
    }

    private static func candidateObjects(
        from root: [String: DynamicJSONValue],
        sourceKey: String?
    ) -> [(key: String, object: [String: DynamicJSONValue])] {
        var result = [(key: String, object: [String: DynamicJSONValue])]()
        var seenKeys = Set<String>()

        func append(_ key: String, value: DynamicJSONValue?) {
            guard let value else { return }
            switch value {
            case .object(let object):
                let signature = "\(key)#\(object.keys.sorted().joined(separator: ","))"
                guard seenKeys.insert(signature).inserted else { return }
                result.append((key, object))
                for nestedKey in ["content", "card", "item", "resource", "source", "sketch", "desc", "badge", "button", "cover_info"] {
                    if let nested = object[nestedKey]?.objectValueForDynamicParsing {
                        append("\(key).\(nestedKey)", value: .object(nested))
                    }
                }
            case .array(let values):
                for (index, item) in values.enumerated() {
                    append("\(key).\(index)", value: item)
                }
            case .string(let text):
                if let data = text.data(using: .utf8),
                   let decoded = try? JSONDecoder().decode(DynamicJSONValue.self, from: data) {
                    append(key, value: decoded)
                }
            case .number, .bool, .null:
                return
            }
        }

        if let sourceKey {
            append(sourceKey, value: .object(root))
        }

        let preferredKeys = [
            "upower_common", "upower_lottery", "charge", "paid", "blocked",
            "common", "article", "courses", "course", "pgc", "ugc_season",
            "medialist", "subscription", "subscription_new", "archive", "video"
        ]
        for key in preferredKeys {
            append(key, value: root[key])
        }
        append("root", value: .object(root))
        return result
    }

    private static func content(
        from object: [String: DynamicJSONValue],
        sourceKey: String,
        rootType: String?,
        preferredKind: Kind?
    ) -> DynamicPaidContent? {
        let objectType = object["type"]?.textValueForDynamicParsing
        let objectSubtype = object["sub_type"]?.textValueForDynamicParsing
        // Only trust structural API fields for paid-content identity. User-authored
        // titles/descriptions can naturally mention "充电" without being upower-only.
        let chargeSignalCorpus = compactNonBlankDynamicFilterTexts([
            sourceKey,
            rootType,
            objectType,
            objectSubtype,
            object["badge_text"]?.dynamicDisplayText,
            object["type_name"]?.dynamicDisplayText,
            object["hint_message"]?.dynamicDisplayText,
            nestedText(object, path: ["badge", "text"]),
            nestedText(object, path: ["badge", "title"]),
            nestedText(object, path: ["button", "text"])
        ])
        let lowerSource = "\(sourceKey) \(rootType ?? "") \(objectType ?? "") \(objectSubtype ?? "")".lowercased()
        let isChargeExclusive = hasTruthyChargeFlag(in: object)
            || chargeSignalCorpus.contains { isChargeMarker($0) }
        let kind = preferredKind ?? inferredKind(source: lowerSource, object: object)

        if sourceKey.contains("archive") || sourceKey.contains("video") {
            guard isChargeExclusive else { return nil }
        }

        let jumpURLText = normalizedJumpURLString(firstNonBlankDynamicText([
            object["jump_url"]?.textValueForDynamicParsing,
            object["jumpUrl"]?.textValueForDynamicParsing,
            object["url"]?.textValueForDynamicParsing,
            object["uri"]?.textValueForDynamicParsing,
            object["link"]?.textValueForDynamicParsing,
            object["web_url"]?.textValueForDynamicParsing,
            object["schema"]?.textValueForDynamicParsing
        ]))
        let bvid = firstNonBlankDynamicText([
            object["bvid"]?.textValueForDynamicParsing,
            object["bvid_str"]?.textValueForDynamicParsing,
            bvid(from: jumpURLText)
        ])
        let cvid = firstNonNilInt([
            object["cvid"]?.intValueForDynamicParsing,
            object["cv_id"]?.intValueForDynamicParsing,
            cvid(from: jumpURLText),
            kind == .article ? object["id"]?.intValueForDynamicParsing : nil,
            kind == .article ? object["rid"]?.intValueForDynamicParsing : nil
        ])
        let resolvedKind: Kind = {
            if kind == .unknown, bvid != nil { return .video }
            if kind == .unknown, cvid != nil { return .article }
            return kind
        }()
        guard isChargeExclusive else { return nil }

        let title = firstNonBlankDynamicText([
            object["title"]?.dynamicDisplayText,
            object["name"]?.dynamicDisplayText,
            object["long_title"]?.dynamicDisplayText,
            object["headline"]?.dynamicDisplayText,
            object["desc"]?.dynamicDisplayText,
            object["summary"]?.dynamicDisplayText,
            object["content"]?.dynamicDisplayText,
            object["message"]?.dynamicDisplayText,
            object["hint_message"]?.dynamicDisplayText
        ]) ?? defaultTitle(kind: resolvedKind, isChargeExclusive: isChargeExclusive)
        let subtitle = firstNonBlankDynamicText([
            object["sub_title"]?.dynamicDisplayText,
            object["subtitle"]?.dynamicDisplayText,
            object["desc"]?.dynamicDisplayText == title ? nil : object["desc"]?.dynamicDisplayText,
            object["summary"]?.dynamicDisplayText == title ? nil : object["summary"]?.dynamicDisplayText,
            object["hint_message"]?.dynamicDisplayText == title ? nil : object["hint_message"]?.dynamicDisplayText
        ])
        let cover = firstImageURL(from: object)
        let badge = badgeText(
            object: object,
            kind: resolvedKind,
            isChargeExclusive: isChargeExclusive
        )
        let isLocked = lowerSource.contains("blocked")
            || chargeSignalCorpus.contains { text in
                let normalized = text.lowercased()
                return normalized.contains("不可见")
                    || normalized.contains("暂不可见")
                    || normalized.contains("需充电")
                    || normalized.contains("解锁")
                    || normalized.contains("locked")
            }

        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return DynamicPaidContent(
            kind: resolvedKind,
            title: title,
            subtitle: subtitle,
            cover: cover,
            jumpURL: jumpURLText,
            bvid: bvid,
            aid: firstNonNilInt([
                object["aid"]?.intValueForDynamicParsing,
                object["id"]?.intValueForDynamicParsing,
                object["rid"]?.intValueForDynamicParsing
            ]),
            cvid: cvid,
            badgeText: badge,
            isChargeExclusive: isChargeExclusive,
            isLocked: isLocked
        )
    }

    private static func inferredKind(
        source: String,
        object: [String: DynamicJSONValue]
    ) -> Kind {
        if source.contains("article") || source.contains("read") || cvid(from: source) != nil {
            return .article
        }
        if source.contains("course") || source.contains("courses") {
            return .course
        }
        if source.contains("pgc")
            || source.contains("season")
            || source.contains("medialist")
            || source.contains("subscription") {
            return .collection
        }
        if source.contains("archive")
            || source.contains("video")
            || source.contains("ugc")
            || object["bvid"] != nil
            || object["bvid_str"] != nil {
            return .video
        }
        if object["cvid"] != nil || object["cv_id"] != nil {
            return .article
        }
        return .unknown
    }

    private static func firstNonNilInt(_ values: [Int?]) -> Int? {
        values.compactMap { $0 }.first
    }

    private static func hasTruthyChargeFlag(in object: [String: DynamicJSONValue]) -> Bool {
        let flagKeys = [
            "is_upower_exclusive", "is_upower_play", "is_charge", "is_charged",
            "need_charge", "need_pay", "is_paid", "pay_only", "locked"
        ]
        return flagKeys.contains { key in
            switch object[key] {
            case .bool(let value):
                return value
            case .number(let value):
                return value != "0"
            case .string(let value):
                let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return normalized == "1" || normalized == "true" || normalized == "yes"
            case .object, .array, .null, .none:
                return false
            }
        }
    }

    private static func isChargeMarker(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return normalized.contains("upower")
            || normalized.contains("charge")
            || normalized.contains("paid")
            || normalized.contains("exclusive")
            || normalized.contains("充电")
            || normalized.contains("付费")
            || normalized.contains("专属")
    }

    private static func firstImageURL(from object: [String: DynamicJSONValue]) -> String? {
        let directKeys = [
            "cover", "cover_url", "pic", "image", "image_url", "img_src",
            "thumbnail", "thumb", "bg_img", "background", "poster"
        ]
        for key in directKeys {
            if let url = imageURL(from: object[key]) {
                return url
            }
        }
        for key in ["covers", "pics", "images", "items"] {
            if let image = object[key]?.dynamicImageItems.first?.normalizedURL {
                return image
            }
        }
        for key in ["cover_info", "image", "pic", "content", "card", "item", "resource"] {
            if let nested = object[key]?.objectValueForDynamicParsing,
               let url = firstImageURL(from: nested) {
                return url
            }
        }
        return nil
    }

    private static func imageURL(from value: DynamicJSONValue?) -> String? {
        guard let value else { return nil }
        if let text = value.textValueForDynamicParsing {
            let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).normalizedBiliURL()
            guard normalized.hasPrefix("http://") || normalized.hasPrefix("https://") else { return nil }
            return normalized
        }
        if let object = value.objectValueForDynamicParsing {
            return firstImageURL(from: object)
        }
        return nil
    }

    private static func badgeText(
        object: [String: DynamicJSONValue],
        kind: Kind,
        isChargeExclusive: Bool
    ) -> String {
        let candidate = firstNonBlankDynamicText([
            object["badge_text"]?.dynamicDisplayText,
            object["type_name"]?.dynamicDisplayText,
            object["label"]?.dynamicDisplayText,
            object["tag"]?.dynamicDisplayText,
            nestedText(object, path: ["badge", "text"]),
            nestedText(object, path: ["badge", "title"]),
            nestedText(object, path: ["button", "text"])
        ])
        if let candidate, isChargeMarker(candidate) {
            return candidate
        }
        if isChargeExclusive {
            switch kind {
            case .video:
                return "充电视频"
            case .article:
                return "充电专栏"
            case .course:
                return "充电课程"
            case .collection, .unknown:
                return "充电专属"
            }
        }
        if let candidate, !candidate.isEmpty {
            return candidate
        }
        switch kind {
        case .video:
            return "视频"
        case .article:
            return "专栏"
        case .course:
            return "课程"
        case .collection:
            return "合集"
        case .unknown:
            return "动态内容"
        }
    }

    private static func defaultTitle(kind: Kind, isChargeExclusive: Bool) -> String {
        if isChargeExclusive {
            switch kind {
            case .video:
                return "充电视频"
            case .article:
                return "充电专栏"
            case .course:
                return "充电课程"
            case .collection, .unknown:
                return "充电专属内容"
            }
        }
        switch kind {
        case .video:
            return "视频"
        case .article:
            return "专栏"
        case .course:
            return "课程"
        case .collection:
            return "合集"
        case .unknown:
            return "动态内容"
        }
    }

    private static func nestedText(
        _ object: [String: DynamicJSONValue],
        path: [String]
    ) -> String? {
        guard let first = path.first else { return nil }
        var value = object[first]
        for key in path.dropFirst() {
            value = value?.objectValueForDynamicParsing?[key]
        }
        return value?.dynamicDisplayText
    }

    private static func normalizedJumpURLString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let bvid = bvid(from: trimmed) {
            return "https://www.bilibili.com/video/\(bvid)"
        }
        if let cvid = cvid(from: trimmed) {
            return "https://www.bilibili.com/read/cv\(cvid)"
        }
        let normalized = trimmed.normalizedBiliURL()
        if normalized.hasPrefix("http://") || normalized.hasPrefix("https://") {
            return normalized
        }
        return nil
    }

    private static func bvid(from text: String?) -> String? {
        guard let text,
              let range = text.range(of: #"BV[A-Za-z0-9]{10,}"#, options: .regularExpression)
        else { return nil }
        return String(text[range])
    }

    private static func cvid(from text: String?) -> Int? {
        guard let text else { return nil }
        let patterns = [
            #"cv(\d+)"#,
            #"read/(?:mobile/)?(\d+)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  match.numberOfRanges >= 2,
                  let range = Range(match.range(at: 1), in: text),
                  let value = Int(text[range])
            else { continue }
            return value
        }
        return nil
    }
}

nonisolated struct DynamicLive: Decodable, Hashable {
    let title: String?
    let cover: String?
    let roomID: Int?
    let uid: Int?
    let link: String?
    let online: Int?
    let areaName: String?
    let watchedText: String?
    let liveStatus: Int?
    let badgeText: String?

    enum CodingKeys: String, CodingKey {
        case link, title, cover, uid, online
        case livePlayInfo = "live_play_info"
        case roomID = "room_id"
        case roomIDAlt = "roomid"
        case liveID = "live_id"
        case liveStatus = "live_status"
        case areaName = "area_name"
        case watchedShow = "watched_show"
        case coverURL = "cover_url"
        case keyframe
        case pendants
        case badgeText = "badge_text"
        case status
    }

    init(from decoder: Decoder) throws {
        if let value = try? decoder.singleValueContainer().decode(String.self),
           let data = value.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(DynamicLive.self, from: data) {
            self = decoded
            return
        }

        let raw = try DynamicJSONValue(from: decoder)
        let rawObject = raw.objectValueForDynamicParsing ?? [:]
        let embeddedObject = Self.embeddedContentObject(from: rawObject) ?? [:]
        let object = rawObject.merging(embeddedObject) { current, _ in current }
        let playInfo = embeddedObject["live_play_info"]?.objectValueForDynamicParsing
            ?? rawObject["live_play_info"]?.objectValueForDynamicParsing
            ?? object["live_play_info"]?.objectValueForDynamicParsing
        let source = playInfo ?? object
        let watchedShow = source["watched_show"]?.objectValueForDynamicParsing
        let pendants = source["pendants"]?.objectValueForDynamicParsing ?? object["pendants"]?.objectValueForDynamicParsing

        title = firstNonBlankDynamicText([
            source["title"]?.textValueForDynamicParsing,
            object["title"]?.textValueForDynamicParsing,
            object["desc"]?.textValueForDynamicParsing
        ])
        cover = Self.firstImageURL(from: [source, object, embeddedObject, rawObject])
        let linkValue = firstNonBlankDynamicText([
            source["link"]?.textValueForDynamicParsing,
            source["jump_url"]?.textValueForDynamicParsing,
            source["url"]?.textValueForDynamicParsing,
            object["link"]?.textValueForDynamicParsing,
            object["jump_url"]?.textValueForDynamicParsing
        ])?.normalizedBiliURL()
        roomID = source["room_id"]?.intValueForDynamicParsing
            ?? source["roomid"]?.intValueForDynamicParsing
            ?? Self.roomID(from: linkValue)
            ?? object["room_id"]?.intValueForDynamicParsing
            ?? object["roomid"]?.intValueForDynamicParsing
        uid = source["uid"]?.intValueForDynamicParsing ?? object["uid"]?.intValueForDynamicParsing
        link = linkValue
        online = source["online"]?.intValueForDynamicParsing
            ?? source["watched_show"]?.intValueForDynamicParsing
            ?? watchedShow?["num"]?.intValueForDynamicParsing
            ?? watchedShow?["watched_num"]?.intValueForDynamicParsing
        areaName = firstNonBlankDynamicText([
            source["area_name"]?.textValueForDynamicParsing,
            source["area"]?.textValueForDynamicParsing,
            object["area_name"]?.textValueForDynamicParsing
        ])
        watchedText = firstNonBlankDynamicText([
            watchedShow?["text_large"]?.textValueForDynamicParsing,
            watchedShow?["text_small"]?.textValueForDynamicParsing,
            watchedShow?["text"]?.textValueForDynamicParsing,
            watchedShow?["watched_show_text"]?.textValueForDynamicParsing,
            source["watched_show"]?.textValueForDynamicParsing
        ])
        liveStatus = source["live_status"]?.intValueForDynamicParsing
            ?? source["status"]?.intValueForDynamicParsing
            ?? object["live_status"]?.intValueForDynamicParsing
        badgeText = firstNonBlankDynamicText([
            source["badge_text"]?.textValueForDynamicParsing,
            object["badge_text"]?.textValueForDynamicParsing,
            Self.badgeText(from: pendants)
        ])
    }

    private static func roomID(from link: String?) -> Int? {
        guard let link, !link.isEmpty else { return nil }
        if let components = URLComponents(string: link) {
            for key in ["room_id", "roomid"] {
                if let value = components.queryItems?.first(where: { $0.name == key })?.value,
                   let roomID = Int(value) {
                    return roomID
                }
            }

            let pathParts = components.path.split(separator: "/").map(String.init)
            for part in pathParts.reversed() {
                if let roomID = Int(part) {
                    return roomID
                }
            }
        }

        if let range = link.range(of: #"live\.bilibili\.com/(?:h5/)?\d+"#, options: .regularExpression) {
            let matched = String(link[range])
            if let digitRange = matched.range(of: #"\d+"#, options: .regularExpression),
               let value = Int(matched[digitRange]) {
                return value
            }
        }
        return nil
    }

    private static func embeddedContentObject(from object: [String: DynamicJSONValue]) -> [String: DynamicJSONValue]? {
        for key in ["content", "card", "live_play_info"] {
            guard let value = object[key] else { continue }
            if let nested = value.objectValueForDynamicParsing {
                return nested
            }
            guard let text = value.textValueForDynamicParsing,
                  let data = text.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(DynamicJSONValue.self, from: data)
            else { continue }
            if let nested = decoded.objectValueForDynamicParsing {
                return nested
            }
        }
        return nil
    }

    private static func firstImageURL(from objects: [[String: DynamicJSONValue]]) -> String? {
        let keys = [
            "cover", "cover_url", "keyframe", "live_cover", "room_cover",
            "user_cover", "system_cover", "pic", "image", "image_url",
            "img_src", "thumbnail", "thumb"
        ]
        for object in objects {
            for key in keys {
                if let url = imageURL(from: object[key]) {
                    return url
                }
            }
        }
        for object in objects {
            for key in ["cover_info", "image", "pic", "room_info", "live_play_info"] {
                if let nested = object[key]?.objectValueForDynamicParsing,
                   let url = firstImageURL(from: [nested]) {
                    return url
                }
            }
        }
        return nil
    }

    private static func imageURL(from value: DynamicJSONValue?) -> String? {
        guard let value else { return nil }
        if let text = value.textValueForDynamicParsing,
           let url = normalizedImageURL(text) {
            return url
        }
        if let object = value.objectValueForDynamicParsing {
            return firstImageURL(from: [object])
        }
        return nil
    }

    private static func normalizedImageURL(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).normalizedBiliURL()
        guard normalized.hasPrefix("https://") || normalized.hasPrefix("http://"),
              let url = URL(string: normalized)
        else { return nil }
        let pathExtension = url.pathExtension.lowercased()
        let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "avif"]
        guard normalized.contains("hdslb.com")
            || normalized.contains("biliimg.com")
            || imageExtensions.contains(pathExtension)
        else { return nil }
        return normalized
    }

    private static func badgeText(from pendants: [String: DynamicJSONValue]?) -> String? {
        guard let pendants else { return nil }
        let candidates = pendants.values.compactMap(\.objectValueForDynamicParsing)
        for candidate in candidates {
            if let text = firstNonBlankDynamicText([
                candidate["text"]?.textValueForDynamicParsing,
                candidate["content"]?.textValueForDynamicParsing,
                candidate["name"]?.textValueForDynamicParsing
            ]) {
                return text
            }
        }
        return nil
    }

    var normalizedCoverURL: String? {
        cover?.normalizedBiliURL()
    }

    var normalizedLinkURL: URL? {
        guard let link, !link.isEmpty else { return nil }
        return URL(string: link.normalizedBiliURL())
    }

    var displayTitle: String {
        title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? title! : "直播中"
    }

    var statusText: String {
        if let badgeText, !badgeText.isEmpty {
            return badgeText
        }
        return liveStatus == 1 || liveStatus == nil ? "直播中" : "直播"
    }

    var viewerText: String? {
        if let watchedText, !watchedText.isEmpty {
            return watchedText
        }
        if let online, online > 0 {
            return "\(BiliFormatters.compactCount(online)) 人看过"
        }
        return nil
    }

    var hasLiveIdentity: Bool {
        roomID != nil
            || uid != nil
            || normalizedLinkURL != nil
            || normalizedCoverURL != nil
            || title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    func asLiveRoom(author: DynamicAuthor?) -> LiveRoom? {
        let parsedRoomID = roomID ?? Self.roomID(from: link)
        let anchorUID = uid ?? author?.mid
        guard (parsedRoomID ?? 0) > 0 || (anchorUID ?? 0) > 0 else { return nil }
        return LiveRoom(
            roomID: parsedRoomID ?? 0,
            title: displayTitle,
            uname: author?.name ?? "Unknown",
            uid: anchorUID,
            face: author?.face,
            cover: cover,
            keyframe: cover,
            online: online,
            areaName: areaName,
            parentAreaName: nil,
            liveStatus: liveStatus
        )
    }
}

nonisolated struct DynamicOpus: Decodable, Hashable {
    let title: String?
    let summary: DynamicText?
    let content: DynamicText?
    let desc: DynamicText?
    let pics: [DynamicImageItem]?

    enum CodingKeys: String, CodingKey {
        case title, summary, content, desc, pics, images, items
    }

    var displayText: String? {
        firstNonBlankDynamicText([
            summary?.displayText,
            content?.displayText,
            desc?.displayText,
            title
        ])
    }

    var segments: [DynamicTextSegment] {
        firstNonEmptyDynamicSegments([
            summary?.segments ?? [],
            content?.segments ?? [],
            desc?.segments ?? [],
            dynamicPlainTextSegments(title)
        ])
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = container.decodeLossyStringIfPresent(forKey: .title)
        summary = try? container.decodeIfPresent(DynamicText.self, forKey: .summary)
        content = try? container.decodeIfPresent(DynamicText.self, forKey: .content)
        desc = try? container.decodeIfPresent(DynamicText.self, forKey: .desc)
        pics = (try? container.decodeIfPresent([DynamicImageItem].self, forKey: .pics))
            ?? (try? container.decodeIfPresent([DynamicImageItem].self, forKey: .images))
            ?? (try? container.decodeIfPresent([DynamicImageItem].self, forKey: .items))
    }

    var containsGoodsPromotion: Bool {
        summary?.containsGoodsPromotion == true
            || content?.containsGoodsPromotion == true
            || desc?.containsGoodsPromotion == true
    }

    var containsDynamicAdPromotion: Bool {
        summary?.containsDynamicAdPromotion == true
            || content?.containsDynamicAdPromotion == true
            || desc?.containsDynamicAdPromotion == true
            || BiliContentFilter.isDynamicAdText(title)
    }
}

nonisolated struct DynamicDraw: Decodable, Hashable {
    let items: [DynamicImageItem]?
    let title: String?
    let summary: DynamicText?
    let desc: DynamicText?

    var displayText: String? {
        firstNonBlankDynamicText([
            summary?.displayText,
            desc?.displayText,
            title
        ])
    }

    var segments: [DynamicTextSegment] {
        firstNonEmptyDynamicSegments([
            summary?.segments ?? [],
            desc?.segments ?? [],
            dynamicPlainTextSegments(title)
        ])
    }

    enum CodingKeys: String, CodingKey {
        case items, title, summary, desc
        case pics, images
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? container.decodeIfPresent([DynamicImageItem].self, forKey: .items))
            ?? (try? container.decodeIfPresent([DynamicImageItem].self, forKey: .pics))
            ?? (try? container.decodeIfPresent([DynamicImageItem].self, forKey: .images))
        title = container.decodeLossyStringIfPresent(forKey: .title)
        summary = try? container.decodeIfPresent(DynamicText.self, forKey: .summary)
        desc = try? container.decodeIfPresent(DynamicText.self, forKey: .desc)
    }

    var containsGoodsPromotion: Bool {
        summary?.containsGoodsPromotion == true
            || desc?.containsGoodsPromotion == true
    }

    var containsDynamicAdPromotion: Bool {
        summary?.containsDynamicAdPromotion == true
            || desc?.containsDynamicAdPromotion == true
            || BiliContentFilter.isDynamicAdText(title)
    }
}

nonisolated struct DynamicImageItem: Decodable, Hashable, Sendable {
    let url: String
    let width: Int?
    let height: Int?
    let size: Double?
    let mediaType: String?
    let isLivePhotoFlag: Bool
    let liveVideoURL: String?
    let isAnimatedGIFFlag: Bool
    let animatedImageURL: String?

    enum CodingKeys: String, CodingKey {
        case src, url, width, height, size
        case type, format
        case mediaType = "media_type"
        case mimeType = "mime_type"
        case imageType = "image_type"
        case imgType = "img_type"
        case pictureType = "picture_type"
        case livePhoto = "live_photo"
        case livePhotoCamel = "livePhoto"
        case isLivePhoto = "is_live_photo"
        case isLivePhotoCamel = "isLivePhoto"
        case liveVideoURL = "live_video_url"
        case liveVideoURLCamel = "liveVideoUrl"
        case videoURL = "video_url"
        case videoURLCamel = "videoUrl"
        case videoSrc = "video_src"
        case videoSrcCamel = "videoSrc"
        case gifURL = "gif_url"
        case gifURLCamel = "gifUrl"
        case animatedURL = "animated_url"
        case animatedURLCamel = "animatedUrl"
        case isGIF = "is_gif"
        case isGIFCamel = "isGif"
        case imgSrc = "img_src"
        case imgWidth = "img_width"
        case imgHeight = "img_height"
        case imgSize = "img_size"
        case rawURL = "raw_url"
        case imageURL = "image_url"
        case imageWidth = "image_width"
        case imageHeight = "image_height"
        case originalWidth = "orig_width"
        case originalHeight = "orig_height"
        case widthShort = "w"
        case heightShort = "h"
    }

    init(
        url: String,
        width: Int?,
        height: Int?,
        size: Double?,
        mediaType: String? = nil,
        isLivePhoto: Bool = false,
        liveVideoURL: String? = nil,
        isAnimatedGIF: Bool = false,
        animatedImageURL: String? = nil
    ) {
        self.url = url
        self.width = width
        self.height = height
        self.size = size
        self.mediaType = mediaType
        self.isLivePhotoFlag = isLivePhoto
        self.liveVideoURL = liveVideoURL
        self.isAnimatedGIFFlag = isAnimatedGIF
        self.animatedImageURL = animatedImageURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = container.decodeLossyStringIfPresent(forKey: .src)
            ?? container.decodeLossyStringIfPresent(forKey: .url)
            ?? container.decodeLossyStringIfPresent(forKey: .imgSrc)
            ?? container.decodeLossyStringIfPresent(forKey: .rawURL)
            ?? container.decodeLossyStringIfPresent(forKey: .imageURL)
            ?? ""
        width = container.decodeLossyIntIfPresent(forKey: .width)
            ?? container.decodeLossyIntIfPresent(forKey: .imgWidth)
            ?? container.decodeLossyIntIfPresent(forKey: .imageWidth)
            ?? container.decodeLossyIntIfPresent(forKey: .originalWidth)
            ?? container.decodeLossyIntIfPresent(forKey: .widthShort)
        height = container.decodeLossyIntIfPresent(forKey: .height)
            ?? container.decodeLossyIntIfPresent(forKey: .imgHeight)
            ?? container.decodeLossyIntIfPresent(forKey: .imageHeight)
            ?? container.decodeLossyIntIfPresent(forKey: .originalHeight)
            ?? container.decodeLossyIntIfPresent(forKey: .heightShort)
        size = (try? container.decodeIfPresent(Double.self, forKey: .size))
            ?? (try? container.decodeIfPresent(Double.self, forKey: .imgSize))
            ?? container.decodeLossyStringIfPresent(forKey: .size).flatMap(Double.init)
            ?? container.decodeLossyStringIfPresent(forKey: .imgSize).flatMap(Double.init)
        let decodedMediaType = [
            container.decodeLossyStringIfPresent(forKey: .mediaType),
            container.decodeLossyStringIfPresent(forKey: .mimeType),
            container.decodeLossyStringIfPresent(forKey: .imageType),
            container.decodeLossyStringIfPresent(forKey: .imgType),
            container.decodeLossyStringIfPresent(forKey: .pictureType),
            container.decodeLossyStringIfPresent(forKey: .type),
            container.decodeLossyStringIfPresent(forKey: .format)
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty }
        let livePhotoValue = (try? container.decode(DynamicJSONValue.self, forKey: .livePhoto))
            ?? (try? container.decode(DynamicJSONValue.self, forKey: .livePhotoCamel))
        let isLivePhoto = container.decodeLossyBoolIfPresent(forKey: .isLivePhoto) == true
            || container.decodeLossyBoolIfPresent(forKey: .isLivePhotoCamel) == true
        let isGIF = container.decodeLossyBoolIfPresent(forKey: .isGIF) == true
            || container.decodeLossyBoolIfPresent(forKey: .isGIFCamel) == true
        animatedImageURL = container.decodeLossyStringIfPresent(forKey: .gifURL)
            ?? container.decodeLossyStringIfPresent(forKey: .gifURLCamel)
            ?? container.decodeLossyStringIfPresent(forKey: .animatedURL)
            ?? container.decodeLossyStringIfPresent(forKey: .animatedURLCamel)
        let livePhotoObjectURL: String? = {
            guard case .object(let values) = livePhotoValue else { return nil }
            return firstNonBlankDynamicText([
                values["video_url"]?.textValue,
                values["video_src"]?.textValue,
                values["live_video_url"]?.textValue,
                values["liveVideoUrl"]?.textValue,
                values["videoUrl"]?.textValue,
                values["url"]?.textValue,
                values["src"]?.textValue
            ])
        }()
        let hasLivePhotoObject: Bool = {
            guard case .object(let values) = livePhotoValue else { return false }
            return !values.isEmpty
        }()
        liveVideoURL = container.decodeLossyStringIfPresent(forKey: .liveVideoURL)
            ?? container.decodeLossyStringIfPresent(forKey: .liveVideoURLCamel)
            ?? container.decodeLossyStringIfPresent(forKey: .videoURL)
            ?? container.decodeLossyStringIfPresent(forKey: .videoURLCamel)
            ?? container.decodeLossyStringIfPresent(forKey: .videoSrc)
            ?? container.decodeLossyStringIfPresent(forKey: .videoSrcCamel)
            ?? livePhotoObjectURL
        let liveFlag = container.decodeLossyStringIfPresent(forKey: .livePhoto)
            ?? container.decodeLossyStringIfPresent(forKey: .livePhotoCamel)
        let liveFlagValue = container.decodeLossyBoolIfPresent(forKey: .livePhoto)
            ?? container.decodeLossyBoolIfPresent(forKey: .livePhotoCamel)
        mediaType = decodedMediaType
            ?? liveFlag
            ?? (isLivePhoto ? "live-photo" : nil)
            ?? (liveFlagValue == true ? "live-photo" : nil)
            ?? (hasLivePhotoObject ? "live-photo" : nil)
        isLivePhotoFlag = isLivePhoto
            || liveFlagValue == true
            || hasLivePhotoObject
            || liveVideoURL != nil
        isAnimatedGIFFlag = isGIF || animatedImageURL != nil
    }

    var normalizedURL: String? {
        let normalized = url.trimmingCharacters(in: .whitespacesAndNewlines).normalizedBiliURL()
        return normalized.isEmpty ? nil : normalized
    }

    var aspectRatio: Double {
        if let width, let height, width > 0, height > 0 {
            return Double(width) / Double(height)
        }
        if let ratio = normalizedURL?.biliImageURLAspectRatio {
            return ratio
        }
        return 1
    }

    var normalizedLiveVideoURL: String? {
        let normalized = liveVideoURL?.trimmingCharacters(in: .whitespacesAndNewlines).normalizedBiliURL() ?? ""
        return normalized.isEmpty ? nil : normalized
    }

    var normalizedAnimatedImageURL: String? {
        let normalized = animatedImageURL?.trimmingCharacters(in: .whitespacesAndNewlines).normalizedBiliURL() ?? ""
        return normalized.isEmpty ? nil : normalized
    }

    var isLongImage: Bool {
        let text = (mediaType ?? "")
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
        return text.contains("long") || text.contains("长图") || aspectRatio < 0.62
    }

    var isAnimatedGIF: Bool {
        let text = "\(mediaType ?? "") \(normalizedAnimatedImageURL ?? "") \(normalizedURL ?? url)"
            .lowercased()
            .removingPercentEncoding ?? "\(mediaType ?? "") \(normalizedAnimatedImageURL ?? "") \(normalizedURL ?? url)".lowercased()
        return isAnimatedGIFFlag || text.contains("gif") || text.contains("image/gif")
    }

    var isLiveImage: Bool {
        let text = (mediaType ?? "")
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
        return isLivePhotoFlag
            || text.contains("live")
            || text.contains("livephoto")
            || text.contains("实况")
            || normalizedLiveVideoURL != nil
    }

    var mediaBadgeText: String? {
        if isLiveImage { return "LIVE" }
        if isAnimatedGIF { return "GIF" }
        return nil
    }
}

nonisolated struct DynamicModuleStat: Decodable, Hashable {
    let like: DynamicStatItem?
    let reply: DynamicStatItem?
    let comment: DynamicStatItem?
    let comments: DynamicStatItem?
    let repost: DynamicStatItem?
    let forward: DynamicStatItem?

    enum CodingKeys: String, CodingKey {
        case like, reply, comment, comments, repost, forward
    }
}

nonisolated struct DynamicStatItem: Decodable, Hashable {
    let count: Int?
    let status: Bool?

    enum CodingKeys: String, CodingKey {
        case count, status, text
        case countText = "count_text"
        case countStr = "count_str"
    }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer() {
            if let value = try? single.decode(Int.self) {
                count = value
                status = nil
                return
            }
            if let value = try? single.decode(String.self),
               let parsed = Self.parseCount(value) {
                count = parsed
                status = nil
                return
            }
            if let value = try? single.decode(Bool.self) {
                count = nil
                status = value
                return
            }
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        count = container.decodeLossyIntIfPresent(forKey: .count)
            ?? Self.parseCount(container.decodeLossyStringIfPresent(forKey: .countText))
            ?? Self.parseCount(container.decodeLossyStringIfPresent(forKey: .countStr))
            ?? Self.parseCount(container.decodeLossyStringIfPresent(forKey: .text))
        status = container.decodeLossyBoolIfPresent(forKey: .status)
    }

    private static func parseCount(_ value: String?) -> Int? {
        guard var text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        text = text.replacingOccurrences(of: ",", with: "")
        if let value = Int(text) {
            return value
        }

        let units: [(suffix: String, multiplier: Double)] = [
            ("亿", 100_000_000),
            ("万", 10_000)
        ]
        for unit in units where text.hasSuffix(unit.suffix) {
            let numberText = String(text.dropLast(unit.suffix.count))
            guard let number = Double(numberText) else { continue }
            return Int(number * unit.multiplier)
        }
        return nil
    }
}

nonisolated struct DynamicArchive: Decodable, Hashable {
    let aid: Int?
    let bvid: String?
    let title: String?
    let cover: String?
    let desc: String?
    let durationText: String?
    let duration: Int?
    let stat: DynamicArchiveStat?

    enum CodingKeys: String, CodingKey {
        case aid, bvid, title, cover, desc, stat, duration, length
        case durationText = "duration_text"
        case durationTextAlt = "durationText"
        case durationStr = "duration_str"
        case durationString = "duration_string"
        case durationSecond = "duration_second"
        case durationSeconds = "duration_seconds"
        case durationTime = "duration_time"
        case durationMS = "duration_ms"
        case durationMillis = "duration_millis"
        case coverRightText = "cover_right_text"
        case coverRightTextAlt = "coverRightText"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        aid = container.decodeLossyIntIfPresent(forKey: .aid)
        bvid = try container.decodeIfPresent(String.self, forKey: .bvid)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        cover = try container.decodeIfPresent(String.self, forKey: .cover)
        desc = try container.decodeIfPresent(String.self, forKey: .desc)
        durationText = firstNonBlankDynamicText([
            container.decodeLossyStringIfPresent(forKey: .durationText),
            container.decodeLossyStringIfPresent(forKey: .durationTextAlt),
            container.decodeLossyStringIfPresent(forKey: .durationStr),
            container.decodeLossyStringIfPresent(forKey: .durationString),
            container.decodeLossyStringIfPresent(forKey: .length),
            container.decodeLossyStringIfPresent(forKey: .coverRightText),
            container.decodeLossyStringIfPresent(forKey: .coverRightTextAlt),
            container.decodeLossyStringIfPresent(forKey: .duration)
        ])
        duration = Self.durationSeconds(
            text: durationText,
            seconds: container.decodeLossyIntIfPresent(forKey: .duration)
                ?? container.decodeLossyIntIfPresent(forKey: .durationSecond)
                ?? container.decodeLossyIntIfPresent(forKey: .durationSeconds)
                ?? container.decodeLossyIntIfPresent(forKey: .durationTime),
            milliseconds: container.decodeLossyIntIfPresent(forKey: .durationMS)
                ?? container.decodeLossyIntIfPresent(forKey: .durationMillis)
        )
        stat = try container.decodeIfPresent(DynamicArchiveStat.self, forKey: .stat)
    }

    init?(fallbackObject object: [String: DynamicJSONValue]) {
        let jumpURL = firstNonBlankDynamicText([
            object["jump_url"]?.textValueForDynamicParsing,
            object["url"]?.textValueForDynamicParsing,
            object["uri"]?.textValueForDynamicParsing,
            object["link"]?.textValueForDynamicParsing,
            object["jumpUrl"]?.textValueForDynamicParsing
        ])
        let bvid = firstNonBlankDynamicText([
            object["bvid"]?.textValueForDynamicParsing,
            object["bvid_str"]?.textValueForDynamicParsing,
            Self.bvid(from: jumpURL)
        ])
        guard let bvid, !bvid.isEmpty else { return nil }

        let statObject = object["stat"]?.objectValueForDynamicParsing
            ?? object["cnt_info"]?.objectValueForDynamicParsing
        let durationText = firstNonBlankDynamicText([
            object["duration_text"]?.textValueForDynamicParsing,
            object["durationText"]?.textValueForDynamicParsing,
            object["duration_str"]?.textValueForDynamicParsing,
            object["duration_string"]?.textValueForDynamicParsing,
            object["length"]?.textValueForDynamicParsing,
            object["cover_right_text"]?.textValueForDynamicParsing,
            object["coverRightText"]?.textValueForDynamicParsing,
            object["duration"]?.textValueForDynamicParsing
        ])

        self.aid = object["aid"]?.intValueForDynamicParsing
            ?? object["id"]?.intValueForDynamicParsing
            ?? object["rid"]?.intValueForDynamicParsing
        self.bvid = bvid
        self.title = firstNonBlankDynamicText([
            object["title"]?.textValueForDynamicParsing,
            object["long_title"]?.textValueForDynamicParsing,
            object["name"]?.textValueForDynamicParsing,
            object["desc"]?.textValueForDynamicParsing
        ])
        self.cover = firstNonBlankDynamicText([
            object["cover"]?.textValueForDynamicParsing,
            object["cover_url"]?.textValueForDynamicParsing,
            object["pic"]?.textValueForDynamicParsing,
            object["image_url"]?.textValueForDynamicParsing,
            object["thumbnail"]?.textValueForDynamicParsing,
            object["thumb"]?.textValueForDynamicParsing
        ])?.normalizedBiliURL()
        self.desc = object["desc"]?.textValueForDynamicParsing
        self.durationText = durationText
        self.duration = Self.durationSeconds(
            text: durationText,
            seconds: object["duration"]?.intValueForDynamicParsing
                ?? object["duration_second"]?.intValueForDynamicParsing
                ?? object["duration_seconds"]?.intValueForDynamicParsing
                ?? object["duration_time"]?.intValueForDynamicParsing,
            milliseconds: object["duration_ms"]?.intValueForDynamicParsing
                ?? object["duration_millis"]?.intValueForDynamicParsing
        )
        self.stat = DynamicArchiveStat(fallbackObject: statObject)
    }

    func asVideoItem(author: DynamicAuthor?) -> VideoItem? {
        guard let bvid, !bvid.isEmpty else { return nil }
        return VideoItem(
            bvid: bvid,
            aid: aid,
            title: title ?? "视频",
            pic: cover?.normalizedBiliURL(),
            desc: desc,
            duration: duration,
            pubdate: author?.pubTS,
            owner: author?.owner,
            stat: VideoStat(
                view: stat?.play,
                reply: stat?.reply,
                like: stat?.like,
                coin: stat?.coin,
                favorite: stat?.favorite
            ),
            cid: nil,
            pages: nil,
            dimension: nil
        )
    }

    nonisolated private static func durationSeconds(text: String?, seconds: Int?, milliseconds: Int?) -> Int? {
        if let parsed = text.flatMap(durationSeconds) {
            return parsed
        }
        if let normalized = normalizedSeconds(seconds) {
            return normalized
        }
        if let milliseconds, milliseconds > 0 {
            return max(milliseconds / 1000, 1)
        }
        return nil
    }

    nonisolated private static func durationSeconds(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "--:--" else { return nil }
        if let seconds = Int(trimmed), let normalized = normalizedSeconds(seconds) {
            return normalized
        }

        let normalizedText = trimmed
            .replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: " ", with: "")
        let parts = normalizedText.split(separator: ":").compactMap { Int($0) }
        if parts.count == 2 {
            return positiveDuration(parts[0] * 60 + parts[1])
        }
        if parts.count == 3 {
            return positiveDuration(parts[0] * 3600 + parts[1] * 60 + parts[2])
        }
        return chineseDurationSeconds(normalizedText)
    }

    nonisolated private static func normalizedSeconds(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        if value > 100_000 {
            return max(value / 1000, 1)
        }
        return value
    }

    nonisolated private static func positiveDuration(_ value: Int) -> Int? {
        value > 0 ? value : nil
    }

    nonisolated private static func chineseDurationSeconds(_ value: String) -> Int? {
        let pattern = #"(?:(\d+)(?:小时|时|h))?(?:(\d+)(?:分钟|分|m))?(?:(\d+)(?:秒|s))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              match.range.length > 0
        else { return nil }

        func component(_ index: Int) -> Int {
            guard match.range(at: index).location != NSNotFound,
                  let range = Range(match.range(at: index), in: value)
            else { return 0 }
            return Int(value[range]) ?? 0
        }

        return positiveDuration(component(1) * 3600 + component(2) * 60 + component(3))
    }

    nonisolated private static func bvid(from text: String?) -> String? {
        guard let text else { return nil }
        guard let range = text.range(of: #"BV[A-Za-z0-9]{10,}"#, options: .regularExpression) else { return nil }
        return String(text[range])
    }
}

nonisolated struct DynamicArchiveStat: Decodable, Hashable {
    let play: Int?
    let reply: Int?
    let like: Int?
    let coin: Int?
    let favorite: Int?

    enum CodingKeys: String, CodingKey {
        case play, reply, like, coin, favorite
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        play = container.decodeLossyIntIfPresent(forKey: .play)
        reply = container.decodeLossyIntIfPresent(forKey: .reply)
        like = container.decodeLossyIntIfPresent(forKey: .like)
        coin = container.decodeLossyIntIfPresent(forKey: .coin)
        favorite = container.decodeLossyIntIfPresent(forKey: .favorite)
    }

    init?(fallbackObject object: [String: DynamicJSONValue]?) {
        guard let object else { return nil }
        play = object["play"]?.intValueForDynamicParsing
            ?? object["view"]?.intValueForDynamicParsing
            ?? object["view_count"]?.intValueForDynamicParsing
        reply = object["reply"]?.intValueForDynamicParsing
            ?? object["danmaku"]?.intValueForDynamicParsing
            ?? object["comment"]?.intValueForDynamicParsing
        like = object["like"]?.intValueForDynamicParsing
        coin = object["coin"]?.intValueForDynamicParsing
        favorite = object["favorite"]?.intValueForDynamicParsing
            ?? object["collect"]?.intValueForDynamicParsing
    }
}

nonisolated extension String {
    func normalizedBiliURL() -> String {
        if hasPrefix("//") {
            return "https:" + self
        }
        if hasPrefix("http://") {
            return replacingOccurrences(of: "http://", with: "https://")
        }
        return self
    }

    func biliCoverThumbnailURL(width: Int = 672, height: Int = 378) -> String {
        let normalized = normalizedBiliURL()
        guard normalized.contains("hdslb.com") else {
            return normalized
        }

        let size = RemoteImageQualityPreference.effectiveThumbnailSize(width: width, height: height)
        return normalized.biliImageView2URL(width: size.width, height: size.height)
    }

    func biliCoverThumbnailURL(
        fitting size: CGSize,
        scale: CGFloat,
        maximumPixelLength: Int = 1280
    ) -> String {
        biliCoverThumbnailURL(
            width: Self.biliThumbnailPixelLength(size.width, scale: scale, maximum: maximumPixelLength),
            height: Self.biliThumbnailPixelLength(size.height, scale: scale, maximum: maximumPixelLength)
        )
    }

    func biliAvatarThumbnailURL(size: Int = 96) -> String {
        let normalized = normalizedBiliURL()
        guard normalized.contains("hdslb.com") else {
            return normalized
        }

        let pixelSize = max(48, size)
        return normalized.biliImageView2URL(width: pixelSize, height: pixelSize)
    }

    func biliImageThumbnailURL(maxSide: Int = 1080) -> String {
        let normalized = normalizedBiliURL()
        guard normalized.contains("hdslb.com") else {
            return normalized
        }

        let pixelSize = min(RemoteImageQualityPreference.effectiveMaximumPixelLength(maxSide), 4096)
        return "\(normalized.biliImageBaseURL())?imageView2/2/w/\(pixelSize)/format/webp"
    }

    func biliImageOriginalURL() -> String {
        let normalized = normalizedBiliURL()
        guard normalized.contains("hdslb.com") else {
            return normalized
        }
        return normalized.biliImageBaseURL()
    }

    func biliImageThumbnailURL(
        fitting size: CGSize,
        scale: CGFloat,
        maximumPixelLength: Int = 1280
    ) -> String {
        biliImageThumbnailURL(
            maxSide: Self.biliThumbnailMaxPixelSide(
                fitting: size,
                scale: scale,
                maximumPixelLength: maximumPixelLength
            )
        )
    }

    func biliImageCacheIdentityURLString() -> String {
        let normalized = normalizedBiliURL()
        guard normalized.contains("hdslb.com") else {
            return normalized
        }

        let base = normalized.biliImageBaseURL()
        guard normalized.contains("imageView2") else {
            return base
        }

        let sourcePixelBucket = normalized.biliImageURLPixelBucket.map { "#src-\($0)" } ?? ""
        if let ratio = normalized.biliImageURLAspectRatio {
            let ratioBucket = Int((ratio * 100).rounded())
            return "\(base)#crop-\(ratioBucket)\(sourcePixelBucket)"
        }
        return "\(base)#fit\(sourcePixelBucket)"
    }

    static func biliThumbnailMaxPixelSide(
        fitting size: CGSize,
        scale: CGFloat,
        maximumPixelLength: Int = 1280
    ) -> Int {
        Swift.max(
            biliThumbnailPixelLength(size.width, scale: scale, maximum: maximumPixelLength),
            biliThumbnailPixelLength(size.height, scale: scale, maximum: maximumPixelLength)
        )
    }

    var biliImageURLAspectRatio: Double? {
        let normalized = normalizedBiliURL()
        let candidates = [
            #"(?i)[@_/?&](?:w|width)[_=/:-]?(\d{2,5}).{0,18}(?:h|height)[_=/:-]?(\d{2,5})"#,
            #"(?i)[@_/?&](?:h|height)[_=/:-]?(\d{2,5}).{0,18}(?:w|width)[_=/:-]?(\d{2,5})"#
        ]

        for (index, pattern) in candidates.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
            guard let match = regex.firstMatch(in: normalized, range: range),
                  match.numberOfRanges >= 3,
                  let firstRange = Range(match.range(at: 1), in: normalized),
                  let secondRange = Range(match.range(at: 2), in: normalized),
                  let first = Double(normalized[firstRange]),
                  let second = Double(normalized[secondRange]),
                  first > 0,
                  second > 0
            else { continue }

            let width = index == 0 ? first : second
            let height = index == 0 ? second : first
            let ratio = width / height
            guard ratio >= 0.05, ratio <= 20 else { continue }
            return ratio
        }

        return nil
    }

    var biliImageURLPixelBucket: Int? {
        let pieces = normalizedBiliURL().split(separator: "/")
        var pixelLengths = [Int]()
        for index in pieces.indices {
            let key = pieces[index].lowercased()
            guard key == "w" || key == "h" else { continue }
            let nextIndex = pieces.index(after: index)
            guard nextIndex < pieces.endIndex,
                  let value = Int(pieces[nextIndex]),
                  value > 0
            else { continue }
            pixelLengths.append(value)
        }
        guard let maxSide = pixelLengths.max() else { return nil }
        let bucket = 160
        return ((maxSide + bucket - 1) / bucket) * bucket
    }

    private func biliImageView2URL(width: Int, height: Int) -> String {
        let base = biliImageBaseURL()
        return "\(base)?imageView2/2/w/\(width)/h/\(height)/format/webp"
    }

    private static func biliThumbnailPixelLength(
        _ points: CGFloat,
        scale: CGFloat,
        minimum: Int = 96,
        maximum: Int
    ) -> Int {
        let scaled = Int(ceil(Swift.max(points, 1) * Swift.max(scale, 1)))
        let bucket = 16
        let bucketed = ((scaled + bucket - 1) / bucket) * bucket
        return Swift.min(Swift.max(bucketed, minimum), maximum)
    }

    private func biliImageBaseURL() -> String {
        let queryStart = firstIndex(of: "?") ?? endIndex
        var base = String(self[..<queryStart])
        let lastSlash = base.lastIndex(of: "/") ?? base.startIndex
        if let suffixStart = base[lastSlash...].firstIndex(of: "@") {
            base = String(base[..<suffixStart])
        }
        return base
    }

    func removingHTMLTags() -> String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}

extension KeyedDecodingContainer {
    nonisolated func decodeLossyIntIfPresent(forKey key: Key) -> Int? {
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

    nonisolated func decodeLossyDoubleIfPresent(forKey key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return Double(value)
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Double(value)
        }
        return nil
    }

    nonisolated func decodeLossyStringIfPresent(forKey key: Key) -> String? {
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

    nonisolated func decodeLossyBoolIfPresent(forKey key: Key) -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value != 0
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            switch value.lowercased() {
            case "true", "1", "yes":
                return true
            case "false", "0", "no":
                return false
            default:
                return nil
            }
        }
        return nil
    }
}

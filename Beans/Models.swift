import Foundation

/// 音质等级。
enum BeansAudioQuality: String, CaseIterable, Identifiable {
    case standard
    case higher
    case exhigh
    case lossless
    case hires
    case master

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return beansLocalized("标准", "Standard")
        case .higher: return beansLocalized("更高", "Higher")
        case .exhigh: return beansLocalized("极高", "Very High")
        case .lossless: return beansLocalized("无损", "Lossless")
        case .hires: return "Hi-Res"
        case .master: return "Master"
        }
    }

    /// 网易云 songURL 的 level 参数
    var level: String {
        switch self {
        case .master:
            return "jymaster"
        default:
            return rawValue
        }
    }

    /// 当前官方播放音质（默认 Hi-Res；服务端不可用时由各平台接口自行降级）。
    static var current: BeansAudioQuality {
        let raw = UserDefaults.standard.string(forKey: "beans.audioQuality") ?? Self.hires.rawValue
        return BeansAudioQuality(rawValue: raw) ?? .hires
    }
}

/// 第三方音源音质。
enum ThirdPartyAudioQuality: String, CaseIterable, Identifiable, Sendable {
    case kb128 = "128k"
    case kb320 = "320k"
    case flac = "flac"
    case flac24bit = "flac24bit"
    case hires = "hires"
    case atmos = "atmos"
    case atmosPlus = "atmos_plus"
    case master = "master"

    static let storageKey = "beans.thirdPartyAudioQuality"
    static let downloadStorageKey = "beans.downloadAudioQuality"

    var id: String { rawValue }

    /// 兼容第三方脚本常见的音质别名（例如 24bit / lossless）。
    init?(sourceValue: String) {
        let normalized = sourceValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch normalized {
        case "128", "128k", "low", "standard": self = .kb128
        case "320", "320k", "high", "exhigh": self = .kb320
        case "flac", "lossless": self = .flac
        case "24bit", "flac24", "flac24bit", "hires24": self = .flac24bit
        case "hires", "highres", "high-resolution": self = .hires
        case "atmos", "dolby": self = .atmos
        case "atmosplus", "atmos_plus", "dolbyplus": self = .atmosPlus
        case "master", "masterquality": self = .master
        default: return nil
        }
    }

    var displayName: String {
        switch self {
        case .kb128: return beansLocalized("128k", "128k")
        case .kb320: return beansLocalized("320k", "320k")
        case .flac: return beansLocalized("无损 FLAC", "FLAC")
        case .flac24bit: return beansLocalized("FLAC 24 位", "FLAC 24-bit")
        case .hires: return beansLocalized("Hi-Res", "Hi-Res")
        case .atmos: return beansLocalized("Atmos", "Atmos")
        case .atmosPlus: return beansLocalized("Atmos+", "Atmos+")
        case .master: return beansLocalized("Master", "Master")
        }
    }

    /// 当前第三方音源优先音质。
    static var current: ThirdPartyAudioQuality {
        UserDefaults.standard.string(forKey: storageKey)
            .flatMap { ThirdPartyAudioQuality(sourceValue: $0) } ?? .kb320
    }

    /// 下载使用的独立音质设置，默认保持 320k 以兼容旧版本。
    static var downloadCurrent: ThirdPartyAudioQuality {
        UserDefaults.standard.string(forKey: downloadStorageKey)
            .flatMap { ThirdPartyAudioQuality(sourceValue: $0) } ?? .kb320
    }

    /// 按第三方接口的平台代码返回可用档位。
    static func supported(providerCode: String) -> [ThirdPartyAudioQuality] {
        switch providerCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "kw", "mg":
            return [.kb128, .kb320, .flac, .flac24bit, .hires]
        case "kg":
            return [.kb128, .kb320, .flac, .flac24bit, .hires, .atmos, .master]
        case "tx":
            return allCases
        case "wy":
            return [.kb128, .kb320, .flac, .flac24bit, .hires, .atmos, .master]
        case "git":
            return [.kb128, .kb320, .flac]
        default:
            return allCases
        }
    }

    static func supported(for source: SongSource) -> [ThirdPartyAudioQuality] {
        switch source {
        case .netease: return supported(providerCode: "wy")
        case .qq: return supported(providerCode: "tx")
        case .kugou: return supported(providerCode: "kg")
        case .kuwo: return supported(providerCode: "kw")
        case .migu: return supported(providerCode: "mg")
        }
    }

    /// 从高到低的降级链。
    var fallbackChain: [ThirdPartyAudioQuality] {
        switch self {
        case .kb128:
            return [.kb128]
        case .kb320:
            return [.kb320, .kb128]
        case .flac:
            return [.flac, .kb320, .kb128]
        case .flac24bit:
            return [.flac24bit, .flac, .kb320, .kb128]
        case .hires:
            return [.hires, .flac24bit, .flac, .kb320, .kb128]
        case .atmos:
            return [.atmos, .hires, .flac24bit, .flac, .kb320, .kb128]
        case .atmosPlus:
            return [.atmosPlus, .atmos, .hires, .flac24bit, .flac, .kb320, .kb128]
        case .master:
            return [.master, .atmosPlus, .atmos, .hires, .flac24bit, .flac, .kb320, .kb128]
        }
    }
}

/// 歌曲来源
enum SongSource: String, Codable, Sendable, CaseIterable {
    case netease
    case qq
    case kugou
    case kuwo
    case migu

    /// 兼容旧版本地收藏：未知或已下线来源统一回退为网易云
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SongSource(rawValue: raw) ?? .netease
    }
}

enum FavoriteMark: Equatable {
    case none
    case local
    case official
    case both

    var isLiked: Bool {
        self != .none
    }
}

enum FavoriteDestination: String, CaseIterable, Identifiable {
    case local
    case official

    var id: String { rawValue }

    var title: String {
        switch self {
        case .local: return "本地收藏"
        case .official: return "官方歌单"
        }
    }
}

/// 决定播放器优先使用官方地址还是用户已启用的第三方音源。
/// 自动模式保留原有体验：官方地址可用时优先官方，失败后再解析第三方音源。
enum PlaybackSourcePreference: String, CaseIterable, Identifiable {
    case automatic
    case official
    case thirdParty

    static let storageKey = "beans.playback.sourcePreference"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "自动"
        case .official: return "官方"
        case .thirdParty: return "第三方"
        }
    }

    var detail: String {
        switch self {
        case .automatic: return "优先官方，失败后尝试已启用音源"
        case .official: return "只使用当前平台官方播放地址"
        case .thirdParty: return "只使用已启用的第三方音源"
        }
    }

    static var current: PlaybackSourcePreference {
        UserDefaults.standard.string(forKey: storageKey)
            .flatMap(PlaybackSourcePreference.init(rawValue:)) ?? .automatic
    }
}

struct Song: Identifiable, Hashable, Codable {
    let id: Int
    let name: String
    let artists: String
    let album: String
    let coverURL: URL?
    let duration: TimeInterval
    /// 歌曲来源（网易云 / QQ音乐）
    let source: SongSource
    /// QQ 音乐 songmid（source == .qq 时用于获取播放地址与歌词）
    let qqMid: String?
    /// QQ 音乐音频文件 media_mid；部分歌曲与 songmid 不同，取 vkey 时必须优先使用
    let qqMediaMid: String?
    /// 酷狗音乐文件 hash 与专辑音频 id（source == .kugou 时用于获取播放地址与歌词）
    let kugouHash: String?
    let kugouAlbumAudioId: String?
    let kugouAlbumId: String?
    let kugouQualityHashes: [String: String]?
    /// 咪咕歌词接口使用的版权资源标识，和展示歌曲 ID 在部分曲目中并不相同。
    let miguCopyrightId: String?
    /// 咪咕搜索结果直接提供的歌词地址，优先于再次查询资源详情。
    let miguLyricURL: URL?
    /// 付费/VIP 标记（网易云：0 免费、1 VIP、4 付费单曲；QQ：0 免费、非 0 付费）
    let fee: Int

    var formattedDuration: String {
        let total = max(0, Int(duration))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var officialURL: URL? {
        switch source {
        case .netease:
            return URL(string: "https://music.163.com/#/song?id=\(id)")
        case .qq:
            let identifier = qqMid?.isEmpty == false ? qqMid! : String(id)
            return URL(string: "https://y.qq.com/n/ryqq/songDetail/\(identifier)")
        case .kugou:
            guard let hash = kugouHash?.trimmingCharacters(in: .whitespacesAndNewlines), !hash.isEmpty else {
                return nil
            }
            return URL(string: "https://www.kugou.com/song/#hash=\(hash)")
        case .kuwo:
            return URL(string: "https://www.kuwo.cn/play_detail/\(id)")
        case .migu:
            return URL(string: "https://music.migu.cn/v3/music/song/\(id)")
        }
    }

    /// 跨平台唯一标识（避免网易云与 QQ 音乐歌曲 id 撞车）
    var identityKey: String {
        switch source {
        case .qq: return "qq-\(id)"
        case .kugou: return "kugou-\(id)"
        case .kuwo: return "kuwo-\(id)"
        case .migu: return "migu-\(id)"
        case .netease: return "netease-\(id)"
        }
    }

    /// 是否为 VIP / 付费歌曲（用于列表与播放器角标）
    /// 网易云 fee：0 免费、1 VIP、4 付费单曲；8 为翻唱/免费资源，不视为 VIP
    /// QQ payplay：0 免费，非 0 需要会员/付费
    var isVIP: Bool {
        switch source {
        case .netease:
            return fee == 1 || fee == 4
        case .qq:
            return fee != 0
        case .kugou:
            return fee != 0
        case .kuwo, .migu:
            return fee != 0
        }
    }

    init(id: Int, name: String, artists: String, album: String, coverURL: URL?, duration: TimeInterval, source: SongSource = .netease, qqMid: String? = nil, qqMediaMid: String? = nil, kugouHash: String? = nil, kugouAlbumAudioId: String? = nil, kugouAlbumId: String? = nil, kugouQualityHashes: [String: String]? = nil, miguCopyrightId: String? = nil, miguLyricURL: URL? = nil, fee: Int = 0) {
        self.id = id
        self.name = name
        self.artists = artists
        self.album = album
        self.coverURL = coverURL
        self.duration = duration
        self.source = source
        self.qqMid = qqMid
        self.qqMediaMid = qqMediaMid
        self.kugouHash = kugouHash
        self.kugouAlbumAudioId = kugouAlbumAudioId
        self.kugouAlbumId = kugouAlbumId
        self.kugouQualityHashes = kugouQualityHashes
        self.miguCopyrightId = miguCopyrightId
        self.miguLyricURL = miguLyricURL
        self.fee = fee
    }

    init?(json: [String: Any]) {
        guard let id = json["id"] as? Int else { return nil }
        self.id = id
        name = json["name"] as? String ?? ""
        let artistsArray = json["artists"] as? [[String: Any]] ?? (json["ar"] as? [[String: Any]]) ?? []
        artists = artistsArray.compactMap { $0["name"] as? String }.joined(separator: " / ")
        if let albumDict = json["album"] as? [String: Any] {
            album = albumDict["name"] as? String ?? ""
            let pic = albumDict["picUrl"] as? String ?? (albumDict["blurPicUrl"] as? String ?? "")
            coverURL = pic.isEmpty ? nil : URL(string: pic)
        } else if let al = json["al"] as? [String: Any] {
            album = al["name"] as? String ?? ""
            let pic = al["picUrl"] as? String ?? ""
            coverURL = pic.isEmpty ? nil : URL(string: pic)
        } else {
            album = ""
            coverURL = nil
        }
        let ms = json["duration"] as? Int ?? (json["dt"] as? Int) ?? 0
        duration = Double(ms) / 1000.0
        source = .netease
        qqMid = nil
        qqMediaMid = nil
        kugouHash = nil
        kugouAlbumAudioId = nil
        kugouAlbumId = nil
        kugouQualityHashes = nil
        miguCopyrightId = nil
        miguLyricURL = nil
        fee = json["fee"] as? Int ?? 0
    }

    private enum CodingKeys: String, CodingKey { case id, name, artists, album, coverURL, duration, source, qqMid, qqMediaMid, kugouHash, kugouAlbumAudioId, kugouAlbumId, kugouQualityHashes, miguCopyrightId, miguLyricURL, fee }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        artists = try c.decodeIfPresent(String.self, forKey: .artists) ?? ""
        album = try c.decodeIfPresent(String.self, forKey: .album) ?? ""
        coverURL = try c.decodeIfPresent(URL.self, forKey: .coverURL)
        duration = try c.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
        source = try c.decodeIfPresent(SongSource.self, forKey: .source) ?? .netease
        qqMid = try c.decodeIfPresent(String.self, forKey: .qqMid)
        qqMediaMid = try c.decodeIfPresent(String.self, forKey: .qqMediaMid)
        kugouHash = try c.decodeIfPresent(String.self, forKey: .kugouHash)
        kugouAlbumAudioId = try c.decodeIfPresent(String.self, forKey: .kugouAlbumAudioId)
        kugouAlbumId = try c.decodeIfPresent(String.self, forKey: .kugouAlbumId)
        kugouQualityHashes = try c.decodeIfPresent([String: String].self, forKey: .kugouQualityHashes)
        miguCopyrightId = try c.decodeIfPresent(String.self, forKey: .miguCopyrightId)
        miguLyricURL = try c.decodeIfPresent(URL.self, forKey: .miguLyricURL)
        fee = try c.decodeIfPresent(Int.self, forKey: .fee) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(artists, forKey: .artists)
        try c.encode(album, forKey: .album)
        try c.encodeIfPresent(coverURL, forKey: .coverURL)
        try c.encode(duration, forKey: .duration)
        try c.encode(source, forKey: .source)
        try c.encodeIfPresent(qqMid, forKey: .qqMid)
        try c.encodeIfPresent(qqMediaMid, forKey: .qqMediaMid)
        try c.encodeIfPresent(kugouHash, forKey: .kugouHash)
        try c.encodeIfPresent(kugouAlbumAudioId, forKey: .kugouAlbumAudioId)
        try c.encodeIfPresent(kugouAlbumId, forKey: .kugouAlbumId)
        try c.encodeIfPresent(kugouQualityHashes, forKey: .kugouQualityHashes)
        try c.encodeIfPresent(miguCopyrightId, forKey: .miguCopyrightId)
        try c.encodeIfPresent(miguLyricURL, forKey: .miguLyricURL)
        try c.encode(fee, forKey: .fee)
    }
}

/// 歌手搜索结果（网易云 / QQ音乐通用）
struct Artist: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let coverURL: URL?
    let source: SongSource
}

/// 专辑搜索结果（网易云 / QQ音乐通用）
struct Album: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let artistName: String
    let coverURL: URL?
    let source: SongSource
    var trackCount: Int?
    /// 平台返回的发行类型，例如 Album / EP / Single。缺失时按曲目数降级判断。
    var releaseType: String? = nil
    /// 统一为 `yyyy-MM-dd` 的发行日期，供歌手页及专辑详情的专辑卡片展示。
    var releaseDate: String? = nil

    var isEPOrSingle: Bool {
        let normalized = releaseType?
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased() ?? ""
        if normalized.contains("ep") || normalized.contains("single") || normalized.contains("单曲") {
            return true
        }
        return trackCount == 1
    }

    var releaseCaption: String {
        if let releaseDate, !releaseDate.isEmpty { return releaseDate }
        if let releaseType, !releaseType.isEmpty { return releaseType }
        return trackCount.map(beansSongCountText) ?? ""
    }

    static func releaseDateText(from rawValue: Any?) -> String? {
        guard let rawValue else { return nil }
        if let number = rawValue as? NSNumber {
            let timestamp = number.doubleValue
            guard timestamp > 0 else { return nil }
            let seconds = timestamp > 10_000_000_000 ? timestamp / 1_000 : timestamp
            return releaseDateString(timestamp: seconds)
        }
        guard let text = rawValue as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let timestamp = Double(trimmed), timestamp > 10_000_000_000 {
            return releaseDateString(timestamp: timestamp / 1_000)
        }
        if let match = trimmed.range(of: #"\d{4}[-./]\d{1,2}[-./]\d{1,2}"#, options: .regularExpression) {
            return String(trimmed[match])
                .replacingOccurrences(of: ".", with: "-")
                .replacingOccurrences(of: "/", with: "-")
        }
        if let match = trimmed.range(of: #"\d{4}-\d{1,2}"#, options: .regularExpression) {
            return String(trimmed[match])
        }
        return trimmed.count == 4 && trimmed.allSatisfy(\.isNumber) ? trimmed : nil
    }

    private static func releaseDateString(timestamp: TimeInterval) -> String? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let components = calendar.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: timestamp))
        guard let year = components.year, let month = components.month, let day = components.day else { return nil }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}

struct Playlist: Identifiable, Hashable, Codable {
    let id: Int
    let name: String
    var coverURL: URL?
    let trackCount: Int
    let playCount: Int
    let creatorName: String
    let creatorAvatarURL: URL?
    let playlistDescription: String
    let specialType: Int
    /// 酷狗新版歌单接口使用的 global_collection_id，和本地展示用的数字 listid 可能不同。
    let kugouGlobalCollectionID: String?
    /// 歌单来源（网易云 / QQ音乐），非网易云歌单用对应接口加载
    let source: SongSource

    init(id: Int, name: String, coverURL: URL?, trackCount: Int = 0, playCount: Int = 0, creatorName: String = "", creatorAvatarURL: URL? = nil, playlistDescription: String = "", source: SongSource = .netease, kugouGlobalCollectionID: String? = nil) {
        self.id = id
        self.name = name
        self.coverURL = coverURL
        self.trackCount = trackCount
        self.playCount = playCount
        self.creatorName = creatorName
        self.creatorAvatarURL = creatorAvatarURL
        self.playlistDescription = playlistDescription
        self.specialType = 0
        self.kugouGlobalCollectionID = kugouGlobalCollectionID
        self.source = source
    }

    init?(json: [String: Any]) {
        guard let id = json["id"] as? Int else { return nil }
        self.id = id
        name = json["name"] as? String ?? ""
        trackCount = json["trackCount"] as? Int ?? 0
        playCount = json["playCount"] as? Int ?? 0
        let pic = json["coverImgUrl"] as? String ?? json["picUrl"] as? String ?? ""
        coverURL = pic.isEmpty ? nil : URL(string: pic)
        let creator = json["creator"] as? [String: Any] ?? [:]
        creatorName = creator["nickname"] as? String ?? ""
        let avatar = creator["avatarUrl"] as? String ?? creator["avatarURL"] as? String ?? creator["avatar"] as? String ?? ""
        creatorAvatarURL = avatar.isEmpty ? nil : URL(string: avatar)
        playlistDescription = json["description"] as? String ?? json["desc"] as? String ?? ""
        specialType = json["specialType"] as? Int ?? 0
        kugouGlobalCollectionID = nil
        source = .netease
    }

    init?(personalizedJSON json: [String: Any]) {
        guard let id = json["id"] as? Int else { return nil }
        self.id = id
        name = json["name"] as? String ?? ""
        trackCount = 0
        playCount = json["playCount"] as? Int ?? 0
        let pic = json["picUrl"] as? String ?? ""
        coverURL = pic.isEmpty ? nil : URL(string: pic)
        let creator = json["creator"] as? [String: Any] ?? [:]
        creatorName = creator["nickname"] as? String ?? ""
        let avatar = creator["avatarUrl"] as? String ?? creator["avatarURL"] as? String ?? creator["avatar"] as? String ?? ""
        creatorAvatarURL = avatar.isEmpty ? nil : URL(string: avatar)
        playlistDescription = json["description"] as? String ?? ""
        specialType = json["specialType"] as? Int ?? 0
        kugouGlobalCollectionID = nil
        source = .netease
    }

    var isNetEaseLikedPlaylist: Bool {
        source == .netease && (specialType == 5 || name == "我喜欢的音乐" || name.localizedCaseInsensitiveContains("liked songs"))
    }
}

struct TopList: Identifiable, Hashable, Codable {
    let id: Int
    let name: String
    let coverURL: URL?
    let updateFrequency: String

    init?(json: [String: Any]) {
        guard let id = json["id"] as? Int else { return nil }
        self.id = id
        name = json["name"] as? String ?? ""
        let pic = json["coverImgUrl"] as? String ?? ""
        coverURL = pic.isEmpty ? nil : URL(string: pic)
        updateFrequency = json["updateFrequency"] as? String ?? ""
    }
}

/// QQ 峰尖榜总览项
struct QQTopInfo: Identifiable, Hashable, Codable {
    let id: Int
    let name: String
    let subTitle: String
    let topSongNames: [String]
    let coverURL: URL?
}

/// 酷狗官方排行榜总览项
struct KugouTopInfo: Identifiable, Hashable, Codable {
    let id: Int
    let name: String
    let updateFrequency: String
    let coverURL: URL?
}

struct LyricWord: Hashable, Codable {
    let text: String
    let start: Double
    let duration: Double
}

enum LyricKaraokeTiming {
    static func opacity(for word: LyricWord, at time: TimeInterval) -> Double {
        let fraction = min(max((time - word.start) / max(word.duration, 0.001), 0), 1)
        return 0.28 + fraction * 0.72
    }
}

enum LyricWordFormat: String, Codable {
    case neteaseYRC
    case qqQRC
    case kugouKRC
}

struct LyricLine: Identifiable, Hashable {
    let id: UUID
    let time: Double
    let text: String
    /// 歌词翻译（网易云 tlyric，可空）
    var translation: String?
    /// 可选的真实逐字时间轴；旧 LRC 缓存没有此字段时保持 nil。
    var words: [LyricWord]?

    init(time: Double, text: String, translation: String? = nil, words: [LyricWord]? = nil) {
        self.id = UUID()
        self.time = time
        self.text = text
        self.translation = translation
        self.words = words
    }
}

enum LyricParser {
    /// 解析普通 LRC，并可合并平台提供的逐字歌词文本。
    static func parse(
        _ raw: String,
        translationRaw: String? = nil,
        wordRaw: String? = nil,
        wordFormat: LyricWordFormat? = nil
    ) -> [LyricLine] {
        var lines = parseCore(raw, offset: declaredOffsetSeconds(in: raw))
        if let wordRaw, let wordFormat {
            let timed = parseWordLines(wordRaw, format: wordFormat)
            if !timed.isEmpty {
                if lines.isEmpty {
                    lines = timed
                } else {
                    for index in lines.indices {
                        guard let match = timed.min(by: { abs($0.time - lines[index].time) < abs($1.time - lines[index].time) }),
                              abs(match.time - lines[index].time) < 0.35 else { continue }
                        lines[index].words = match.words
                    }
                }
            }
        }
        mergeTranslation(&lines, raw: translationRaw)
        return lines
    }

    /// 解析歌词；可选传入翻译歌词（网易云 tlyric），按时间戳合并到对应行
    static func parse(_ raw: String, translationRaw: String? = nil) -> [LyricLine] {
        parse(raw, translationRaw: translationRaw, wordRaw: nil, wordFormat: nil)
    }

    private static func mergeTranslation(_ lines: inout [LyricLine], raw: String?) {
        guard let raw, !raw.isEmpty else { return }
        let trans = parseCore(raw, offset: declaredOffsetSeconds(in: raw))
        for i in lines.indices {
            if let match = trans.min(by: { abs($0.time - lines[i].time) < abs($1.time - lines[i].time) }),
               abs(match.time - lines[i].time) < 0.35, !match.text.isEmpty {
                lines[i].translation = match.text
            }
        }
    }

    private static func parseWordLines(_ raw: String, format: LyricWordFormat) -> [LyricLine] {
        let scale: Double = 0.001
        var result: [LyricLine] = []
        let linePattern = #"\[(\d+),(\d+)\]"#
        guard let lineRegex = try? NSRegularExpression(pattern: linePattern) else { return [] }
        for rawLine in raw.components(separatedBy: .newlines) {
            let nsRange = NSRange(rawLine.startIndex..., in: rawLine)
            guard let lineMatch = lineRegex.firstMatch(in: rawLine, range: nsRange),
                  let startRange = Range(lineMatch.range(at: 1), in: rawLine),
                  let durationRange = Range(lineMatch.range(at: 2), in: rawLine),
                  let lineStart = Double(rawLine[startRange]),
                  let lineDuration = Double(rawLine[durationRange]) else { continue }
            let contentStart = rawLine.index(rawLine.startIndex, offsetBy: lineMatch.range.upperBound)
            let content = String(rawLine[contentStart...])
            let markerPattern = format == .kugouKRC
                ? #"<(\d+),(\d+)(?:,\d+)?>"#
                : #"\((\d+),(\d+)(?:,\d+)?\)"#
            guard let markerRegex = try? NSRegularExpression(pattern: markerPattern) else { continue }
            let markers = markerRegex.matches(in: content, range: NSRange(content.startIndex..., in: content))
            guard !markers.isEmpty else { continue }
            var words: [LyricWord] = []
            for (index, marker) in markers.enumerated() {
                guard let startRange = Range(marker.range(at: 1), in: content),
                      let durationRange = Range(marker.range(at: 2), in: content),
                      let wordStart = Double(content[startRange]),
                      let wordDuration = Double(content[durationRange]) else { continue }
                let textStart = content.index(content.startIndex, offsetBy: marker.range.upperBound)
                let textEnd: String.Index = index + 1 < markers.count
                    ? content.index(content.startIndex, offsetBy: markers[index + 1].range.location)
                    : content.endIndex
                guard textStart <= textEnd else { continue }
                let text = String(content[textStart..<textEnd])
                let absoluteStart = format == .kugouKRC
                    ? lineStart * scale + wordStart * scale
                    : wordStart * scale
                words.append(LyricWord(text: text, start: absoluteStart, duration: max(wordDuration * scale, 0.001)))
            }
            let text = words.map(\.text).joined()
            if !text.isEmpty {
                result.append(LyricLine(time: lineStart * scale, text: text, words: words))
            } else if lineDuration > 0 {
                result.append(LyricLine(time: lineStart * scale, text: " "))
            }
        }
        return result.sorted { $0.time < $1.time }
    }

    private static func parseCore(_ raw: String, offset: Double) -> [LyricLine] {
        var lines: [LyricLine] = []
        for line in raw.components(separatedBy: .newlines) {
            parseTimes(in: line).forEach { time in
                let text = line.replacingOccurrences(of: #"\[\d{2}:\d{2}(\.\d{1,3})?\]"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                lines.append(LyricLine(time: max(0, time + offset), text: text))
            }
        }
        return lines.sorted { $0.time < $1.time }
    }

    private static func declaredOffsetSeconds(in raw: String) -> Double {
        let pattern = #"\[offset:([+-]?\d+)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              let range = Range(match.range(at: 1), in: raw),
              let milliseconds = Double(raw[range]) else {
            return 0
        }
        return milliseconds / 1000.0
    }

    private static func parseTimes(in line: String) -> [Double] {
        var times: [Double] = []
        let pattern = #"\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(line.startIndex..., in: line)
        regex?.enumerateMatches(in: line, options: [], range: range) { match, _, _ in
            guard let match else { return }
            guard let minuteRange = Range(match.range(at: 1), in: line),
                  let secondRange = Range(match.range(at: 2), in: line) else { return }
            let minutes = Double(line[minuteRange]) ?? 0
            let seconds = Double(line[secondRange]) ?? 0
            var fraction = 0.0
            if match.numberOfRanges > 3, let fracRange = Range(match.range(at: 3), in: line) {
                let raw = String(line[fracRange])
                fraction = (Double(raw) ?? 0) / pow(10, Double(max(raw.count, 1)))
            }
            times.append(minutes * 60 + seconds + fraction)
        }
        return times
    }
}

enum LyricTiming {
    static let userOffsetKey = "beans.lyricOffset"

    static func effectiveProgress(_ progress: Double, userOffset: Double? = nil) -> Double {
        let offset = userOffset ?? UserDefaults.standard.double(forKey: userOffsetKey)
        return max(0, progress + offset)
    }

    static func seekTime(for line: LyricLine, userOffset: Double? = nil) -> Double {
        let offset = userOffset ?? UserDefaults.standard.double(forKey: userOffsetKey)
        return max(0, line.time - offset)
    }
}

struct NetEaseUser: Identifiable, Hashable, Codable {
    let uid: Int
    let nickname: String
    let avatarURL: URL?
    /// 网易云会员类型：0 无会员；非 0 有 VIP；>= 11 为黑胶 SVIP（接口字段 profile.vipType）
    let vipType: Int

    var id: Int { uid }

    /// VIP 标识：nil 表示无会员
    var vipBadge: String? {
        if vipType >= 11 { return "SVIP" }
        if vipType > 0 { return "VIP" }
        return nil
    }

    init?(json: [String: Any]) {
        guard let id = json["userId"] as? Int ?? (json["id"] as? Int) else { return nil }
        uid = id
        nickname = json["nickname"] as? String ?? ""
        let pic = json["avatarUrl"] as? String ?? ""
        avatarURL = pic.isEmpty ? nil : URL(string: pic)
        vipType = json["vipType"] as? Int ?? 0
    }

    enum CodingKeys: String, CodingKey { case uid, nickname, avatarURL, vipType }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uid = try c.decode(Int.self, forKey: .uid)
        nickname = try c.decode(String.self, forKey: .nickname)
        avatarURL = try c.decodeIfPresent(URL.self, forKey: .avatarURL)
        vipType = try c.decodeIfPresent(Int.self, forKey: .vipType) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(uid, forKey: .uid)
        try c.encode(nickname, forKey: .nickname)
        try c.encodeIfPresent(avatarURL, forKey: .avatarURL)
        try c.encode(vipType, forKey: .vipType)
    }
}
/// 听歌排行条目（网易云听歌记录）
struct PlayRecordItem: Identifiable, Hashable {
    let song: Song
    let playCount: Int
    var id: Int { song.id }
}

/// 听歌排行结果（列表 + 真实总数，避免被接口单次上限截断）
struct PlayRecordResult {
    let items: [PlayRecordItem]
    let totalCount: Int
}

// MARK: - 歌曲评论

struct SongComment: Identifiable, Hashable {
    let id: Int
    let content: String
    let nickname: String
    let avatarURL: URL?
    let time: Date
    let likedCount: Int
    let isHot: Bool

    init(id: Int, content: String, nickname: String, avatarURL: URL?, time: Date, likedCount: Int, isHot: Bool = false) {
        self.id = id
        self.content = content
        self.nickname = nickname
        self.avatarURL = avatarURL
        self.time = time
        self.likedCount = likedCount
        self.isHot = isHot
    }

    init?(json: [String: Any], isHot: Bool = false) {
        guard let id = json["commentId"] as? Int else { return nil }
        self.id = id
        content = json["content"] as? String ?? ""
        let user = json["user"] as? [String: Any]
        nickname = user?["nickname"] as? String ?? ""
        let avatar = user?["avatarUrl"] as? String ?? ""
        avatarURL = avatar.isEmpty ? nil : URL(string: avatar)
        let ms = json["time"] as? Int ?? 0
        time = Date(timeIntervalSince1970: Double(ms) / 1000.0)
        likedCount = json["likedCount"] as? Int ?? 0
        self.isHot = isHot
    }
}

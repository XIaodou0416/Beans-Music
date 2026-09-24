import Foundation

nonisolated struct LiveRecommendData: Decodable {
    let recommendRoomList: [LiveRoom]?

    enum CodingKeys: String, CodingKey {
        case recommendRoomList = "recommend_room_list"
    }
}

nonisolated struct LiveAreaGroup: Identifiable, Decodable, Hashable {
    let id: Int
    let name: String
    let children: [LiveArea]

    enum CodingKeys: String, CodingKey {
        case id, name
        case children = "list"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeLossyIntIfPresent(forKey: .id) ?? 0
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "未知"
        children = try container.decodeIfPresent([LiveArea].self, forKey: .children) ?? []
    }
}

nonisolated struct LiveArea: Identifiable, Decodable, Hashable {
    let id: Int
    let parentID: Int
    let name: String
    let parentName: String?
    let pic: String?

    enum CodingKeys: String, CodingKey {
        case id, name, pic
        case parentID = "parent_id"
        case parentName = "parent_name"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeLossyIntIfPresent(forKey: .id) ?? 0
        parentID = container.decodeLossyIntIfPresent(forKey: .parentID) ?? 0
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "未知"
        parentName = try container.decodeIfPresent(String.self, forKey: .parentName)
        pic = try container.decodeIfPresent(String.self, forKey: .pic)
    }
}

nonisolated struct LiveRoom: Identifiable, Decodable, Hashable {
    var id: Int { roomID }

    let roomID: Int
    let title: String
    let uname: String
    let uid: Int?
    let face: String?
    let cover: String?
    let keyframe: String?
    let online: Int?
    let areaName: String?
    let parentAreaName: String?
    let liveStatus: Int?

    init(
        roomID: Int,
        title: String,
        uname: String,
        uid: Int?,
        face: String?,
        cover: String?,
        keyframe: String?,
        online: Int?,
        areaName: String?,
        parentAreaName: String?,
        liveStatus: Int?
    ) {
        self.roomID = roomID
        self.title = title
        self.uname = uname
        self.uid = uid
        self.face = face
        self.cover = cover
        self.keyframe = keyframe
        self.online = online
        self.areaName = areaName
        self.parentAreaName = parentAreaName
        self.liveStatus = liveStatus
    }

    enum CodingKeys: String, CodingKey {
        case title, uname, uid, face, cover, keyframe, online
        case roomID = "roomid"
        case roomIDAlt = "room_id"
        case liveStatus = "live_status"
        case areaName = "area_v2_name"
        case parentAreaName = "area_v2_parent_name"
        case areaNameAlt = "area_name"
        case parentAreaNameAlt = "parent_area_name"
        case parentAreaNameV2 = "parent_area_v2_name"
        case userCover = "user_cover"
        case systemCover = "system_cover"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        roomID =
            container.decodeLossyIntIfPresent(forKey: .roomID)
            ?? container.decodeLossyIntIfPresent(forKey: .roomIDAlt)
            ?? 0
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Untitled"
        uname = try container.decodeIfPresent(String.self, forKey: .uname) ?? "Unknown"
        uid = container.decodeLossyIntIfPresent(forKey: .uid)
        face = try container.decodeIfPresent(String.self, forKey: .face)
        cover =
            try container.decodeIfPresent(String.self, forKey: .cover)
            ?? container.decodeIfPresent(String.self, forKey: .userCover)
        keyframe =
            try container.decodeIfPresent(String.self, forKey: .keyframe)
            ?? container.decodeIfPresent(String.self, forKey: .systemCover)
        online = container.decodeLossyIntIfPresent(forKey: .online)
        liveStatus = container.decodeLossyIntIfPresent(forKey: .liveStatus)
        areaName =
            try container.decodeIfPresent(String.self, forKey: .areaName)
            ?? container.decodeIfPresent(String.self, forKey: .areaNameAlt)
        parentAreaName =
            try container.decodeIfPresent(String.self, forKey: .parentAreaName)
            ?? container.decodeIfPresent(String.self, forKey: .parentAreaNameV2)
            ?? container.decodeIfPresent(String.self, forKey: .parentAreaNameAlt)
    }

    var displayCover: String? {
        coverCandidates.first
    }

    var coverCandidates: [String] {
        var seen = Set<String>()
        var result = [String]()
        for candidate in [keyframe, cover] {
            let normalized =
                candidate?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .normalizedBiliURL() ?? ""
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
            result.append(normalized)
        }
        return result
    }

    var isLive: Bool {
        liveStatus == nil || liveStatus == 1
    }

    var anchorOwner: VideoOwner {
        VideoOwner(mid: uid ?? 0, name: uname, face: face?.normalizedBiliURL())
    }
}

nonisolated struct LiveRoomInfo: Decodable, Hashable {
    let roomID: Int
    let uid: Int?
    let title: String
    let userCover: String?
    let keyframe: String?
    let description: String?
    let liveStatus: Int?
    let online: Int?
    let areaName: String?
    let parentAreaName: String?
    let liveTime: String?

    enum CodingKeys: String, CodingKey {
        case uid, title, keyframe, description, online
        case roomID = "room_id"
        case userCover = "user_cover"
        case liveStatus = "live_status"
        case areaName = "area_name"
        case parentAreaName = "parent_area_name"
        case liveTime = "live_time"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        roomID = container.decodeLossyIntIfPresent(forKey: .roomID) ?? 0
        uid = container.decodeLossyIntIfPresent(forKey: .uid)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Untitled"
        userCover = try container.decodeIfPresent(String.self, forKey: .userCover)
        keyframe = try container.decodeIfPresent(String.self, forKey: .keyframe)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        liveStatus = container.decodeLossyIntIfPresent(forKey: .liveStatus)
        online = container.decodeLossyIntIfPresent(forKey: .online)
        areaName = try container.decodeIfPresent(String.self, forKey: .areaName)
        parentAreaName = try container.decodeIfPresent(String.self, forKey: .parentAreaName)
        liveTime = try container.decodeIfPresent(String.self, forKey: .liveTime)
    }

    var displayCover: String? {
        keyframe ?? userCover
    }

    var isLive: Bool {
        liveStatus == 1
    }
}

nonisolated struct LiveRoomSummary: Decodable, Hashable {
    let roomID: Int
    let liveStatus: Int?
    let title: String?
    let cover: String?
    let online: Int?
    let link: String?

    enum CodingKeys: String, CodingKey {
        case title, cover, online, link
        case roomID = "roomid"
        case roomIDAlt = "room_id"
        case liveStatus = "liveStatus"
        case liveStatusAlt = "live_status"
        case roomStatus = "roomStatus"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        roomID =
            container.decodeLossyIntIfPresent(forKey: .roomID)
            ?? container.decodeLossyIntIfPresent(forKey: .roomIDAlt)
            ?? 0
        liveStatus =
            container.decodeLossyIntIfPresent(forKey: .liveStatus)
            ?? container.decodeLossyIntIfPresent(forKey: .liveStatusAlt)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        cover = try container.decodeIfPresent(String.self, forKey: .cover)
        online = container.decodeLossyIntIfPresent(forKey: .online)
        link = try container.decodeIfPresent(String.self, forKey: .link)
    }
}

nonisolated struct LivePlayInfoData: Decodable {
    let playurlInfo: LivePlayURLInfo?

    enum CodingKeys: String, CodingKey {
        case playurlInfo = "playurl_info"
    }

    var firstPlayableURL: URL? {
        playableURLCandidates.first?.url
    }

    var playableURLCandidates: [LiveStreamURLCandidate] {
        playurlInfo?.playurl?.stream?
            .playableURLCandidates(preferHLS: true) ?? []
    }

    var availableQualities: [LiveStreamQuality] {
        let described = playurlInfo?.playurl?.qualityDescriptions ?? []
        let accepted = playurlInfo?.playurl?.stream?.acceptedQualities ?? []
        return LiveStreamQuality.merged(described + accepted)
    }
}

nonisolated struct LiveRoomPlayURLData: Decodable {
    let durl: [LiveRoomPlayURLItem]?

    var firstURL: URL? {
        playableURLCandidates.first?.url
    }

    var playableURLCandidates: [LiveStreamURLCandidate] {
        (durl ?? []).compactMap { item in
            URL(string: item.url.normalizedBiliURL()).map {
                LiveStreamURLCandidate(
                    url: $0,
                    protocolName: "legacy",
                    formatName: $0.liveStreamFormatHint,
                    codecName: nil,
                    currentQN: nil,
                    qualityTitle: nil,
                    source: "legacy"
                )
            }
        }
    }
}

nonisolated struct LiveRoomPlayURLItem: Decodable {
    let url: String
}

nonisolated struct LiveStreamURLCandidate: Equatable, Hashable {
    let url: URL
    let protocolName: String?
    let formatName: String?
    let codecName: String?
    let currentQN: Int?
    let qualityTitle: String?
    let source: String

    var isLikelyHLS: Bool {
        protocolName?.localizedCaseInsensitiveContains("hls") == true
            || formatName?.localizedCaseInsensitiveContains("fmp4") == true
            || formatName?.localizedCaseInsensitiveContains("ts") == true
            || url.isLikelyHLSManifest
    }
}

nonisolated struct LiveStreamFetchResult: Equatable, Hashable {
    let candidates: [LiveStreamURLCandidate]
    let qualities: [LiveStreamQuality]

    var playableQualities: [LiveStreamQuality] {
        let derived = LiveStreamQuality.merged(
            candidates.compactMap { candidate in
                guard let qn = candidate.currentQN, qn > 0 else { return nil }
                return LiveStreamQuality(qn: qn, description: candidate.qualityTitle)
            }
        )
        return LiveStreamQuality.merged(qualities + derived)
    }
}

nonisolated struct LiveStreamQuality: Identifiable, Decodable, Equatable, Hashable {
    // Bilibili Live uses qn 400 for its 1080P blue-ray rendition.
    static let defaultPreferredQN = 400

    let qn: Int
    let description: String?

    var id: Int { qn }

    enum CodingKeys: String, CodingKey {
        case qn
        case description = "desc"
        case descriptionAlt = "description"
    }

    init(qn: Int, description: String?) {
        self.qn = qn
        self.description = description
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        qn = container.decodeLossyIntIfPresent(forKey: .qn) ?? 0
        description =
            container.decodeLossyStringIfPresent(forKey: .description)
            ?? container.decodeLossyStringIfPresent(forKey: .descriptionAlt)
    }

    var title: String {
        if let description, !description.isEmpty {
            return description
        }
        return Self.defaultTitle(for: qn)
    }

    static func defaultTitle(for qn: Int) -> String {
        switch qn {
        case 10000:
            return "原画"
        case 400:
            return "蓝光"
        case 250:
            return "超清"
        case 150:
            return "高清"
        case 80:
            return "流畅"
        default:
            return "清晰度 \(qn)"
        }
    }

    static func merged(_ values: [LiveStreamQuality]) -> [LiveStreamQuality] {
        var seen = Set<Int>()
        return
            values
            .filter { $0.qn > 0 }
            .sorted { $0.qn > $1.qn }
            .filter { seen.insert($0.qn).inserted }
    }
}

nonisolated struct LiveAnchorInfoData: Decodable, Hashable {
    let info: LiveAnchorProfile?
    let relationInfo: LiveAnchorRelationInfo?

    enum CodingKeys: String, CodingKey {
        case info
        case relationInfo = "relation_info"
    }
}

nonisolated struct LiveAnchorProfile: Decodable, Hashable {
    let uid: Int?
    let uname: String?
    let face: String?
    let gender: String?

    enum CodingKeys: String, CodingKey {
        case uid, uname, face, gender
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uid = container.decodeLossyIntIfPresent(forKey: .uid)
        uname = try container.decodeIfPresent(String.self, forKey: .uname)
        face = try container.decodeIfPresent(String.self, forKey: .face)
        gender = try container.decodeIfPresent(String.self, forKey: .gender)
    }
}

nonisolated struct LiveAnchorRelationInfo: Decodable, Hashable {
    let attention: Int?

    enum CodingKeys: String, CodingKey {
        case attention
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        attention = container.decodeLossyIntIfPresent(forKey: .attention)
    }
}

nonisolated struct FollowedLiveRoomsData: Decodable {
    let list: [LiveRoom]?
    let rooms: [LiveRoom]?

    enum CodingKeys: String, CodingKey {
        case list
        case rooms = "room_list"
    }

    var roomList: [LiveRoom] {
        list ?? rooms ?? []
    }
}

nonisolated struct LiveDanmakuConnectionInfoData: Decodable, Sendable {
    let token: String?
    let hostList: [LiveDanmakuHost]

    enum CodingKeys: String, CodingKey {
        case token
        case hostList = "host_list"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        token = container.decodeLossyStringIfPresent(forKey: .token)
        hostList = try container.decodeIfPresent([LiveDanmakuHost].self, forKey: .hostList) ?? []
    }
}

nonisolated struct LiveDanmakuHistoryData: Decodable, Sendable {
    let admin: [LiveDanmakuHistoryMessage]
    let room: [LiveDanmakuHistoryMessage]

    enum CodingKeys: String, CodingKey {
        case admin
        case room
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        admin = try container.decodeIfPresent([LiveDanmakuHistoryMessage].self, forKey: .admin) ?? []
        room = try container.decodeIfPresent([LiveDanmakuHistoryMessage].self, forKey: .room) ?? []
    }

    var chronologicalMessages: [LiveDanmakuHistoryMessage] {
        (admin + room)
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { ($0.timeline ?? "") < ($1.timeline ?? "") }
    }
}

nonisolated struct LiveDanmakuHistoryMessage: Decodable, Hashable, Sendable {
    let text: String
    let nickname: String?
    let timeline: String?

    enum CodingKeys: String, CodingKey {
        case text
        case nickname
        case uname
        case userName = "user_name"
        case username
        case name
        case timeline
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = container.decodeLossyStringIfPresent(forKey: .text) ?? ""
        nickname = [
            container.decodeLossyStringIfPresent(forKey: .nickname),
            container.decodeLossyStringIfPresent(forKey: .uname),
            container.decodeLossyStringIfPresent(forKey: .userName),
            container.decodeLossyStringIfPresent(forKey: .username),
            container.decodeLossyStringIfPresent(forKey: .name),
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first(where: { !$0.isEmpty })
        timeline = container.decodeLossyStringIfPresent(forKey: .timeline)
    }
}

nonisolated struct LiveDanmakuHost: Decodable, Hashable, Sendable {
    let host: String
    let port: Int?
    let wssPort: Int?
    let wsPort: Int?

    enum CodingKeys: String, CodingKey {
        case host
        case port
        case wssPort = "wss_port"
        case wsPort = "ws_port"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        host = container.decodeLossyStringIfPresent(forKey: .host) ?? ""
        port = container.decodeLossyIntIfPresent(forKey: .port)
        wssPort = container.decodeLossyIntIfPresent(forKey: .wssPort)
        wsPort = container.decodeLossyIntIfPresent(forKey: .wsPort)
    }

    var webSocketURL: URL? {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else { return nil }
        let portValue = wssPort ?? port ?? wsPort ?? 443
        return URL(string: "wss://\(trimmedHost):\(portValue)/sub")
    }
}

nonisolated struct LivePlayURLInfo: Decodable {
    let playurl: LivePlayURL?
}

nonisolated struct LivePlayURL: Decodable {
    let stream: [LiveStream]?
    let qualityDescriptions: [LiveStreamQuality]?

    enum CodingKeys: String, CodingKey {
        case stream
        case qualityDescriptions = "g_qn_desc"
    }
}

nonisolated struct LiveStream: Decodable {
    let protocolName: String?
    let format: [LiveStreamFormat]?

    enum CodingKeys: String, CodingKey {
        case format
        case protocolName = "protocol_name"
    }
}

nonisolated extension Array where Element == LiveStream {
    fileprivate var acceptedQualities: [LiveStreamQuality] {
        let values = flatMap { stream in
            (stream.format ?? []).flatMap { format in
                (format.codec ?? []).flatMap { codec in
                    codec.acceptedQualities
                }
            }
        }
        return LiveStreamQuality.merged(values)
    }

    fileprivate func firstPlayableURL(preferHLS: Bool) -> URL? {
        playableURLCandidates(preferHLS: preferHLS).first?.url
    }

    fileprivate func playableURLCandidates(preferHLS: Bool) -> [LiveStreamURLCandidate] {
        let candidates = flatMap { stream in
            (stream.format ?? []).flatMap { format in
                (format.codec ?? []).flatMap { codec in
                    codec.playableURLCandidates(
                        protocolName: stream.protocolName,
                        formatName: format.formatName,
                        source: "v2"
                    )
                }
            }
        }

        return
            candidates
            .filter { candidate in
                guard candidate.url.scheme == "https" || candidate.url.scheme == "http" else { return false }
                if preferHLS {
                    return candidate.isLikelyHLS || candidate.url.isLikelyAVPlayerFile
                }
                return true
            }
            .sorted { lhs, rhs in
                lhs.livePlaybackPriorityScore < rhs.livePlaybackPriorityScore
            }
            .removingDuplicateLiveURLs()
    }
}

nonisolated struct LiveStreamFormat: Decodable {
    let formatName: String?
    let codec: [LiveStreamCodec]?

    enum CodingKeys: String, CodingKey {
        case codec
        case formatName = "format_name"
    }
}

nonisolated struct LiveStreamCodec: Decodable {
    let codecName: String?
    let currentQN: Int?
    let acceptQN: [Int]?
    let baseURL: String
    let urlInfo: [LiveStreamURLInfo]?

    enum CodingKeys: String, CodingKey {
        case codecName = "codec_name"
        case currentQN = "current_qn"
        case acceptQN = "accept_qn"
        case baseURL = "base_url"
        case urlInfo = "url_info"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        codecName = try container.decodeIfPresent(String.self, forKey: .codecName)
        currentQN = container.decodeLossyIntIfPresent(forKey: .currentQN)
        acceptQN = try container.decodeIfPresent([Int].self, forKey: .acceptQN)
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
        urlInfo = try container.decodeIfPresent([LiveStreamURLInfo].self, forKey: .urlInfo)
    }

    var acceptedQualities: [LiveStreamQuality] {
        LiveStreamQuality.merged(
            (acceptQN ?? []).map { LiveStreamQuality(qn: $0, description: nil) }
                + [currentQN].compactMap { qn in
                    guard let qn else { return nil }
                    return LiveStreamQuality(qn: qn, description: nil)
                }
        )
    }

    var playableURLs: [URL] {
        if let urlInfo, !urlInfo.isEmpty {
            return urlInfo.compactMap { info in
                Self.makeURL(host: info.host, baseURL: baseURL, extra: info.extra)
            }
        }
        return Self.makeURL(host: "", baseURL: baseURL, extra: nil).map { [$0] } ?? []
    }

    func playableURLCandidates(protocolName: String?, formatName: String?, source: String) -> [LiveStreamURLCandidate] {
        playableURLs.map {
            LiveStreamURLCandidate(
                url: $0,
                protocolName: protocolName,
                formatName: formatName,
                codecName: codecName,
                currentQN: currentQN,
                qualityTitle: currentQN.map(LiveStreamQuality.defaultTitle),
                source: source
            )
        }
    }

    private static func makeURL(host: String, baseURL: String, extra: String?) -> URL? {
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBase.isEmpty else { return nil }

        let normalizedHost: String
        if trimmedBase.hasPrefix("http://") || trimmedBase.hasPrefix("https://") {
            normalizedHost = ""
        } else if host.hasPrefix("//") {
            normalizedHost = "https:" + host
        } else {
            normalizedHost = host
        }

        var urlString = normalizedHost + trimmedBase
        if let extra, !extra.isEmpty {
            if urlString.hasSuffix("?") || urlString.hasSuffix("&") {
                urlString += extra.trimmingPrefixCharacters(["?", "&"])
            } else if extra.hasPrefix("?") || extra.hasPrefix("&") {
                urlString += extra
            } else {
                urlString += urlString.contains("?") ? "&\(extra)" : "?\(extra)"
            }
        }

        return URL(string: urlString)
    }
}

nonisolated struct LiveStreamURLInfo: Decodable {
    let host: String
    let extra: String?
}

nonisolated extension String {
    fileprivate func trimmingPrefixCharacters(_ characters: Set<Character>) -> String {
        var result = self
        while let first = result.first, characters.contains(first) {
            result.removeFirst()
        }
        return result
    }
}

nonisolated extension LiveStreamURLCandidate {
    fileprivate var livePlaybackPriorityScore: Int {
        var score = 0
        if !isLikelyHLS {
            score += 10_000
        }
        if formatName?.localizedCaseInsensitiveContains("fmp4") == true {
            score -= 600
        }
        if url.isLikelyHLSManifest {
            score -= 500
        }
        if protocolName?.localizedCaseInsensitiveContains("hls") == true {
            score -= 300
        }
        if formatName?.localizedCaseInsensitiveContains("ts") == true {
            score += 180
        }

        let codec = codecName?.lowercased() ?? ""
        if codec.contains("avc") || codec.contains("h264") {
            score -= 240
        } else if codec.contains("hevc") || codec.contains("h265") {
            score += 260
        } else if codec.contains("av1") {
            score += 420
        }

        if let currentQN {
            score += max(0, currentQN - 400) / 100
        }
        return score
    }
}

nonisolated extension Array where Element == LiveStreamURLCandidate {
    fileprivate func removingDuplicateLiveURLs() -> [LiveStreamURLCandidate] {
        var seen = Set<String>()
        var result: [LiveStreamURLCandidate] = []
        for candidate in self {
            guard seen.insert(candidate.url.absoluteString).inserted else { continue }
            result.append(candidate)
        }
        return result
    }
}

nonisolated extension URL {
    fileprivate var isLikelyHLSManifest: Bool {
        pathExtension.localizedCaseInsensitiveCompare("m3u8") == .orderedSame
            || absoluteString.range(of: ".m3u8", options: .caseInsensitive) != nil
    }

    fileprivate var isLikelyAVPlayerFile: Bool {
        let ext = pathExtension.lowercased()
        return ext == "mp4" || ext == "m4v" || ext == "mov"
    }

    fileprivate var liveStreamFormatHint: String? {
        if isLikelyHLSManifest {
            return "hls"
        }
        let ext = pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        return ext.isEmpty ? nil : ext
    }
}

import Foundation

nonisolated enum AccountMessageCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case reply
    case mention
    case like
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reply:
            return "回复我的"
        case .mention:
            return "@ 我"
        case .like:
            return "收到的赞"
        case .system:
            return "系统通知"
        }
    }

    var systemImage: String {
        switch self {
        case .reply:
            return "text.bubble"
        case .mention:
            return "at"
        case .like:
            return "heart"
        case .system:
            return "bell"
        }
    }

    var emptyTitle: String {
        switch self {
        case .reply:
            return "还没有回复"
        case .mention:
            return "还没有 @ 你"
        case .like:
            return "还没有收到赞"
        case .system:
            return "还没有系统通知"
        }
    }
}

nonisolated struct AccountMessageUnreadSummary: Equatable, Sendable {
    let reply: Int
    let mention: Int
    let like: Int
    let system: Int

    init(reply: Int = 0, mention: Int = 0, like: Int = 0, system: Int = 0) {
        self.reply = max(0, reply)
        self.mention = max(0, mention)
        self.like = max(0, like)
        self.system = max(0, system)
    }

    static let empty = AccountMessageUnreadSummary()

    var total: Int {
        reply + mention + like + system
    }

    func count(for category: AccountMessageCategory) -> Int {
        switch category {
        case .reply:
            return reply
        case .mention:
            return mention
        case .like:
            return like
        case .system:
            return system
        }
    }

    func markingRead(_ category: AccountMessageCategory) -> AccountMessageUnreadSummary {
        switch category {
        case .reply:
            return AccountMessageUnreadSummary(mention: mention, like: like, system: system)
        case .mention:
            return AccountMessageUnreadSummary(reply: reply, like: like, system: system)
        case .like:
            return AccountMessageUnreadSummary(reply: reply, mention: mention, system: system)
        case .system:
            return AccountMessageUnreadSummary(reply: reply, mention: mention, like: like)
        }
    }

    func badgeText(for category: AccountMessageCategory? = nil) -> String? {
        let count = category.map(count(for:)) ?? total
        guard count > 0 else { return nil }
        return count > 99 ? "99+" : String(count)
    }
}

nonisolated struct AccountMessageCursor: Equatable, Sendable {
    let id: Int?
    let timestamp: Int?
    let isEnd: Bool

    init(id: Int?, timestamp: Int?, isEnd: Bool) {
        self.id = id
        self.timestamp = timestamp
        self.isEnd = isEnd
    }

    var canLoadMore: Bool {
        !isEnd && id != nil
    }
}

nonisolated struct AccountMessageLink: Equatable, Sendable {
    let nativeURI: String?
    let webURLString: String?

    init(nativeURI: String? = nil, webURLString: String? = nil) {
        self.nativeURI = nativeURI?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyAccountMessageText
        self.webURLString = webURLString?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyAccountMessageText
    }

    var resolvedURL: URL? {
        AccountMessageLinkResolver.resolve(nativeURI: nativeURI, webURLString: webURLString)
    }

    var commentTarget: AccountMessageCommentTarget? {
        AccountMessageLinkResolver.commentTarget(
            nativeURI: nativeURI,
            webURLString: webURLString
        )
    }
}

nonisolated struct AccountMessageCommentTarget: Identifiable, Hashable, Sendable {
    let oid: String
    let type: Int
    let rootID: Int
    let secondaryID: Int?
    let originalURL: URL?

    var id: String {
        "\(type)-\(oid)-\(rootID)-\(secondaryID ?? 0)"
    }

    var contentTitle: String {
        switch type {
        case 1:
            return "原视频"
        case 11, 16, 17:
            return "原动态"
        case 12:
            return "原专栏"
        case 22:
            return "原 Opus"
        default:
            return "原内容"
        }
    }
}

nonisolated struct AccountMessageCommentThread: Equatable {
    let root: Comment
    let replies: [Comment]
    let focusedReplyID: Int?
    let requestedReplyWasUnavailable: Bool
}

nonisolated struct AccountMessageUnavailableTarget: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let message: String
    let originalURL: URL?
}

nonisolated enum AccountMessageRouteResolution: Equatable, Sendable {
    case open(URL)
    case comment(AccountMessageCommentTarget)
    case unavailable(AccountMessageUnavailableTarget)
}

nonisolated enum AccountMessageRouteError: LocalizedError {
    case commentUnavailable

    var errorDescription: String? {
        switch self {
        case .commentUnavailable:
            return "这条评论可能已被删除、折叠或仅对部分用户可见。"
        }
    }
}

nonisolated enum AccountMessageInboxFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case unread
    case reply
    case mention
    case like
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "全部"
        case .unread:
            return "未读"
        case .reply:
            return "回复"
        case .mention:
            return "@ 我"
        case .like:
            return "赞"
        case .system:
            return "系统"
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            return "tray.full"
        case .unread:
            return "envelope.badge"
        case .reply:
            return AccountMessageCategory.reply.systemImage
        case .mention:
            return AccountMessageCategory.mention.systemImage
        case .like:
            return AccountMessageCategory.like.systemImage
        case .system:
            return AccountMessageCategory.system.systemImage
        }
    }

    var category: AccountMessageCategory? {
        switch self {
        case .all, .unread:
            return nil
        case .reply:
            return .reply
        case .mention:
            return .mention
        case .like:
            return .like
        case .system:
            return .system
        }
    }
}

nonisolated struct AccountMessageActor: Identifiable, Equatable, Sendable {
    let mid: Int?
    let name: String
    let avatarURLString: String?

    var id: String {
        mid.map { "mid-\($0)" } ?? "\(name)-\(avatarURLString ?? "-")"
    }

    var owner: VideoOwner? {
        guard let mid, mid > 0 else { return nil }
        return VideoOwner(mid: mid, name: name, face: avatarURLString)
    }
}

nonisolated struct AccountMessageItem: Identifiable, Equatable, Sendable {
    let id: String
    let serverID: Int?
    let category: AccountMessageCategory
    let actors: [AccountMessageActor]
    let count: Int
    let title: String
    let body: String
    let contextLines: [String]
    let timestamp: Date?
    let timestampText: String?
    let coverURLString: String?
    let link: AccountMessageLink
    let isLatest: Bool
    var noticeState: Int?

    var actorDisplayName: String? {
        actors.isEmpty ? nil : actors.map(\.name).joined(separator: "、")
    }

    var avatarURLString: String? {
        actors.first?.avatarURLString
    }

    var primaryOwner: VideoOwner? {
        actors.first?.owner
    }

    var canDelete: Bool {
        serverID != nil
    }

    var canShowLikeDetail: Bool {
        category == .like && count > 1 && serverID != nil
    }

    var isLikeNotificationMuted: Bool {
        noticeState == 1
    }

    var displayTime: String? {
        if let timestamp {
            return BiliFormatters.accountMessageDateTime(timestamp)
        }
        return timestampText?.nonEmptyAccountMessageText
    }

    var routeURL: URL? {
        link.resolvedURL
    }

    var commentTarget: AccountMessageCommentTarget? {
        link.commentTarget
    }

    var searchableText: String {
        ([title, body] + contextLines + actors.map(\.name))
            .joined(separator: "\n")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }
}

nonisolated struct AccountMessagePage: Equatable, Sendable {
    let items: [AccountMessageItem]
    let nextCursor: AccountMessageCursor?
    let hasMore: Bool
    let lastViewAt: Date?

    init(
        items: [AccountMessageItem],
        nextCursor: AccountMessageCursor?,
        hasMore: Bool,
        lastViewAt: Date? = nil
    ) {
        self.items = items
        self.nextCursor = nextCursor
        self.hasMore = hasMore
        self.lastViewAt = lastViewAt
    }
}

nonisolated struct AccountMessageLikeDetailItem: Identifiable, Equatable, Sendable {
    let actor: AccountMessageActor
    let timestamp: Date?

    var id: String {
        "\(actor.id)-\(Int(timestamp?.timeIntervalSince1970 ?? 0))"
    }

    var displayTime: String? {
        BiliFormatters.accountMessageDateTime(timestamp)
    }
}

nonisolated struct AccountMessageLikeDetailPage: Equatable, Sendable {
    let title: String?
    let items: [AccountMessageLikeDetailItem]
    let hasMore: Bool
    let nextLastMID: Int?
}

nonisolated struct AccountMessageFollower: Identifiable, Equatable, Sendable {
    let actor: AccountMessageActor
    let sign: String?
    let followedAt: Date?

    var id: String { actor.id }

    var displayTime: String? {
        BiliFormatters.accountMessageDateTime(followedAt)
    }
}

nonisolated struct AccountMessageFollowerPage: Equatable, Sendable {
    let items: [AccountMessageFollower]
    let total: Int?
    let hasMore: Bool
}

nonisolated struct AccountPrivateMessageSession: Identifiable, Equatable, Sendable {
    let talkerID: Int
    let actor: AccountMessageActor
    let preview: String
    let timestamp: Date?
    var unreadCount: Int
    let lastMessageSequence: Int?
    var isPinned: Bool
    var isMuted: Bool

    var id: Int { talkerID }

    var displayTime: String? {
        BiliFormatters.accountMessageDateTime(timestamp)
    }
}

nonisolated struct AccountPrivateMessage: Identifiable, Equatable, Sendable {
    let sequence: Int
    let messageKey: Int?
    let messageType: Int
    let senderID: Int
    let text: String
    let imageURLString: String?
    let routeURL: URL?
    let timestamp: Date?
    let isOutgoing: Bool
    var isWithdrawn: Bool

    var id: Int { sequence }

    var canWithdraw: Bool {
        isOutgoing && !isWithdrawn && messageKey != nil
    }

    var canReport: Bool {
        !isOutgoing && !isWithdrawn && messageKey != nil
    }

    var displayTime: String? {
        BiliFormatters.accountMessageDateTime(timestamp)
    }
}

nonisolated struct AccountPrivateMessagePage: Equatable, Sendable {
    let items: [AccountPrivateMessage]
    let hasMore: Bool
    let nextEndSequence: Int?
}

nonisolated struct AccountPrivateMessageImageUpload: Equatable, Sendable {
    let url: String
    let width: Int
    let height: Int
    let size: Double
}

nonisolated struct AccountMessageTextSegment: Equatable, Sendable {
    let text: String
    let url: URL?
}

nonisolated enum AccountMessageRichTextParser {
    static func segments(from text: String) -> [AccountMessageTextSegment] {
        let pattern = #"#\{([^}]*)\}\{([^}]*)\}|https?://[^\s，。！？、；：【】（）]+|www\.[^\s，。！？、；：【】（）]+|【((?:BV[0-9A-Za-z]+)|(?:av)?[0-9]+)】|（([0-9]+)）"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return [AccountMessageTextSegment(text: text, url: nil)]
        }

        let source = text as NSString
        let matches = expression.matches(in: text, range: NSRange(location: 0, length: source.length))
        guard !matches.isEmpty else {
            return [AccountMessageTextSegment(text: text, url: nil)]
        }

        var segments: [AccountMessageTextSegment] = []
        var location = 0
        for match in matches {
            if match.range.location > location {
                append(source.substring(with: NSRange(location: location, length: match.range.location - location)), url: nil, to: &segments)
            }

            let raw = source.substring(with: match.range)
            if let label = capture(1, in: match, source: source),
               let destination = capture(2, in: match, source: source),
               let url = resolvedURL(destination) {
                append(label, url: url, to: &segments)
            } else if let videoID = capture(3, in: match, source: source),
                      let url = videoURL(videoID) {
                append(raw, url: url, to: &segments)
            } else if let dynamicID = capture(4, in: match, source: source),
                      let url = URL(string: "https://t.bilibili.com/\(dynamicID)") {
                append("查看动态", url: url, to: &segments)
            } else if let url = resolvedURL(raw) {
                append("网页链接", url: url, to: &segments)
            } else {
                append(raw, url: nil, to: &segments)
            }
            location = NSMaxRange(match.range)
        }

        if location < source.length {
            append(source.substring(from: location), url: nil, to: &segments)
        }
        return segments
    }

    static func attributedString(from text: String) -> AttributedString {
        segments(from: text).reduce(into: AttributedString()) { result, segment in
            var value = AttributedString(segment.text)
            value.link = segment.url
            result.append(value)
        }
    }

    static func containsLink(in text: String) -> Bool {
        segments(from: text).contains { $0.url != nil }
    }

    private static func capture(_ index: Int, in match: NSTextCheckingResult, source: NSString) -> String? {
        let range = match.range(at: index)
        guard range.location != NSNotFound else { return nil }
        return source.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyAccountMessageText
    }

    private static func resolvedURL(_ rawValue: String) -> URL? {
        let value = rawValue
            .replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("bilibili://") {
            return AccountMessageLinkResolver.resolve(nativeURI: value, webURLString: nil)
        }
        return AccountMessageLinkResolver.resolve(nativeURI: nil, webURLString: value)
    }

    private static func videoURL(_ rawValue: String) -> URL? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = value.lowercased().hasPrefix("bv") || value.lowercased().hasPrefix("av")
            ? value
            : "av\(value)"
        return URL(string: "https://www.bilibili.com/video/\(path)")
    }

    private static func append(
        _ text: String,
        url: URL?,
        to segments: inout [AccountMessageTextSegment]
    ) {
        guard !text.isEmpty else { return }
        if url == nil, !segments.isEmpty, segments.last?.url == nil {
            let previous = segments.removeLast()
            segments.append(AccountMessageTextSegment(text: previous.text + text, url: nil))
        } else {
            segments.append(AccountMessageTextSegment(text: text, url: url))
        }
    }
}

nonisolated enum AccountMessageLinkResolver {
    static func resolve(nativeURI: String?, webURLString: String?) -> URL? {
        let nativeResolvedURL: URL? = {
            guard let nativeURI,
                  let nativeURL = URL(string: nativeURI.trimmingCharacters(in: .whitespacesAndNewlines))
            else {
                return nil
            }

            if let normalized = AppLinkRouter.normalizedHTTPURL(nativeURL) {
                return normalizedMessageURL(normalized)
            }
            return httpURL(forBiliNativeURL: nativeURL)
        }()

        if let webURLString,
           let url = normalizedHTTPURL(from: webURLString) {
            return preservingCommentAnchor(from: nativeResolvedURL, in: url)
        }
        return nativeResolvedURL
    }

    static func commentTarget(nativeURI: String?, webURLString: String?) -> AccountMessageCommentTarget? {
        let nativeURL = nativeURI
            .flatMap { URL(string: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let webURL = webURLString.flatMap(normalizedHTTPURL(from:))

        if let nativeURL,
           let target = nativeCommentTarget(from: nativeURL, preferredOriginalURL: webURL) {
            return target
        }
        if let webURL,
           let target = webCommentTarget(from: webURL) {
            return target
        }
        return nil
    }

    static func httpURL(forBiliNativeURL url: URL) -> URL? {
        guard url.scheme?.lowercased() == "bilibili" else { return nil }
        let host = url.host?.lowercased() ?? ""
        let pathComponents = url.pathComponents
            .dropFirst()
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
            .filter { !$0.isEmpty }
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        switch host {
        case "video":
            if let bvid = queryValue(named: "bvid", in: queryItems) ?? firstBVID(in: pathComponents) {
                return videoURL(path: bvid, queryItems: queryItems)
            }
            if let aid = queryValue(named: "aid", in: queryItems)
                ?? queryValue(named: "avid", in: queryItems)
                ?? firstAVID(in: pathComponents)
                ?? firstNumericPathComponent(in: pathComponents) {
                return videoURL(path: "av\(aid)", queryItems: queryItems)
            }
        case "live":
            if let roomID = queryValue(named: "room_id", in: queryItems)
                ?? queryValue(named: "roomid", in: queryItems)
                ?? firstNumericPathComponent(in: pathComponents) {
                return URL(string: "https://live.bilibili.com/\(roomID)")
            }
        case "space":
            if let mid = queryValue(named: "mid", in: queryItems) ?? firstNumericPathComponent(in: pathComponents) {
                return URL(string: "https://space.bilibili.com/\(mid)")
            }
        case "main":
            if let mid = queryValue(named: "mid", in: queryItems)
                ?? queryValue(named: "uid", in: queryItems) {
                return URL(string: "https://space.bilibili.com/\(mid)")
            }
        case "dynamic":
            if let dynamicID = queryValue(named: "dynamic_id", in: queryItems)
                ?? queryValue(named: "id", in: queryItems)
                ?? firstNumericPathComponent(in: pathComponents) {
                return URL(string: "https://t.bilibili.com/\(dynamicID)")
            }
        case "following":
            if pathComponents.first?.lowercased() == "detail" {
                if let articleID = pathComponents
                    .first(where: { $0.lowercased().hasPrefix("cv") })?
                    .droppingPrefix("cv") {
                    return URL(string: "https://www.bilibili.com/read/cv\(articleID)")
                }
                if let dynamicID = firstNumericPathComponent(in: pathComponents) {
                    return URL(string: "https://t.bilibili.com/\(dynamicID)")
                }
            }
        case "opus":
            if let opusID = queryValue(named: "id", in: queryItems) ?? firstNumericPathComponent(in: pathComponents) {
                return URL(string: "https://www.bilibili.com/opus/\(opusID)")
            }
        case "article":
            if let articleID = firstNumericPathComponent(in: pathComponents) {
                return URL(string: "https://www.bilibili.com/read/cv\(articleID)")
            }
        case "pgc", "bangumi":
            if let episodeID = queryValue(named: "ep_id", in: queryItems)
                ?? pathComponents.first(where: { $0.hasPrefix("ep") })?.droppingPrefix("ep")
                ?? pathComponent(after: "ep", in: pathComponents) {
                return URL(string: "https://www.bilibili.com/bangumi/play/ep\(episodeID)")
            }
            if let seasonID = queryValue(named: "season_id", in: queryItems)
                ?? pathComponents.first(where: { $0.hasPrefix("ss") })?.droppingPrefix("ss")
                ?? pathComponent(after: "season", in: pathComponents) {
                return URL(string: "https://www.bilibili.com/bangumi/play/ss\(seasonID)")
            }
        case "comment":
            guard pathComponents.count >= 4,
                  ["detail", "msg_fold"].contains(pathComponents[0].lowercased()),
                  let type = Int(pathComponents[1]),
                  let subjectID = Int(pathComponents[2]),
                  let rootID = Int(pathComponents[3])
            else {
                return nil
            }
            let secondaryID = queryValue(named: "anchor", in: queryItems)
                ?? queryValue(named: "comment_secondary_id", in: queryItems)
            if let enterURI = queryValue(named: "enterUri", in: queryItems)
                ?? queryValue(named: "enter_uri", in: queryItems),
               let enterURL = URL(string: enterURI),
               let destination = httpURL(forBiliNativeURL: enterURL) {
                return addingCommentAnchor(rootID: rootID, secondaryID: secondaryID, to: destination)
            }
            if type == 1 {
                return videoURL(
                    path: "av\(subjectID)",
                    queryItems: commentQueryItems(rootID: rootID, secondaryID: secondaryID)
                )
            }
            if [11, 16, 17].contains(type) {
                return URL(string: "https://t.bilibili.com/\(subjectID)")
            }
            if type == 12 {
                return URL(string: "https://www.bilibili.com/read/cv\(subjectID)")
            }
            if type == 22 {
                return URL(string: "https://www.bilibili.com/opus/\(subjectID)")
            }
        case "browser":
            if let nestedURL = queryValue(named: "url", in: queryItems) {
                return normalizedHTTPURL(from: nestedURL)
            }
        default:
            break
        }
        return nil
    }

    private static func preservingCommentAnchor(from nativeURL: URL?, in webURL: URL) -> URL {
        guard let nativeURL,
              let anchor = AppLinkRouter.commentAnchor(for: nativeURL)
        else {
            return webURL
        }

        var components = URLComponents(url: webURL, resolvingAgainstBaseURL: false)
        var queryItems = components?.queryItems ?? []
        queryItems.removeAll {
            $0.name.caseInsensitiveCompare("comment_root_id") == .orderedSame
                || $0.name.caseInsensitiveCompare("comment_secondary_id") == .orderedSame
        }
        queryItems.append(URLQueryItem(name: "comment_root_id", value: String(anchor.rootID)))
        if let secondaryID = anchor.secondaryID {
            queryItems.append(URLQueryItem(name: "comment_secondary_id", value: String(secondaryID)))
        }
        components?.queryItems = queryItems
        return components?.url ?? webURL
    }

    private static func nativeCommentTarget(
        from url: URL,
        preferredOriginalURL: URL?
    ) -> AccountMessageCommentTarget? {
        guard url.scheme?.lowercased() == "bilibili",
              url.host?.lowercased() == "comment"
        else {
            return nil
        }

        let pathComponents = url.pathComponents
            .dropFirst()
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
            .filter { !$0.isEmpty }
        guard pathComponents.count >= 4,
              ["detail", "msg_fold"].contains(pathComponents[0].lowercased()),
              let type = Int(pathComponents[1]),
              let rootID = Int(pathComponents[3]),
              rootID > 0
        else {
            return nil
        }

        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let oid = pathComponents[2]
        let secondaryID = queryValue(named: "anchor", in: queryItems).flatMap(Int.init)
            ?? queryValue(named: "comment_secondary_id", in: queryItems).flatMap(Int.init)
        let enterURL = (queryValue(named: "enterUri", in: queryItems)
            ?? queryValue(named: "enter_uri", in: queryItems))
            .flatMap(URL.init(string:))
            .flatMap { AppLinkRouter.normalizedHTTPURL($0) ?? httpURL(forBiliNativeURL: $0) }
        let originalURL = preferredOriginalURL
            .flatMap { webCommentTarget(from: $0) == nil ? $0 : nil }
            ?? enterURL
            ?? fallbackContentURL(type: type, oid: oid)

        return AccountMessageCommentTarget(
            oid: oid,
            type: type,
            rootID: rootID,
            secondaryID: secondaryID,
            originalURL: originalURL
        )
    }

    private static func webCommentTarget(from url: URL) -> AccountMessageCommentTarget? {
        guard url.path.lowercased().contains("/h5/comment/sub") else { return nil }
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let oid = queryValue(named: "oid", in: queryItems),
              let rootID = queryValue(named: "root", in: queryItems).flatMap(Int.init),
              rootID > 0
        else {
            return nil
        }
        let type = queryValue(named: "type", in: queryItems).flatMap(Int.init)
            ?? (queryValue(named: "pageType", in: queryItems).flatMap(Int.init) == 1 ? 1 : 0)
        guard type > 0 else { return nil }
        return AccountMessageCommentTarget(
            oid: oid,
            type: type,
            rootID: rootID,
            secondaryID: queryValue(named: "comment_secondary_id", in: queryItems).flatMap(Int.init),
            originalURL: fallbackContentURL(type: type, oid: oid)
        )
    }

    private static func fallbackContentURL(type: Int, oid: String) -> URL? {
        switch type {
        case 1:
            return URL(string: "https://www.bilibili.com/video/av\(oid)")
        case 11, 16, 17:
            return URL(string: "https://t.bilibili.com/\(oid)")
        case 12:
            return URL(string: "https://www.bilibili.com/read/\(oid.lowercased().hasPrefix("cv") ? oid : "cv\(oid)")")
        case 22:
            return URL(string: "https://www.bilibili.com/opus/\(oid)")
        default:
            return nil
        }
    }

    private static func videoURL(path: String, queryItems: [URLQueryItem]) -> URL? {
        var components = URLComponents(string: "https://www.bilibili.com/video/\(path)")
        let commentQueryItems = queryItems.filter {
            $0.name.caseInsensitiveCompare("comment_root_id") == .orderedSame
                || $0.name.caseInsensitiveCompare("comment_secondary_id") == .orderedSame
        }
        components?.queryItems = commentQueryItems.isEmpty ? nil : commentQueryItems
        return components?.url
    }

    private static func addingCommentAnchor(rootID: Int, secondaryID: String?, to url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var queryItems = components?.queryItems ?? []
        queryItems.removeAll {
            $0.name.caseInsensitiveCompare("comment_root_id") == .orderedSame
                || $0.name.caseInsensitiveCompare("comment_secondary_id") == .orderedSame
        }
        queryItems.append(contentsOf: commentQueryItems(rootID: rootID, secondaryID: secondaryID))
        components?.queryItems = queryItems
        return components?.url ?? url
    }

    private static func commentQueryItems(rootID: Int, secondaryID: String?) -> [URLQueryItem] {
        [
            URLQueryItem(name: "comment_root_id", value: String(rootID)),
            secondaryID.flatMap { Int($0).map(String.init) }
                .map { URLQueryItem(name: "comment_secondary_id", value: $0) }
        ].compactMap { $0 }
    }

    private static func normalizedHTTPURL(from rawValue: String) -> URL? {
        let normalized: URL?
        if let url = URL(string: rawValue),
           let url = AppLinkRouter.normalizedHTTPURL(url) {
            normalized = url
        } else {
            normalized = AppLinkRouter.normalizedHTTPURLString(rawValue).flatMap(URL.init(string:))
        }
        return normalized.map(normalizedMessageURL)
    }

    private static func normalizedMessageURL(_ url: URL) -> URL {
        guard url.path.lowercased().contains("/h5/comment/sub"),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let subjectID = queryValue(named: "oid", in: components.queryItems ?? []).flatMap(Int.init),
              let rootID = queryValue(named: "root", in: components.queryItems ?? []).flatMap(Int.init),
              queryValue(named: "pageType", in: components.queryItems ?? []).flatMap(Int.init) == 1,
              let videoURL = videoURL(
                  path: "av\(subjectID)",
                  queryItems: commentQueryItems(
                      rootID: rootID,
                      secondaryID: queryValue(named: "comment_secondary_id", in: components.queryItems ?? [])
                  )
              )
        else {
            return url
        }
        return videoURL
    }

    private static func queryValue(named name: String, in queryItems: [URLQueryItem]) -> String? {
        queryItems.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value?.nonEmptyAccountMessageText
    }

    private static func firstBVID(in values: [String]) -> String? {
        values.first { $0.range(of: #"^BV[A-Za-z0-9]+$"#, options: .regularExpression) != nil }
    }

    private static func firstNumericPathComponent(in values: [String]) -> String? {
        values.first { Int($0) != nil }
    }

    private static func firstAVID(in values: [String]) -> String? {
        values
            .first { $0.lowercased().hasPrefix("av") && Int($0.dropFirst(2)) != nil }
            .flatMap { $0.droppingPrefix("av") ?? $0.droppingPrefix("AV") }
    }

    private static func pathComponent(after value: String, in values: [String]) -> String? {
        guard let index = values.firstIndex(where: { $0.caseInsensitiveCompare(value) == .orderedSame }),
              values.indices.contains(index + 1)
        else {
            return nil
        }
        let candidate = values[index + 1]
        return candidate.isEmpty ? nil : candidate
    }
}

nonisolated extension String {
    var nonEmptyAccountMessageText: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func droppingPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        let value = String(dropFirst(prefix.count))
        return value.isEmpty ? nil : value
    }
}

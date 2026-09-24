import Foundation
import SafariServices
import SwiftUI

struct InAppBrowserItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct InAppBrowserView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context _: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        return SFSafariViewController(url: url, configuration: configuration)
    }

    func updateUIViewController(_: SFSafariViewController, context _: Context) {}
}

enum AppLinkDestination {
    case video(VideoItem)
    case videoComment(VideoCommentRoute)
    case liveRoom(LiveRoom)
    case user(VideoOwner)
    case browser(URL)
}

nonisolated struct VideoCommentAnchor: Hashable, Sendable {
    let rootID: Int
    let secondaryID: Int?

    init?(rootID: Int?, secondaryID: Int? = nil) {
        guard let rootID, rootID > 0 else { return nil }
        self.rootID = rootID
        self.secondaryID = secondaryID.flatMap { $0 > 0 ? $0 : nil }
    }

    init?(url: URL) {
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        self.init(
            rootID: queryItems.firstValue(named: "comment_root_id").flatMap(Int.init),
            secondaryID: queryItems.firstValue(named: "comment_secondary_id").flatMap(Int.init)
        )
    }
}

nonisolated struct VideoCommentRoute: Hashable, Sendable {
    let video: VideoItem
    let anchor: VideoCommentAnchor
}

nonisolated enum AppLinkRouter {
    static func destination(for url: URL, api: BiliAPIClient) async -> AppLinkDestination {
        let normalizedURL = normalizedHTTPURL(url) ?? url

        if let videoLink = BiliVideoLink(url: normalizedURL) {
            if let video = await videoItem(for: videoLink, api: api) {
                return videoDestination(video, url: normalizedURL)
            }
        }

        if let room = liveRoom(from: normalizedURL) {
            return .liveRoom(room)
        }

        if let owner = userOwner(from: normalizedURL) {
            return .user(owner)
        }

        if isShortBiliHost(normalizedURL.host),
           let resolvedURL = await resolvedRedirectURL(from: normalizedURL),
           resolvedURL.absoluteString != normalizedURL.absoluteString {
            if let destination = await internalDestination(forResolvedURL: resolvedURL, originalURL: normalizedURL, api: api) {
                return destination
            }
        }

        return .browser(normalizedURL)
    }

    static func canHandle(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    static func displayTitle(for url: URL) -> String {
        let normalizedURL = normalizedHTTPURL(url) ?? url
        if BiliVideoLink(url: normalizedURL) != nil {
            return "打开视频"
        }
        if liveRoom(from: normalizedURL) != nil {
            return "打开直播间"
        }
        if userOwner(from: normalizedURL) != nil {
            return "打开用户"
        }
        if isShortBiliHost(normalizedURL.host) {
            return "打开链接"
        }
        return normalizedURL.host?.replacingPrefix("www.", with: "") ?? "查看链接"
    }

    static func inlineTitle(for url: URL, title rawTitle: String? = nil) -> String {
        let title = rawTitle?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmptyAppLinkText
        if let title,
           normalizedHTTPURLString(title) == nil,
           !looksLikeRawURLText(title) {
            return title
        }
        return displayTitle(for: url)
    }

    static func normalizedHTTPURL(_ url: URL) -> URL? {
        normalizedHTTPURLString(url.absoluteString).flatMap(URL.init(string:))
    }

    static func normalizedHTTPURLString(_ rawValue: String) -> String? {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        value = value.normalizedBiliURL()
        if value.hasPrefix("www.")
            || value.hasPrefix("b23.tv/")
            || value.hasPrefix("bili2233.cn/")
            || value.hasPrefix("bili22.cn/")
            || value.hasPrefix("bili23.cn/")
            || value.hasPrefix("bili33.cn/")
            || value.hasPrefix("bilibili.com/")
            || value.hasPrefix("m.bilibili.com/")
            || value.hasPrefix("live.bilibili.com/") {
            value = "https://\(value)"
        }

        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              components.host?.isEmpty == false
        else {
            return nil
        }
        return value
    }

    static func commentAnchor(for url: URL) -> VideoCommentAnchor? {
        let normalizedURL = normalizedHTTPURL(url) ?? url
        guard BiliVideoLink(url: normalizedURL) != nil else { return nil }
        return VideoCommentAnchor(url: normalizedURL)
    }

    private static func internalDestination(
        forResolvedURL resolvedURL: URL,
        originalURL _: URL,
        api: BiliAPIClient
    ) async -> AppLinkDestination? {
        let normalizedURL = normalizedHTTPURL(resolvedURL) ?? resolvedURL
        if let videoLink = BiliVideoLink(url: normalizedURL),
           let video = await videoItem(for: videoLink, api: api) {
            return videoDestination(video, url: normalizedURL)
        }
        if let room = liveRoom(from: normalizedURL) {
            return .liveRoom(room)
        }
        if let owner = userOwner(from: normalizedURL) {
            return .user(owner)
        }
        return nil
    }

    private static func videoDestination(_ video: VideoItem, url: URL) -> AppLinkDestination {
        if let anchor = commentAnchor(for: url) {
            return .videoComment(VideoCommentRoute(video: video, anchor: anchor))
        }
        return .video(video)
    }

    private static func videoItem(for link: BiliVideoLink, api: BiliAPIClient) async -> VideoItem? {
        if let bvid = link.bvid {
            return seedVideo(bvid: bvid, aid: link.aid, resumeTime: link.resumeTime)
        }

        guard let aid = link.aid else { return nil }
        do {
            let item = try await api.fetchVideoDetail(aid: aid)
            if let resumeTime = link.resumeTime, resumeTime > 0.25 {
                return VideoItem(
                    bvid: item.bvid,
                    aid: item.aid,
                    title: item.title,
                    pic: item.pic,
                    desc: item.desc,
                    duration: item.duration,
                    pubdate: item.pubdate,
                    owner: item.owner,
                    stat: item.stat,
                    cid: item.cid,
                    pages: item.pages,
                    dimension: item.dimension,
                    historyResumeTime: resumeTime,
                    historyCID: item.historyCID
                )
            }
            return item
        } catch {
            return nil
        }
    }

    private static func seedVideo(bvid: String, aid: Int?, resumeTime: TimeInterval?) -> VideoItem {
        VideoItem(
            bvid: bvid,
            aid: aid,
            title: "正在加载",
            pic: nil,
            desc: nil,
            duration: nil,
            pubdate: nil,
            owner: nil,
            stat: nil,
            cid: nil,
            pages: nil,
            dimension: nil,
            historyResumeTime: resumeTime,
            historyCID: nil
        )
    }

    private static func liveRoom(from url: URL) -> LiveRoom? {
        guard isBiliHost(url.host) else { return nil }
        let pathComponents = url.pathComponents
        guard pathComponents.count >= 2 else { return nil }
        let roomID = pathComponents
            .dropFirst()
            .compactMap { Int($0.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) }
            .first
        guard let roomID, roomID > 0, url.host?.lowercased().contains("live.bilibili.com") == true else {
            return nil
        }
        return LiveRoom(
            roomID: roomID,
            title: "正在进入直播间",
            uname: "直播间",
            uid: nil,
            face: nil,
            cover: nil,
            keyframe: nil,
            online: nil,
            areaName: nil,
            parentAreaName: nil,
            liveStatus: 1
        )
    }

    private static func userOwner(from url: URL) -> VideoOwner? {
        guard isBiliHost(url.host),
              url.host?.lowercased() == "space.bilibili.com"
        else { return nil }

        let mid = url.pathComponents
            .dropFirst()
            .compactMap { Int($0.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) }
            .first
        guard let mid, mid > 0 else { return nil }

        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let name = queryItems.firstValue(named: "name")
            ?? queryItems.firstValue(named: "uname")
            ?? "用户主页"
        let face = queryItems.firstValue(named: "face")?.normalizedBiliURL()
        return VideoOwner(mid: mid, name: name, face: face)
    }

    private static func resolvedRedirectURL(from url: URL) async -> URL? {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 4
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return response.url
        } catch {
            return nil
        }
    }

    private static func isBiliHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "bilibili.com" || host.hasSuffix(".bilibili.com")
    }

    private static func isShortBiliHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return [
            "b23.tv",
            "bili2233.cn",
            "bili22.cn",
            "bili23.cn",
            "bili33.cn"
        ].contains(host)
    }

    private static func looksLikeRawURLText(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        return normalized.range(
            of: #"(?i)^(?:(?:https?:)?//|www\.|b23\.tv/|bili2233\.cn/|bili22\.cn/|bili23\.cn/|bili33\.cn/|bilibili\.com/|m\.bilibili\.com/|live\.bilibili\.com/)"#,
            options: .regularExpression
        ) != nil
    }
}

nonisolated struct BiliVideoLink {
    let bvid: String?
    let aid: Int?
    let resumeTime: TimeInterval?

    init?(url: URL) {
        guard AppLinkRouter.normalizedHTTPURL(url) != nil,
              Self.isSupportedBiliVideoHost(url.host)
        else { return nil }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        let queryBVID = queryItems.firstValue(named: "bvid").flatMap(Self.normalizedBVID)
        let queryAID = queryItems.firstValue(named: "aid").flatMap(Int.init)
        let pathBVID = Self.bvid(in: url.path)
        let pathAID = Self.aid(in: url.path)
        let stringBVID = Self.bvid(in: url.absoluteString)

        let resolvedBVID = queryBVID ?? pathBVID ?? stringBVID
        let resolvedAID = queryAID ?? pathAID
        guard resolvedBVID != nil || resolvedAID != nil else { return nil }

        bvid = resolvedBVID
        aid = resolvedAID
        resumeTime = Self.resumeTime(queryItems: queryItems, fragment: components?.fragment)
    }

    private static func isSupportedBiliVideoHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "bilibili.com"
            || host.hasSuffix(".bilibili.com")
            || host == "b23.tv"
            || host == "bili2233.cn"
            || host == "bili22.cn"
            || host == "bili23.cn"
            || host == "bili33.cn"
    }

    private static func bvid(in value: String) -> String? {
        let pattern = #"(?i)\b(BV[0-9A-Za-z]{8,})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: range),
              let matchRange = Range(match.range(at: 1), in: value)
        else { return nil }
        return normalizedBVID(String(value[matchRange]))
    }

    private static func aid(in value: String) -> Int? {
        let pattern = #"(?i)(?:^|/|[?&])av(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: range),
              let matchRange = Range(match.range(at: 1), in: value)
        else { return nil }
        return Int(value[matchRange])
    }

    private static func normalizedBVID(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: #"(?i)^BV[0-9A-Za-z]{8,}$"#, options: .regularExpression) != nil else {
            return nil
        }
        let suffix = trimmed.dropFirst(2)
        return "BV\(suffix)"
    }

    private static func resumeTime(queryItems: [URLQueryItem], fragment: String?) -> TimeInterval? {
        let candidates = [
            queryItems.firstValue(named: "t"),
            queryItems.firstValue(named: "start"),
            queryItems.firstValue(named: "time")
        ]
        for candidate in candidates {
            if let parsed = parseTime(candidate) {
                return parsed
            }
        }
        if let startProgress = queryItems.firstValue(named: "start_progress").flatMap(Double.init), startProgress > 0 {
            return startProgress / 1000
        }
        if let fragment,
           fragment.hasPrefix("t="),
           let parsed = parseTime(String(fragment.dropFirst(2))) {
            return parsed
        }
        return nil
    }

    private static func parseTime(_ value: String?) -> TimeInterval? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if let seconds = Double(value), seconds > 0 {
            return seconds
        }

        let pattern = #"(?i)^\s*(?:(\d+(?:\.\d+)?)h)?(?:(\d+(?:\.\d+)?)m)?(?:(\d+(?:\.\d+)?)s?)?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: range) else { return nil }
        let hours = number(at: 1, in: match, source: value) ?? 0
        let minutes = number(at: 2, in: match, source: value) ?? 0
        let seconds = number(at: 3, in: match, source: value) ?? 0
        let total = hours * 3600 + minutes * 60 + seconds
        return total > 0 ? total : nil
    }

    private static func number(at index: Int, in match: NSTextCheckingResult, source: String) -> Double? {
        guard match.numberOfRanges > index,
              match.range(at: index).location != NSNotFound,
              let range = Range(match.range(at: index), in: source)
        else { return nil }
        return Double(source[range])
    }
}

private extension Array where Element == URLQueryItem {
    nonisolated func firstValue(named name: String) -> String? {
        first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

private struct OpenAppURLActionKey: EnvironmentKey {
    static let defaultValue: ((URL) -> Void)? = nil
}

extension EnvironmentValues {
    var openAppURLAction: ((URL) -> Void)? {
        get { self[OpenAppURLActionKey.self] }
        set { self[OpenAppURLActionKey.self] = newValue }
    }
}

struct AppLinkButton<Label: View>: View {
    let url: URL
    @ViewBuilder let label: () -> Label
    @Environment(\.openAppURLAction) private var openAppURL

    var body: some View {
        if let openAppURL {
            Button {
                openAppURL(url)
            } label: {
                label()
            }
            .buttonStyle(.plain)
        } else {
            Link(destination: url) {
                label()
            }
        }
    }
}

struct AppLinkButtons: View {
    @Environment(\.appThemeTintColor) private var appTintColor

    let urls: [URL]
    var limit = 3
    var maxButtonWidth: CGFloat = 176

    init(urls: [URL], limit: Int = 3, maxButtonWidth: CGFloat = 176) {
        self.urls = Self.unique(urls)
        self.limit = limit
        self.maxButtonWidth = maxButtonWidth
    }

    var body: some View {
        if !urls.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(visibleURLs, id: \.absoluteString) { url in
                        AppLinkButton(url: url) {
                            Label(AppLinkRouter.displayTitle(for: url), systemImage: "link")
                                .font(.caption.weight(.semibold))
                                .labelStyle(.titleAndIcon)
                                .foregroundStyle(appTintColor)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .padding(.horizontal, 9)
                                .frame(maxWidth: maxButtonWidth, alignment: .leading)
                                .frame(height: 24)
                                .background(appTintColor.opacity(0.10), in: Capsule())
                                .overlay {
                                    Capsule()
                                        .stroke(appTintColor.opacity(0.22), lineWidth: 0.5)
                                }
                        }
                        .accessibilityLabel("打开链接")
                    }

                    if hiddenCount > 0 {
                        Text("+\(hiddenCount)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 9)
                            .frame(height: 24)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                            .accessibilityLabel("还有 \(hiddenCount) 个链接")
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollClipDisabled()
        }
    }

    private var visibleURLs: [URL] {
        Array(urls.prefix(limit))
    }

    private var hiddenCount: Int {
        max(urls.count - visibleURLs.count, 0)
    }

    private static func unique(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var result = [URL]()
        for url in urls {
            let key = url.absoluteString
            guard seen.insert(key).inserted else { continue }
            result.append(url)
        }
        return result
    }
}

enum BiliTextLinkExtractor {
    static func matches(in text: String?) -> [BiliTextLinkMatch] {
        guard let text, !text.isEmpty else { return [] }
        let pattern = #"(?i)(?:(?:https?:)?//|www\.|b23\.tv/|bili2233\.cn/|bili22\.cn/|bili23\.cn/|bili33\.cn/|bilibili\.com/|m\.bilibili\.com/|live\.bilibili\.com/)[^\s<>"']+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex
            .matches(in: text, range: range)
            .compactMap { match -> BiliTextLinkMatch? in
                guard let textRange = Range(match.range, in: text) else { return nil }
                let trimmed = trimTrailingPunctuation(String(text[textRange]))
                guard !trimmed.isEmpty,
                      let normalized = AppLinkRouter.normalizedHTTPURLString(trimmed),
                      let url = URL(string: normalized)
                else { return nil }
                return BiliTextLinkMatch(
                    range: NSRange(location: match.range.location, length: (trimmed as NSString).length),
                    url: url
                )
            }
    }

    static func urls(in content: CommentContent?) -> [URL] {
        guard let content else { return [] }
        return unique(urls(in: content.message) + urls(in: content.jumpURLs))
    }

    static func urls(in text: String?) -> [URL] {
        matches(in: text).map(\.url).removingDuplicateURLs()
    }

    static func urls(in value: DynamicJSONValue?) -> [URL] {
        guard let value else { return [] }
        switch value {
        case .string(let string), .number(let string):
            return urls(in: string)
        case .array(let values):
            return unique(values.flatMap { urls(in: $0) })
        case .object(let object):
            let preferredKeys = [
                "jump_url",
                "jumpUrl",
                "url",
                "uri",
                "link",
                "native_url",
                "raw_url"
            ]
            var result = [URL]()
            for key in object.keys {
                result.append(contentsOf: urls(in: key))
            }
            for key in preferredKeys {
                result.append(contentsOf: urls(in: object[key]))
            }
            for (key, value) in object where !preferredKeys.contains(key) {
                if isLikelyNavigationalURLKey(key) || value.isContainer {
                    result.append(contentsOf: urls(in: value))
                }
            }
            return unique(result)
        case .bool, .null:
            return []
        }
    }

    static func urls(in segments: [DynamicTextSegment]) -> [URL] {
        let urls = segments.compactMap { segment -> URL? in
            guard case .link(_, let rawURL) = segment,
                  let normalized = AppLinkRouter.normalizedHTTPURLString(rawURL)
            else { return nil }
            return URL(string: normalized)
        }
        return unique(urls)
    }

    private static func trimTrailingPunctuation(_ raw: String) -> String {
        let punctuation = CharacterSet(charactersIn: ".,，。!！?？;；:：、)]}）】》\"'")
        var value = raw
        while let last = value.last,
              let scalar = String(last).unicodeScalars.first,
              punctuation.contains(scalar) {
            value.removeLast()
        }
        return value
    }

    private static func unique(_ urls: [URL]) -> [URL] {
        urls.removingDuplicateURLs()
    }

    private static func isLikelyNavigationalURLKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        guard normalized.contains("url") || normalized.contains("uri") || normalized.contains("link") else {
            return false
        }
        let mediaHints = [
            "icon",
            "image",
            "img",
            "pic",
            "cover",
            "avatar",
            "face",
            "gif",
            "webp"
        ]
        return !mediaHints.contains { normalized.contains($0) }
    }
}

nonisolated struct BiliTextLinkMatch: Hashable {
    let range: NSRange
    let url: URL
}

private extension DynamicJSONValue {
    var isContainer: Bool {
        switch self {
        case .array, .object:
            return true
        case .string, .number, .bool, .null:
            return false
        }
    }
}

private extension Array where Element == URL {
    nonisolated func removingDuplicateURLs() -> [URL] {
        var seen = Set<String>()
        var result = [URL]()
        for url in self {
            guard seen.insert(url.absoluteString).inserted else { continue }
            result.append(url)
        }
        return result
    }
}

private extension String {
    nonisolated func replacingPrefix(_ prefix: String, with replacement: String) -> String {
        guard hasPrefix(prefix) else { return self }
        return replacement + dropFirst(prefix.count)
    }

    nonisolated var nonEmptyAppLinkText: String? {
        isEmpty ? nil : self
    }
}

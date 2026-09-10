import Foundation

struct UpdateChecker {
    static let repoPath = "XIaodou0416/Beans-Music"
    static let releasePageURL = URL(string: "https://github.com/\(repoPath)/releases/latest")!
    private static let latestAPI = URL(string: "https://api.github.com/repos/\(repoPath)/releases/latest")!
    private static let releasesAPI = URL(string: "https://api.github.com/repos/\(repoPath)/releases?per_page=100")!
    private static let serverUpdateAPI = URL(string: "http://189.24.78.193/beans/update.json")!
    private static let serverHistoryAPI = URL(string: "http://189.24.78.193/beans/updates.json")!
    private static let minimumHistoryVersion = "1.6.5"
    private static let suppressedVersionKey = "beans.updateCheck.suppressedVersion"

    struct ReleaseInfo {
        let version: String
        let name: String
        let body: String
        let htmlURL: URL
        let assetURL: URL?
        let notesImageURL: URL?
        let notesTextColorHex: String?
    }

    enum CheckResult {
        case update(ReleaseInfo)
        case upToDate
        case failed
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    static func checkIfNeeded() async -> ReleaseInfo? {
        guard let info = try? await fetchLatest(), isNewer(info.version, than: currentVersion) else { return nil }
        if UserDefaults.standard.string(forKey: suppressedVersionKey) == info.version { return nil }
        return info
    }

    static func checkNow() async -> CheckResult {
        do {
            let info = try await fetchLatest()
            return isNewer(info.version, than: currentVersion) ? .update(info) : .upToDate
        } catch {
            return .failed
        }
    }

    static func suppress(version: String) {
        UserDefaults.standard.set(version, forKey: suppressedVersionKey)
        UserDefaults.standard.synchronize()
    }

    static func fetchLatest() async throws -> ReleaseInfo {
        // 后端公告可以直接指向 IPA；后端不可用时再回退到 GitHub Releases。
        if let serverInfo = try? await fetchServerLatest() {
            return serverInfo
        }
        var request = URLRequest(url: latestAPI)
        request.setValue("Beans-Music/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let html = json["html_url"] as? String,
              let url = URL(string: html) else {
            throw URLError(.cannotParseResponse)
        }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let assetURL: URL? = (json["assets"] as? [[String: Any]])?
            .compactMap { $0["browser_download_url"] as? String }
            .first(where: { $0.lowercased().hasSuffix(".ipa") })
            .flatMap { URL(string: $0) }
        return ReleaseInfo(
            version: version,
            name: json["name"] as? String ?? tag,
            body: json["body"] as? String ?? "",
            htmlURL: url,
            assetURL: assetURL,
            notesImageURL: nil,
            notesTextColorHex: nil
        )
    }

    static func fetchHistory() async throws -> [ReleaseInfo] {
        if let serverHistory = try? await fetchServerHistory(), !serverHistory.isEmpty {
            return serverHistory.filter { !isNewer(minimumHistoryVersion, than: $0.version) }
        }
        let githubHistory = try await fetchGitHubHistory()
        return githubHistory.filter { !isNewer(minimumHistoryVersion, than: $0.version) }
    }

    /// 优先读取 Beans 后端发布配置，失败时由 fetchLatest 回退 GitHub。
    private static func fetchServerLatest() async throws -> ReleaseInfo {
        var request = URLRequest(url: serverUpdateAPI)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Beans-Music/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let payload = try JSONDecoder().decode(ServerUpdatePayload.self, from: data)
        guard !payload.version.isEmpty else {
            throw URLError(.cannotParseResponse)
        }
        return releaseInfo(from: payload)
    }

    private static func fetchServerHistory() async throws -> [ReleaseInfo] {
        var request = URLRequest(url: serverHistoryAPI)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Beans-Music/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let payload = try JSONDecoder().decode(ServerUpdateHistoryPayload.self, from: data)
        let records = payload.updates.isEmpty
            ? payload.latest.map { [$0] } ?? []
            : payload.updates
        return records
            .filter { !$0.version.isEmpty }
            .map { releaseInfo(from: $0) }
    }

    private static func fetchGitHubHistory() async throws -> [ReleaseInfo] {
        var request = URLRequest(url: releasesAPI)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Beans-Music/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let releases = try JSONDecoder().decode([GitHubReleasePayload].self, from: data)
        return releases.compactMap { release in
            guard !release.draft, !release.prerelease,
                  let tag = release.tagName,
                  let htmlURL = URL(string: release.htmlURL) else { return nil }
            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let assetURL = release.assets
                .compactMap { URL(string: $0.browserDownloadURL) }
                .first(where: { $0.pathExtension.lowercased() == "ipa" })
            return ReleaseInfo(
                version: version,
                name: release.name ?? tag,
                body: release.body ?? "",
                htmlURL: htmlURL,
                assetURL: assetURL,
                notesImageURL: nil,
                notesTextColorHex: nil
            )
        }
    }

    private static func releaseInfo(from payload: ServerUpdatePayload) -> ReleaseInfo {
        let assetURL = payload.ipaURL.flatMap(URL.init(string:))
        return ReleaseInfo(
            version: payload.version,
            name: payload.title.isEmpty ? "Beans Music \(payload.version)" : payload.title,
            body: payload.notes.joined(separator: "\n"),
            htmlURL: assetURL ?? releasePageURL,
            assetURL: assetURL,
            notesImageURL: payload.notesImageURL.flatMap(URL.init(string:)),
            notesTextColorHex: payload.notesTextColor
        )
    }

    static func isNewer(_ remote: String, than current: String) -> Bool {
        func parts(_ v: String) -> [Int] {
            v.split(separator: ".").compactMap { Int($0) }
        }
        let r = parts(remote)
        let c = parts(current)
        let count = max(r.count, c.count)
        for i in 0..<count {
            let a = i < r.count ? r[i] : 0
            let b = i < c.count ? c[i] : 0
            if a != b { return a > b }
        }
        return false
    }

}

private struct ServerUpdatePayload: Decodable {
    let version: String
    let title: String
    let notes: [String]
    let ipaURL: String?
    let notesImageURL: String?
    let notesTextColor: String?

    enum CodingKeys: String, CodingKey {
        case version
        case title
        case notes
        case ipaURL = "ipa_url"
        case notesImageURL = "notes_image_url"
        case notesTextColor = "notes_text_color"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(String.self, forKey: .version) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        ipaURL = try container.decodeIfPresent(String.self, forKey: .ipaURL)
        notesImageURL = try container.decodeIfPresent(String.self, forKey: .notesImageURL)
        notesTextColor = try container.decodeIfPresent(String.self, forKey: .notesTextColor)
        if let values = try? container.decode([String].self, forKey: .notes) {
            notes = values
        } else if let value = try? container.decode(String.self, forKey: .notes) {
            notes = value.isEmpty ? [] : [value]
        } else {
            notes = []
        }
    }
}

private struct ServerUpdateHistoryPayload: Decodable {
    let latest: ServerUpdatePayload?
    let updates: [ServerUpdatePayload]

    enum CodingKeys: String, CodingKey {
        case latest
        case updates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        latest = try container.decodeIfPresent(ServerUpdatePayload.self, forKey: .latest)
        updates = try container.decodeIfPresent([ServerUpdatePayload].self, forKey: .updates) ?? []
    }
}

private struct GitHubReleasePayload: Decodable {
    let tagName: String?
    let name: String?
    let body: String?
    let htmlURL: String
    let draft: Bool
    let prerelease: Bool
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case draft
        case prerelease
        case assets
    }

    struct GitHubAsset: Decodable {
        let browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case browserDownloadURL = "browser_download_url"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tagName = try container.decodeIfPresent(String.self, forKey: .tagName)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        htmlURL = try container.decode(String.self, forKey: .htmlURL)
        draft = try container.decodeIfPresent(Bool.self, forKey: .draft) ?? false
        prerelease = try container.decodeIfPresent(Bool.self, forKey: .prerelease) ?? false
        assets = try container.decodeIfPresent([GitHubAsset].self, forKey: .assets) ?? []
    }
}

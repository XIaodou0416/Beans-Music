import Foundation

// MARK: - 更新检测（GitHub Releases API）

/// 检测 GitHub 最新 Release 并与当前版本比较，发现新版时用于弹窗提示。
/// 自动检查每次启动一次，手动检查随时可用。
struct UpdateChecker {
    static let repoPath = "XIaodou0416/Beans-Music"
    static let releasePageURL = URL(string: "https://github.com/\(repoPath)/releases/latest")!
    private static let latestAPI = URL(string: "https://api.github.com/repos/\(repoPath)/releases/latest")!
    private static let serverUpdateAPI = URL(string: "http://189.24.78.193/beans/update.json")!
    private static let suppressedVersionKey = "beans.updateCheck.suppressedVersion"

    /// 最新 Release 信息
    struct ReleaseInfo {
        let version: String
        let name: String
        let body: String
        let htmlURL: URL
        /// Release 附带的 IPA 安装包直链（用于自动下载）
        let assetURL: URL?
    }

    enum CheckResult {
        case update(ReleaseInfo)
        case upToDate
        case failed
    }

    /// 当前 App 版本号（CFBundleShortVersionString）
    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    /// 自动检查：每次启动请求一次。用户选择“以后再说”后，才不再提醒当前版本。
    static func checkIfNeeded() async -> ReleaseInfo? {
        guard let info = try? await fetchLatest(), isNewer(info.version, than: currentVersion) else { return nil }
        if UserDefaults.standard.string(forKey: suppressedVersionKey) == info.version { return nil }
        return info
    }

    /// 手动检查：总是请求，返回明确结果（有新版本 / 已是最新 / 检查失败）
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

    /// 拉取最新 Release（公开仓库无需 Token）
    static func fetchLatest() async throws -> ReleaseInfo {
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
        // 从 Release 资产中找出 .ipa 安装包直链
        let assetURL: URL? = (json["assets"] as? [[String: Any]])?
            .compactMap { $0["browser_download_url"] as? String }
            .first(where: { $0.lowercased().hasSuffix(".ipa") })
            .flatMap { URL(string: $0) }
        return ReleaseInfo(
            version: version,
            name: json["name"] as? String ?? tag,
            body: json["body"] as? String ?? "",
            htmlURL: url,
            assetURL: assetURL
        )
    }

    /// 优先读取 Beans 后台发布配置；失败时由 fetchLatest 自动回落 GitHub Releases。
    static func fetchServerLatest() async throws -> ReleaseInfo {
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
        let assetURL = payload.ipaURL.flatMap(URL.init(string:))
        return ReleaseInfo(
            version: payload.version,
            name: payload.title.isEmpty ? "Beans Music \(payload.version)" : payload.title,
            body: payload.notes.joined(separator: "\n"),
            htmlURL: assetURL ?? releasePageURL,
            assetURL: assetURL
        )
    }

    /// 三段式版本号比较：remote 大于 current 返回 true
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

    enum CodingKeys: String, CodingKey {
        case version
        case title
        case notes
        case ipaURL = "ipa_url"
    }
}

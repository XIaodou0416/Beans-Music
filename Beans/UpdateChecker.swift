import Foundation

struct UpdateChecker {
    static let repoPath = "XIaodou0416/Beans-Music"
    static let releasePageURL = URL(string: "https://github.com/\(repoPath)/releases/latest")!
    private static let latestAPI = URL(string: "https://api.github.com/repos/\(repoPath)/releases/latest")!
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

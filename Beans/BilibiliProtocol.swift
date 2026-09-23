import Foundation

/// Parsing shared by login and playback. Pure helpers also run in the CI regression checks.
enum BilibiliProtocol {
    static let cookieNames = ["SESSDATA", "bili_jct", "DedeUserID", "DedeUserID__ckMd5", "sid"]

    static func cookieValues(_ raw: String) -> [String: String] {
        var values: [String: String] = [:]
        for part in raw.split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { continue }
            let name = pair[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = pair[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard cookieNames.contains(name), !value.isEmpty,
                  !value.contains("\r"), !value.contains("\n") else { continue }
            values[name] = value
        }
        return values
    }

    static func cookieHeader(_ values: [String: String]) -> String {
        cookieNames.compactMap { name in
            guard let value = values[name], !value.isEmpty else { return nil }
            return "\(name)=\(value)"
        }.joined(separator: "; ")
    }

    static func normalizeCookie(_ raw: String) -> String { cookieHeader(cookieValues(raw)) }
    static func hasSession(_ raw: String) -> Bool { cookieValues(raw)["SESSDATA"] != nil }

    static func loginURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw), url.scheme?.lowercased() == "https",
              url.user == nil, url.password == nil,
              let host = url.host?.lowercased(),
              ["passport.bilibili.com", "passport.biligame.com"].contains(host),
              url.port == nil || url.port == 443 else { return nil }
        return url
    }

    static func queryCookies(from url: URL) -> [String: String] {
        guard loginURL(url.absoluteString) != nil,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return [:] }
        // Keep the percent encoding used by SESSDATA; decoding it into a Cookie
        // header changes the token on the legacy QR success response.
        var values: [String: String] = [:]
        for part in (components.percentEncodedQuery ?? "").split(separator: "&") {
            let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { continue }
            let name = String(pair[0]).removingPercentEncoding ?? String(pair[0])
            if cookieNames.contains(name), !pair[1].isEmpty { values[name] = String(pair[1]) }
        }
        return values
    }

    static func responseCookies(_ response: HTTPURLResponse) -> [String: String] {
        guard let url = response.url else { return [:] }
        let fields = response.allHeaderFields.reduce(into: [String: String]()) { result, field in
            result[String(describing: field.key)] = String(describing: field.value)
        }
        var values: [String: String] = [:]
        for cookie in HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
            where cookieNames.contains(cookie.name) && !cookie.value.isEmpty {
            values[cookie.name] = cookie.value
        }
        // HTTPURLResponse can fold several Set-Cookie fields into one header.
        // Split only before a cookie assignment, never at the comma in Expires.
        for (name, raw) in fields where name.lowercased() == "set-cookie" {
            let split = raw.replacingOccurrences(of: #",\s*(?=[A-Za-z0-9_\-]+=)"#, with: "\n", options: .regularExpression)
            for line in split.split(separator: "\n") {
                let first = String(line.split(separator: ";", maxSplits: 1).first ?? "")
                for (key, value) in cookieValues(first) { values[key] = value }
            }
        }
        return values
    }

    static func audioURLs(_ response: [String: Any], preferredID: Int) -> [URL] {
        let dash = response["dash"] as? [String: Any] ?? [:]
        let audio = (dash["audio"] as? [[String: Any]] ?? []).filter { item in
            let codec = (item["codecs"] as? String ?? "").lowercased()
            let id = integer(item["id"])
            return codec.hasPrefix("mp4a") || (codec.isEmpty && [30216, 30232, 30280].contains(id))
        }.sorted { lhs, rhs in
            let left = integer(lhs["id"]), right = integer(rhs["id"])
            if (left == preferredID) != (right == preferredID) { return left == preferredID }
            return integer(lhs["bandwidth"]) > integer(rhs["bandwidth"])
        }
        var seen = Set<String>()
        return audio.flatMap { item -> [URL] in
            let primary = [item["baseUrl"], item["base_url"]].compactMap { $0 as? String }
            let backups = (item["backupUrl"] as? [String] ?? []) + (item["backup_url"] as? [String] ?? [])
            // Prefer conventional HTTPS CDN endpoints over peer CDN ports.
            return (primary + backups).compactMap(mediaURL).enumerated().sorted { lhs, rhs in
                let left = priority(lhs.element), right = priority(rhs.element)
                return left == right ? lhs.offset < rhs.offset : left < right
            }.map(\.element)
        }.filter { seen.insert($0.absoluteString).inserted }
    }

    static func progressiveURLs(_ response: [String: Any]) -> [URL] {
        guard let segments = response["durl"] as? [[String: Any]], segments.count == 1,
              let segment = segments.first else { return [] }
        let format = (response["format"] as? String ?? "").lowercased()
        guard format.contains("mp4") else { return [] }
        let values = [segment["url"] as? String].compactMap { $0 } + (segment["backup_url"] as? [String] ?? [])
        var seen = Set<String>()
        return values.compactMap(mediaURL).filter { seen.insert($0.absoluteString).inserted }
    }

    private static func integer(_ value: Any?) -> Int {
        (value as? NSNumber)?.intValue ?? Int(value as? String ?? "") ?? 0
    }
    private static func mediaURL(_ value: String) -> URL? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value.hasPrefix("//") ? "https:" + value : value),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }
    private static func priority(_ url: URL) -> Int {
        let host = url.host?.lowercased() ?? ""
        if url.scheme == "https", url.port == nil || url.port == 443 {
            return host.hasSuffix(".bilivideo.com") ? 0 : 1
        }
        return 2
    }
}

/// QR tickets may issue cookies on an intermediate redirect. Keep each response
/// and follow only the two passport hosts, without automatic cookie forwarding.
final class BilibiliLoginRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

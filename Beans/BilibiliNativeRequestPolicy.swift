import Foundation
import CoreGraphics

/// Explicit write actions share one request contract. This builder does not send
/// network traffic and can be verified with fixture credentials in CI.
enum BilibiliNativeRequestPolicy {
    static let allowedPaths: Set<String> = [
        "/x/web-interface/archive/like", "/x/web-interface/coin/add", "/x/v3/fav/resource/deal",
        "/x/relation/modify", "/x/v2/reply/add", "/x/v2/reply/action"
    ]
    enum Failure: Error { case invalidPath, missingLogin, missingCSRF }
    static func request(path: String, fields: [String: String], cookie: String) throws -> URLRequest {
        guard allowedPaths.contains(path) else { throw Failure.invalidPath }
        let cookie = BilibiliProtocol.normalizeCookie(cookie)
        let values = BilibiliProtocol.cookieValues(cookie)
        guard values["SESSDATA"] != nil else { throw Failure.missingLogin }
        guard let csrf = values["bili_jct"], !csrf.isEmpty else { throw Failure.missingCSRF }
        var body = fields
        body["csrf"] = csrf; body["csrf_token"] = csrf
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        func encode(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: allowed) ?? "" }
        var request = URLRequest(url: URL(string: "https://api.bilibili.com" + path)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.keys.sorted().map { encode($0) + "=" + encode(body[$0]!) }.joined(separator: "&").data(using: .utf8)
        return request
    }
}

enum BeansWindowLayoutPolicy {
    static func usesSidebar(isPad: Bool, window: CGSize, proposed: CGSize) -> Bool {
        let size = window.width > 0 && window.height > 0 ? window : proposed
        return isPad && size.width > size.height
    }
}

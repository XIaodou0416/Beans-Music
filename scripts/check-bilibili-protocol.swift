import Foundation

@main
struct BilibiliProtocolChecks {
    static func main() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            count += 1
            print("PASS: \(name)")
        }
        let raw = "DedeUserID=123; SESSDATA=test%2Ctoken==; bili_jct=csrf; Path=/"
        let normalized = BilibiliProtocol.normalizeCookie(raw)
        check(BilibiliProtocol.hasSession(normalized), "SESSDATA after semicolon whitespace survives normalization")
        check(BilibiliProtocol.cookieValues(normalized)["SESSDATA"] == "test%2Ctoken==", "encoded tokens and embedded equals are preserved")
        check(!BilibiliProtocol.hasSession("DedeUserID=123; SESSDATA= ; Path=/"), "empty session rejected")
        check(!normalized.contains("Path="), "response attributes never become login cookies")
        check(!BilibiliProtocol.hasSession("SESSDATA=abc\r\ninjected:value"), "header injection rejected")
        let legacy = URL(string: "https://passport.bilibili.com/crossDomain?SESSDATA=a%2Cb%2Fc&bili_jct=csrf")!
        check(BilibiliProtocol.queryCookies(from: legacy)["SESSDATA"] == "a%2Cb%2Fc", "legacy URL cookie percent encoding retained")
        check(BilibiliProtocol.loginURL("https://passport.biligame.com/x/passport-login/web/crossDomain?ticket=test") != nil, "new cross-domain login host accepted")
        check(BilibiliProtocol.loginURL("https://passport.bilibili.com.evil.example/crossDomain") == nil, "untrusted redirect host rejected")
        check(BilibiliProtocol.loginURL("http://passport.bilibili.com/crossDomain") == nil, "insecure ticket URL rejected")
        let headers = ["Set-Cookie": "DedeUserID=123; Path=/; Expires=Wed, 01 Jan 2031 00:00:00 GMT, SESSDATA=demo%2Ccookie; Path=/; HttpOnly, bili_jct=csrf; Path=/"]
        let response = HTTPURLResponse(url: legacy, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: headers)!
        let cookies = BilibiliProtocol.responseCookies(response)
        check(cookies["SESSDATA"] == "demo%2Ccookie" && cookies["bili_jct"] == "csrf", "folded Set-Cookie with Expires parsed")
        let fixture: [String: Any] = ["dash": ["audio": [
            ["id": 30216, "codecs": "mp4a.40.2", "baseUrl": "https://a.bilivideo.com/low.m4s", "bandwidth": 64000],
            ["id": 30280, "codecs": "mp4a.40.2", "baseUrl": "https://peer.mcdn.bilivideo.cn:8082/high.m4s", "backupUrl": ["https://a.bilivideo.com/high.m4s", "https://a.bilivideo.com/high.m4s"], "bandwidth": 192000],
            ["id": 30250, "codecs": "ec-3", "baseUrl": "https://a.bilivideo.com/dolby.m4s"],
            ["id": "30232", "base_url": "", "backup_url": ["//a.bilivideo.com/mid.m4s"], "bandwidth": "128000"]
        ]]]
        let urls = BilibiliProtocol.audioURLs(fixture, preferredID: 30280)
        check(urls.first?.absoluteString == "https://a.bilivideo.com/high.m4s", "preferred AAC uses conventional CDN before peer port")
        check(urls.count == 4, "deduplication and unsupported codec filtering")
        check(urls.contains(where: { $0.path == "/mid.m4s" }), "known AAC IDs with missing codec and backup-only address supported")
        check(BilibiliProtocol.audioURLs(fixture, preferredID: 30216).first?.path == "/low.m4s", "standard quality preference respected")
        check(BilibiliProtocol.audioURLs(["dash": ["audio": [["id": 30280, "baseUrl": "javascript:test"]]]], preferredID: 30280).isEmpty, "non-HTTP media address rejected")
        check(BilibiliProtocol.progressiveURLs(["format": "mp4", "durl": [["url": "https://a.bilivideo.com/movie.mp4"]]]).count == 1, "single progressive MP4 accepted")
        check(BilibiliProtocol.progressiveURLs(["format": "flv", "durl": [["url": "https://a.bilivideo.com/movie.flv"]]]).isEmpty, "FLV not given to AVPlayer")
        check(BilibiliProtocol.progressiveURLs(["format": "mp4", "durl": [["url": "https://a.bilivideo.com/1.mp4"], ["url": "https://a.bilivideo.com/2.mp4"]]]).isEmpty, "multi-segment response never silently truncated")
        print("Bilibili protocol: \(count) checks passed")
    }
}

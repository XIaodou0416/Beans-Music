import Foundation

/// QQ 音乐扫码登录（逆向自 wp_MusicApi util/login_qq_scan.js，仅供学习交流）
/// 流程：ptqrshow 生成二维码 -> ptqrlogin 轮询扫码状态 -> check_sig 拿 skey/p_skey
///      -> graph.qq.com oauth2 authorize 换 code -> musicu.fcg QQConnectLogin 换 musickey
/// 登录后播放请求携带 qq.com 域 Cookie（p_skey / qqmusic_key），QQ 歌曲播放成功率显著提升。
final class QQMusicAuth: ObservableObject {
    static let shared = QQMusicAuth()

    @Published private(set) var isLoggedIn = false
    @Published private(set) var nickname = ""
    /// QQ 音乐会员标识：nil 无 / "VIP" / "SVIP"（登录后尽力拉取，失败不阻塞）
    @Published private(set) var vipBadge: String?

    private var cookies: [String: String] = [:]
    private var qrsig = ""

    private let defaults = UserDefaults.standard
    private let cookieKey = "beans.qqmusic.cookie.v1"
    private let nickKey = "beans.qqmusic.nickname.v1"
    private let vipKey = "beans.qqmusic.vip.v1"
    private let session: URLSession
    private let redirectBlocker = NoRedirectDelegate()

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        session = URLSession(configuration: config, delegate: redirectBlocker, delegateQueue: nil)
        if let saved = defaults.dictionary(forKey: cookieKey) as? [String: String], !saved.isEmpty {
            cookies = saved
            isLoggedIn = true
            nickname = defaults.string(forKey: nickKey) ?? ""
            vipBadge = defaults.string(forKey: vipKey)
        }
    }

    // MARK: - 登录状态

    /// 登录账号 ID。QQ 登录通常使用 uin，微信登录通常使用 wxuin。
    var uin: String {
        Self.normalizedUIN(Self.accountID(from: cookies))
    }

    /// 原始账号 ID（保留 o 前缀，歌单增删等写操作接口需要）。
    /// 微信网页登录没有 uin 时回退到 wxuin。
    var rawUin: String {
        Self.accountID(from: cookies)
    }

    var isWeChatLogin: Bool {
        Self.hasUsableAccountID(cookies["wxuin"]) || !(cookies["wxopenid"] ?? "").isEmpty
    }

    /// QQ 歌单接口使用的 QQ 账号 ID。微信登录通常没有可用的 QQ uin，
    /// 此时返回 0，让官方接口根据 wxuin / wxopenid Cookie 识别账号。
    var playlistUin: String {
        if isWeChatLogin,
           !Self.hasUsableAccountID(cookies["p_uin"]),
           !Self.hasUsableAccountID(cookies["pt2gguin"]) {
            return "0"
        }
        for key in ["uin", "p_uin", "pt2gguin"] {
            guard let value = cookies[key],
                  Self.hasUsableAccountID(value) else { continue }
            return Self.normalizedUIN(value)
        }
        return "0"
    }

    /// g_tk（写操作接口签名；QQ/微信登录均优先使用音乐域凭证）。
    var gtk: Int {
        let key = cookies["qqmusic_key"]
            ?? cookies["qm_keyst"]
            ?? cookies["wxskey"]
            ?? cookies["p_skey"]
            ?? cookies["skey"]
            ?? ""
        return key.isEmpty ? 5381 : Self.hash5381(key)
    }

    /// 播放接口 authst。QQ vkey 优先识别音乐域凭证，p_skey 仅作旧登录态兜底。
    var loginKey: String {
        cookies["qm_keyst"] ?? cookies["qqmusic_key"] ?? cookies["music_key"]
            ?? cookies["wxskey"] ?? cookies["musickey"] ?? cookies["p_skey"] ?? ""
    }

    /// 发给 u.y.qq.com 的 Cookie 串（含 qqmusic_key 时 VIP 歌曲播放成功率最高）
    var cookieHeader: String {
        makeCookieHeader(includeCompatibilityUIN: true)
    }

    /// 不注入兼容用的 uin=wxuin，给微信登录的歌单接口使用。
    /// 部分 QQ 接口会优先读取 uin，误把 wxuin 当成 QQ uin 后会返回空歌单。
    var playlistCookieHeader: String {
        makeCookieHeader(includeCompatibilityUIN: false)
    }

    private func makeCookieHeader(includeCompatibilityUIN: Bool) -> String {
        let order = [
            "uin", "wxuin", "p_uin", "wxopenid",
            "qm_keyst", "qqmusic_key", "music_key", "wxskey", "wx_skey",
            "musickey", "p_skey", "skey", "pt4_token"
        ]
        var pairs: [String] = order.compactMap { key in
            guard let value = cookies[key], !value.isEmpty else { return nil }
            return "\(key)=\(value)"
        }
        // 旧版保存的微信登录态可能只有 wxuin；部分 QQ 接口仍只读取 uin。
        if includeCompatibilityUIN,
           !Self.hasUsableAccountID(cookies["uin"]),
           let wxuin = cookies["wxuin"],
           !wxuin.isEmpty {
            pairs.insert("uin=\(wxuin)", at: 0)
        }
        return pairs.joined(separator: "; ")
    }

    func logout() {
        cookies = [:]
        qrsig = ""
        isLoggedIn = false
        nickname = ""
        vipBadge = nil
        defaults.removeObject(forKey: cookieKey)
        defaults.removeObject(forKey: nickKey)
        defaults.removeObject(forKey: vipKey)
    }

    // MARK: - 网页登录 / Cookie 导入

    /// 网页登录（WKWebView 读取）或手动粘贴 Cookie 导入登录态
    func importCookies(_ dict: [String: String], nickname: String?) {
        guard !dict.isEmpty else { return }
        cookies = dict
        isLoggedIn = true
        self.nickname = nickname ?? Self.fallbackNickname(dict)
        defaults.set(cookies, forKey: cookieKey)
        defaults.set(self.nickname, forKey: nickKey)
        NotificationCenter.default.post(name: .beansQQLoginDidUpdate, object: nil)
        // 登录成功后异步刷新会员标识与真实昵称（失败静默降级）
        Task { await self.fetchVIPStatus() }
        Task { await self.fetchProfile() }
    }

    /// 返回网页登录 Cookie 缺少哪一部分，便于区分 QQ 登录和微信登录失败原因。
    static func loginValidationMessage(_ dict: [String: String]) -> String? {
        guard hasUsableAccountID(accountID(from: dict)) else {
            return "未读取到 QQ/微信账号标识，请确认网页登录已经完成"
        }

        let credentialKeys = [
            "p_skey", "skey", "qqmusic_key", "qm_keyst",
            "music_key", "wxskey", "wx_skey", "musickey"
        ]
        guard credentialKeys.contains(where: { !(dict[$0] ?? "").isEmpty }) else {
            return "已读取到账号，但缺少 QQ 音乐登录凭证，请在网页中重新登录后再同步"
        }
        return nil
    }

    /// Cookie 是否包含有效登录态，兼容 QQ 登录的 uin 和微信登录的 wxuin。
    func hasValidLogin(_ dict: [String: String]) -> Bool {
        Self.loginValidationMessage(dict) == nil
    }

    /// 网页登录关注的 Cookie 名（WKWebView 读取时按此过滤）
    static let webCookieNames: Set<String> = [
        "uin", "wxuin", "p_uin", "wxopenid", "skey", "p_skey",
        "qqmusic_key", "qm_keyst", "music_key", "wxskey", "wx_skey",
        "musickey", "pt4_token", "pt2gguin", "pt_login_sig", "pt4_aid",
        "qmusic_s", "pgv_pvid", "pgv_info", "ptnick", "nick", "nickname",
    ]

    /// 解析浏览器复制出来的完整 Cookie 字符串："a=b; c=d"
    static func parseCookieHeader(_ header: String) -> [String: String] {
        var dict: [String: String] = [:]
        for part in header.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard kv.count == 2 else { continue }
            let key = kv[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = kv[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty, !value.isEmpty {
                dict[key] = value
            }
        }
        return dict
    }

    /// QQ/微信账号 ID 转显示昵称；优先 ptlogin 下发的 ptnick_* / nick Cookie。
    static func fallbackNickname(_ dict: [String: String]) -> String {
        if let key = dict.keys.first(where: { $0.hasPrefix("ptnick") }),
           let raw = dict[key], !raw.isEmpty {
            return raw.removingPercentEncoding ?? raw
        }
        if let nick = dict["nick"], !nick.isEmpty { return nick }
        let clean = normalizedUIN(accountID(from: dict))
        return clean.isEmpty ? "QQ音乐用户" : "QQ音乐用户 \(clean)"
    }

    private static func accountID(from cookies: [String: String]) -> String {
        for key in ["uin", "wxuin", "pt2gguin"] {
            guard let value = cookies[key],
                  hasUsableAccountID(value) else { continue }
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "0"
    }

    private static func hasUsableAccountID(_ raw: String?) -> Bool {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return false }
        return value != "0" && value != "o0"
    }

    private static func normalizedUIN(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }
        return value.hasPrefix("o") ? String(value.dropFirst()) : value
    }
    // MARK: - 扫码登录

    enum ScanState: Equatable {
        case waiting
        case scanned
        case success(String)   // 昵称
        case expired
        case error(String)
    }

    /// 获取二维码图片（PNG），并保存 qrsig 供轮询使用
    func fetchQRCode() async throws -> Data {
        qrsig = ""
        var comps = URLComponents(string: "https://ssl.ptlogin2.qq.com/ptqrshow")!
        comps.queryItems = [
            URLQueryItem(name: "appid", value: "716027609"),
            URLQueryItem(name: "e", value: "2"),
            URLQueryItem(name: "l", value: "M"),
            URLQueryItem(name: "s", value: "3"),
            URLQueryItem(name: "d", value: "72"),
            URLQueryItem(name: "v", value: "4"),
            URLQueryItem(name: "t", value: String(format: "%.6f", Double.random(in: 0...1))),
            URLQueryItem(name: "daid", value: "383"),
            URLQueryItem(name: "pt_3rd_aid", value: "100497308"),
        ]
        var request = URLRequest(url: comps.url!)
        request.setValue(Self.ua, forHTTPHeaderField: "User-Agent")
        request.setValue("https://xui.ptlogin2.qq.com/", forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: request)
        collectCookies(from: response)
        guard let qr = cookies["qrsig"], !qr.isEmpty else {
            throw NetEaseError.unknown("获取 QQ 二维码失败，请检查网络后重试")
        }
        qrsig = qr
        return data
    }

    /// 单次轮询扫码状态（调用方以 3 秒间隔重复调用）
    func poll() async throws -> ScanState {
        guard !qrsig.isEmpty else { return .expired }
        var comps = URLComponents(string: "https://ssl.ptlogin2.qq.com/ptqrlogin")!
        comps.queryItems = [
            URLQueryItem(name: "u1", value: "https://graph.qq.com/oauth2.0/login_jump"),
            URLQueryItem(name: "ptqrtoken", value: "\(Self.hash33(qrsig))"),
            URLQueryItem(name: "ptredirect", value: "0"),
            URLQueryItem(name: "h", value: "1"),
            URLQueryItem(name: "t", value: "1"),
            URLQueryItem(name: "g", value: "1"),
            URLQueryItem(name: "from_ui", value: "1"),
            URLQueryItem(name: "ptlang", value: "2052"),
            URLQueryItem(name: "action", value: "0-0-\\(Int(Date().timeIntervalSince1970 * 1000))"),
            URLQueryItem(name: "js_ver", value: "22080914"),
            URLQueryItem(name: "js_type", value: "1"),
            URLQueryItem(name: "login_sig", value: ""),
            URLQueryItem(name: "pt_uistyle", value: "40"),
            URLQueryItem(name: "aid", value: "716027609"),
            URLQueryItem(name: "daid", value: "383"),
            URLQueryItem(name: "pt_3rd_aid", value: "100497308"),
            URLQueryItem(name: "o1vId", value: "49283d5cbb01a744d46314da4608d929"),
        ]
        var request = URLRequest(url: comps.url!)
        request.setValue(Self.ua, forHTTPHeaderField: "User-Agent")
        request.setValue("https://xui.ptlogin2.qq.com/", forHTTPHeaderField: "Referer")
        request.setValue("qrsig=\(qrsig)", forHTTPHeaderField: "Cookie")
        let (data, response) = try await session.data(for: request)
        collectCookies(from: response)
        guard let text = String(data: data, encoding: .utf8),
              let parsed = Self.parsePTUI(text) else {
            return .error("QQ 登录接口异常，请重试")
        }
        switch parsed.code {
        case "0":
            guard let url = parsed.url else { return .error("登录成功但凭证获取失败") }
            do {
                try await completeOAuth(redirectURL: url)
            } catch {
                return .error(error.localizedDescription)
            }
            nickname = parsed.nickname
            isLoggedIn = true
            defaults.set(cookies, forKey: cookieKey)
            defaults.set(nickname, forKey: nickKey)
            Task { await self.fetchVIPStatus() }
            Task { await self.fetchProfile() }
            return .success(parsed.nickname)
        case "65", "68":
            return .expired
        case "67":
            return .scanned
        case "66":
            return .waiting
        default:
            return .waiting
        }
    }

    // MARK: - 授权换 musickey

    private func completeOAuth(redirectURL: String) async throws {
        // check_sig 跳转链必须携带 qrsig（ptlogin2.qq.com 域），否则校验失败、拿不到 skey/p_skey
        var loginCookie = cookieHeader
        if !qrsig.isEmpty {
            loginCookie = "qrsig=\(qrsig)" + (loginCookie.isEmpty ? "" : "; " + loginCookie)
        }
        // 1. 依次访问 check_sig 跳转链，收集 skey / p_skey（最多 6 跳）
        var current = redirectURL
        for _ in 0..<6 {
            guard let url = URL(string: current) else { break }
            var request = URLRequest(url: url)
            request.setValue(Self.ua, forHTTPHeaderField: "User-Agent")
            request.setValue("https://xui.ptlogin2.qq.com/", forHTTPHeaderField: "Referer")
            request.setValue(loginCookie, forHTTPHeaderField: "Cookie")
            let (_, response) = try await session.data(for: request)
            collectCookies(from: response)
            loginCookie = cookieHeader
            if !qrsig.isEmpty {
                loginCookie = "qrsig=\(qrsig)" + (loginCookie.isEmpty ? "" : "; " + loginCookie)
            }
            guard let http = response as? HTTPURLResponse,
                  (300...399).contains(http.statusCode),
                  let location = http.value(forHTTPHeaderField: "Location"),
                  !location.isEmpty else { break }
            if let locURL = URL(string: location), locURL.scheme != nil {
                current = location
            } else if let base = URL(string: current),
                      let resolved = URL(string: location, relativeTo: base) {
                current = resolved.absoluteString
            } else {
                break
            }
        }

        // 2. graph.qq.com oauth2 authorize 换 code
        loginCookie = cookieHeader
        let gtk = Self.hash5381(cookies["qqmusic_key"] ?? cookies["p_skey"] ?? cookies["skey"] ?? "")
        let fields: [String: String] = [
            "response_type": "code",
            "client_id": "100497308",
            "redirect_uri": "https://y.qq.com/portal/wx_redirect.html?login_type=1&surl=https://y.qq.com/",
            "scope": "all",
            "state": "state",
            "switch": "",
            "from_ptlogin": "1",
            "src": "1",
            "update_auth": "1",
            "openapi": "80901010_1030",
            "g_tk": "\(gtk)",
            "auth_time": "\(Int(Date().timeIntervalSince1970 * 1000))",
            "ui": "DFEC5395-9E69-4D3E-96A6-300BB770874D",
        ]
        var authRequest = URLRequest(url: URL(string: "https://graph.qq.com/oauth2.0/authorize")!)
        authRequest.httpMethod = "POST"
        authRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        authRequest.setValue(Self.ua, forHTTPHeaderField: "User-Agent")
        authRequest.setValue("https://graph.qq.com/", forHTTPHeaderField: "Referer")
        authRequest.setValue(loginCookie, forHTTPHeaderField: "Cookie")
        authRequest.httpBody = Self.formEncode(fields).data(using: .utf8)
        let (_, authResponse) = try await session.data(for: authRequest)
        collectCookies(from: authResponse)
        guard let http = authResponse as? HTTPURLResponse,
              let location = http.value(forHTTPHeaderField: "Location"),
              let code = Self.extractCode(from: location) else {
            throw NetEaseError.unknown("QQ 授权失败，请重新扫码")
        }

        // 3. musicu.fcg QQConnectLogin 换 musickey（登录态 Cookie 持久化）
        loginCookie = cookieHeader
        let body = "{\"comm\":{\"g_tk\":5381,\"platform\":\"yqq\",\"ct\":24,\"cv\":0},\"req\":{\"module\":\"QQConnectLogin.LoginServer\",\"method\":\"QQLogin\",\"param\":{\"code\":\"\(code)\"}}}"
        var loginRequest = URLRequest(url: URL(string: "https://u.y.qq.com/cgi-bin/musicu.fcg")!)
        loginRequest.httpMethod = "POST"
        loginRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        loginRequest.setValue(Self.ua, forHTTPHeaderField: "User-Agent")
        loginRequest.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
        loginRequest.setValue(loginCookie, forHTTPHeaderField: "Cookie")
        loginRequest.httpBody = body.data(using: .utf8)
        let (loginData, loginResponse) = try await session.data(for: loginRequest)
        collectCookies(from: loginResponse)
        // 部分 QQ 登录响应把音乐域凭证放在 JSON 中而不是 Set-Cookie，必须显式持久化。
        if let json = try? JSONSerialization.jsonObject(with: loginData) as? [String: Any],
           let req = json["req"] as? [String: Any],
           let data = req["data"] as? [String: Any] {
            if let musicKey = data["musickey"] as? String, !musicKey.isEmpty {
                cookies["musickey"] = musicKey
                cookies["qm_keyst"] = musicKey
                cookies["qqmusic_key"] = musicKey
            }
            if let musicID = data["musicid"] as? Int, musicID > 0 {
                cookies["uin"] = "\(musicID)"
            } else if let musicID = data["musicid"] as? String, !musicID.isEmpty {
                cookies["uin"] = musicID
            }
        }
    }

    // MARK: - 会员状态

    /// 拉取 QQ 音乐会员标识（逆向自 musicu.fcg music.member.getVipInfo，仅供学习交流）。
    /// 携带登录 Cookie 请求，接口字段各家实现略有差异，这里做递归宽松解析：
    /// - 命中 svip 相关字段且数值 > 0 -> SVIP
    /// - 命中 vipType / vip_type 且数值 > 0 -> VIP
    /// - 请求失败或字段缺失 -> nil（不阻塞登录，也不弹错误）
    @MainActor
    func fetchVIPStatus() async {
        guard isLoggedIn, !uin.isEmpty, uin != "0" else {
            if vipBadge != nil {
                vipBadge = nil
                defaults.removeObject(forKey: vipKey)
            }
            return
        }
        do {
            let payload: [String: Any] = [
                "comm": ["ct": 24, "cv": 0, "uin": uin],
                "req_0": [
                    "module": "music.member.getVipInfo",
                    "method": "get_vip_info",
                    "param": ["uin": uin]
                ]
            ]
            let json = try await musicu(payload)
            let badge = Self.parseVIPBadge(json)
            if badge != vipBadge {
                vipBadge = badge
                defaults.set(badge ?? "", forKey: vipKey)
            }
        } catch {
            // 尽力而为：接口波动不影响登录与播放
        }
    }

    /// 递归扫描响应 JSON 中的会员字段（兼容不同返回结构）
    private static func parseVIPBadge(_ json: [String: Any]) -> String? {
        var vipLevel = 0
        var svipFlag = false
        func walk(_ value: Any) {
            if let dict = value as? [String: Any] {
                for (key, v) in dict {
                    let lower = key.lowercased()
                    if lower.contains("svip") {
                        if let n = v as? Int, n > 0 { svipFlag = true }
                        if let b = v as? Bool, b { svipFlag = true }
                    } else if lower == "viptype" || lower == "vip_type" {
                        if let n = v as? Int, n > 0 { vipLevel = max(vipLevel, n) }
                    }
                    walk(v)
                }
            } else if let arr = value as? [Any] {
                arr.forEach(walk)
            }
        }
        walk(json)
        if svipFlag || vipLevel >= 11 { return "SVIP" }
        if vipLevel > 0 { return "VIP" }
        return nil
    }

    /// 拉取 QQ 音乐真实昵称（fcg_get_profile_homepage；扫码/网页/Cookie 登录后调用，失败静默保留旧昵称）
    @MainActor
    func fetchProfile() async {
        guard isLoggedIn, !uin.isEmpty, uin != "0" else { return }
        do {
            let urlString = "https://c.y.qq.com/rsc/fcgi-bin/fcg_get_profile_homepage.fcg?cid=205360838&userid=\(uin)&reqfrom=1&g_tk=5381&loginUin=\(uin)&hostUin=0&format=json&inCharset=utf8&outCharset=utf-8&notice=0&platform=yqq.json&needNewCode=0"
            guard let url = URL(string: urlString) else { return }
            var request = URLRequest(url: url)
            request.setValue(Self.ua, forHTTPHeaderField: "User-Agent")
            request.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            let code = obj["code"] as? Int ?? -1
            // code 1000 = 资料接口不可用（Mineradio 排障记录），不视为未登录，改用 Cookie 兜底
            guard code == 0 || code == 1000 else { return }
            if let nick = Self.extractNickname(obj), !nick.isEmpty, nick != nickname {
                nickname = nick
                defaults.set(nick, forKey: nickKey)
                return
            }
            // 资料接口拿不到昵称时，用 ptlogin 下发的 ptnick_* Cookie 兜底
            if let key = cookies.keys.first(where: { $0.hasPrefix("ptnick") }),
               let raw = cookies[key], !raw.isEmpty {
                let nick = raw.removingPercentEncoding ?? raw
                if nick != nickname {
                    nickname = nick
                    defaults.set(nick, forKey: nickKey)
                }
            }
        } catch {
            // 尽力而为：接口波动不影响登录
        }
    }

    /// 从个人主页响应中提取昵称（data.mymusic.info.nick 优先，其次递归找 nick/nickname）
    private static func extractNickname(_ json: [String: Any]) -> String? {
        if let data = json["data"] as? [String: Any],
           let mymusic = data["mymusic"] as? [String: Any],
           let info = mymusic["info"] as? [String: Any],
           let nick = info["nick"] as? String, !nick.isEmpty {
            return nick
        }
        var found: String?
        func walk(_ value: Any) {
            if found != nil { return }
            if let dict = value as? [String: Any] {
                if let nick = dict["nick"] as? String, !nick.isEmpty, !nick.contains("QQ音乐用户") { found = nick; return }
                if let nick = dict["nickname"] as? String, !nick.isEmpty, !nick.contains("QQ音乐用户") { found = nick; return }
                for (_, v) in dict { walk(v) }
            } else if let arr = value as? [Any] {
                for v in arr { walk(v) }
            }
        }
        walk(json)
        return found
    }

    /// musicu.fcg 统一 POST（携带当前登录 Cookie）
    private func musicu(_ payload: [String: Any]) async throws -> [String: Any] {
        guard let body = try? JSONSerialization.data(withJSONObject: payload),
              let url = URL(string: "https://u.y.qq.com/cgi-bin/musicu.fcg") else {
            throw NetEaseError.unknown("请求参数错误")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.ua, forHTTPHeaderField: "User-Agent")
        request.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.httpBody = body
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NetEaseError.network
        }
        return obj
    }

    // MARK: - 工具

    private static let ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

    private func collectCookies(from response: URLResponse) {
        guard let http = response as? HTTPURLResponse,
              let headers = http.allHeaderFields as? [String: String] else { return }
        let setCookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: http.url!)
        for cookie in setCookies where !cookie.name.isEmpty {
            cookies[cookie.name] = cookie.value
        }
    }

    /// 解析 ptuiCB('66','','0','','') 形式的 JSONP 回调
    /// 兼容两种历史格式：code,url,'0',msg,nick 与 code,'0',url,msg,nick
    private static func parsePTUI(_ text: String) -> (code: String, url: String?, nickname: String)? {
        guard let open = text.firstIndex(of: "("), let close = text.lastIndex(of: ")") else { return nil }
        let inner = text[text.index(after: open)..<close]
        let parts = inner.split(separator: ",", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: "'\" "))
        }
        guard parts.count >= 5 else { return nil }
        let url: String
        if parts[1].hasPrefix("http") {
            url = parts[1]
        } else {
            url = parts.count > 2 ? parts[2] : ""
        }
        return (parts[0], url.isEmpty ? nil : url, parts[4])
    }

    private static func extractCode(from urlString: String) -> String? {
        guard let url = URL(string: urlString),
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = comps.queryItems,
              let code = items.first(where: { $0.name == "code" })?.value else { return nil }
        return code
    }

    private static func formEncode(_ fields: [String: String]) -> String {
        fields.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
    }

    /// 对应 JS: e += (e << 5) + t.charCodeAt(n); return 2147483647 & e（e 初始 0）—— ptqrtoken 用
    /// JS 的 e 是 IEEE-754 double（累加不截断 32 位），必须用 Double 精确模拟，
    /// 否则长 qrsig 在 Int64 中溢出导致 ptqrtoken 错误、登录接口返回异常。
    static func hash33(_ t: String) -> Int {
        var e: Double = 0
        for unit in t.utf16 {
            e = e + Double(Self.toInt32Shift(e)) + Double(unit)
        }
        return Int(Self.toInt32(e) & 0x7FFF_FFFF)
    }

    /// 对应 wp_MusicApi 的 f()：n 初始 5381，key 取 skey/qqmusic_key —— oauth g_tk 用
    static func hash5381(_ t: String) -> Int {
        var e: Double = 5381
        for unit in t.utf16 {
            e = e + Double(Self.toInt32Shift(e)) + Double(unit)
        }
        return Int(Self.toInt32(e) & 0x7FFF_FFFF)
    }

    /// JS ToInt32(d) << 5（32 位有符号截断）
    private static func toInt32Shift(_ d: Double) -> Int32 {
        let u = Self.toUInt32(d)
        return Int32(bitPattern: u &* 32)
    }

    /// JS ToInt32(d)：对 2^32 取模后转有符号 32 位
    private static func toInt32(_ d: Double) -> Int32 {
        Int32(bitPattern: Self.toUInt32(d))
    }

    private static func toUInt32(_ d: Double) -> UInt32 {
        var r = d.truncatingRemainder(dividingBy: 4294967296.0)
        if r < 0 { r += 4294967296.0 }
        return UInt32(r)
    }

}

/// 拦截自动重定向，手动处理 302（oauth authorize 需要从 Location 拿 code）
private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

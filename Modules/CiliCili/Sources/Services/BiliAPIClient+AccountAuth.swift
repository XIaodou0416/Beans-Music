import CryptoKit
import Foundation
import Security

nonisolated extension CharacterSet {
    fileprivate static let biliAppComponentAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()"
    )
}

private let accountPassportURL = URL(string: "https://passport.bilibili.com")!

extension BiliAPIClient {
    func generateQRCodeLogin() async throws -> QRCodeLoginInfo {
        let response: BiliResponse<QRCodeLoginInfo> = try await get(
            base: accountPassportURL,
            path: "/x/passport-login/web/qrcode/generate",
            query: [:],
            referer: "https://passport.bilibili.com/login",
            userAgent: Self.webUserAgent
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard let info = response.payload else { throw BiliAPIError.missingPayload }
        return info
    }

    func generateAppQRCodeLogin() async throws -> QRCodeLoginInfo {
        let profile = BiliAppSigner.Profile.androidTV
        let cookieHeader = await anonymousCookieHeader()
        let headerContext = Self.piliPodStyleAppRecommendHeaders(
            cookieHeader: cookieHeader,
            profile: profile
        )
        var request = try await makeRequest(
            base: accountPassportURL,
            path: "/x/passport-tv-login/qrcode/auth_code",
            query: BiliAppSigner.sign(
                Self.appQRCodeLoginBaseFields(profile: profile, localID: "0"),
                profile: profile
            ),
            referer: "https://www.bilibili.com",
            userAgent: profile.userAgent,
            cookieHeader: cookieHeader,
            additionalHeaders: headerContext.headers,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let (data, _) = try await data(for: request, priority: URLSessionTask.highPriority)
        guard !data.isEmpty else { throw BiliAPIError.emptyData }
        let response: BiliResponse<AppQRCodeLoginAuthInfo> = try await Self.decode(
            data,
            priority: URLSessionTask.highPriority
        )
        guard response.code == 0 else { throw BiliAPIError.api(code: response.code, message: response.displayMessage) }
        guard let info = response.payload else { throw BiliAPIError.missingPayload }
        return info.qrCodeInfo
    }

    func confirmAppQRCodeLoginWithCurrentSession(authCode: String) async throws {
        let csrf = try await requireCSRF()
        let response: BiliResponse<EmptyBiliPayload> = try await postForm(
            base: accountPassportURL,
            path: "/x/passport-tv-login/h5/qrcode/confirm",
            body: [
                "auth_code": authCode,
                "csrf": csrf,
                "scanning_type": "1",
            ],
            referer: "https://passport.bilibili.com/h5-app/passport/login/scan?auth_code=\(authCode)",
            userAgent: Self.mobileUserAgent
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
    }

    func sendAppSMSCode(phone: String, countryCode: String = "86") async throws -> AppSMSCodeInfo {
        let profile = BiliAppSigner.Profile.androidHD
        let cookieHeader = await anonymousCookieHeader()
        let buvid = Self.cookieValue(named: "buvid3", in: cookieHeader) ?? "0"
        let headerContext = Self.piliPodStyleAppRecommendHeaders(
            cookieHeader: cookieHeader,
            profile: profile
        )
        let now = Date()
        let milliseconds = Int(now.timeIntervalSince1970 * 1000)
        let fields = BiliAppSigner.sign(
            [
                "build": profile.build,
                "buvid": buvid,
                "c_locale": "zh_CN",
                "channel": profile.channel,
                "cid": countryCode,
                "disable_rcmd": "0",
                "local_id": buvid,
                "login_session_id": Self.md5("\(buvid)\(milliseconds)"),
                "mobi_app": profile.mobiApp,
                "platform": profile.platform,
                "s_locale": "zh_CN",
                "statistics": profile.statistics,
                "tel": phone,
            ], profile: profile, timestamp: Int(now.timeIntervalSince1970))

        let response: BiliResponse<AppSMSCodeInfo> = try await postSignedAppForm(
            path: "/x/passport-login/sms/send",
            fields: fields,
            profile: profile,
            cookieHeader: cookieHeader,
            additionalHeaders: headerContext.headers
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        guard let info = response.payload else { throw BiliAPIError.missingPayload }
        if let recaptchaURL = info.recaptchaURL, !recaptchaURL.isEmpty {
            throw BiliAPIError.api(code: -105, message: "需要人机验证，请先使用 App 扫码登录。")
        }
        guard info.captchaKey?.isEmpty == false else { throw BiliAPIError.missingPayload }
        return info
    }

    func loginWithAppSMS(
        phone: String,
        countryCode: String = "86",
        code: String,
        captchaKey: String
    ) async throws -> AppQRCodeLoginPollData {
        let profile = BiliAppSigner.Profile.androidHD
        let cookieHeader = await anonymousCookieHeader()
        let buvid = Self.cookieValue(named: "buvid3", in: cookieHeader) ?? "0"
        let headerContext = Self.piliPodStyleAppRecommendHeaders(
            cookieHeader: cookieHeader,
            profile: profile
        )
        let webKey = try await fetchAppLoginWebKey()
        let encryptedDeviceToken = try Self.rsaEncryptedComponent(
            Self.randomAlphaNumeric(length: 16),
            publicKeyPEM: webKey.key
        )
        let deviceID = Self.appLoginDeviceID()
        let fields = BiliAppSigner.sign(
            [
                "bili_local_id": deviceID,
                "build": profile.build,
                "buvid": buvid,
                "c_locale": "zh_CN",
                "captcha_key": captchaKey,
                "channel": profile.channel,
                "cid": countryCode,
                "code": code,
                "device": "phone",
                "device_id": deviceID,
                "device_name": "vivo",
                "device_platform": "Android14vivo",
                "disable_rcmd": "0",
                "dt": encryptedDeviceToken,
                "from_pv": "main.my-information.my-login.0.click",
                "from_url": Self.appPercentEncodedComponent("bilibili://user_center/mine"),
                "local_id": buvid,
                "mobi_app": profile.mobiApp,
                "platform": profile.platform,
                "s_locale": "zh_CN",
                "statistics": profile.statistics,
                "tel": phone,
            ], profile: profile)

        let response: BiliResponse<AppQRCodeLoginPollData> = try await postSignedAppForm(
            path: "/x/passport-login/login/sms",
            fields: fields,
            profile: profile,
            cookieHeader: cookieHeader,
            additionalHeaders: headerContext.headers
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        guard let loginData = response.payload else { throw BiliAPIError.missingPayload }
        return loginData
    }

    func pollQRCodeLogin(qrcodeKey: String) async throws -> QRCodeLoginPollResult {
        let request = try await makeRequest(
            base: accountPassportURL,
            path: "/x/passport-login/web/qrcode/poll",
            query: ["qrcode_key": qrcodeKey],
            referer: "https://passport.bilibili.com/login",
            userAgent: Self.webUserAgent
        )
        let (data, response) = try await data(for: request, priority: URLSessionTask.defaultPriority)
        guard !data.isEmpty else { throw BiliAPIError.emptyData }

        let apiResponse: BiliResponse<QRCodeLoginPollData> = try await Self.decode(
            data,
            priority: URLSessionTask.defaultPriority
        )
        guard apiResponse.code == 0 else {
            throw BiliAPIError.api(code: apiResponse.code, message: apiResponse.displayMessage)
        }
        guard let pollData = apiResponse.payload else { throw BiliAPIError.missingPayload }
        return QRCodeLoginPollResult(
            data: pollData,
            cookies: Self.biliCookies(from: response, requestURL: request.url)
        )
    }

    func pollAppQRCodeLogin(authCode: String) async throws -> AppQRCodeLoginPollResult {
        let profile = BiliAppSigner.Profile.androidTV
        let cookieHeader = await anonymousCookieHeader()
        let headerContext = Self.piliPodStyleAppRecommendHeaders(
            cookieHeader: cookieHeader,
            profile: profile
        )
        let fields = BiliAppSigner.sign(
            [
                "auth_code": authCode,
                "local_id": "0",
            ], profile: profile)
        var request = try await makeRequest(
            base: accountPassportURL,
            path: "/x/passport-tv-login/qrcode/poll",
            query: fields,
            referer: "https://www.bilibili.com",
            userAgent: profile.userAgent,
            cookieHeader: cookieHeader,
            additionalHeaders: headerContext.headers,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let (data, _) = try await data(for: request, priority: URLSessionTask.defaultPriority)
        guard !data.isEmpty else { throw BiliAPIError.emptyData }
        let response: BiliResponse<AppQRCodeLoginPollData> = try await Self.decode(
            data,
            priority: URLSessionTask.defaultPriority
        )
        return AppQRCodeLoginPollResult(
            status: Self.appQRCodeLoginStatus(for: response.code),
            message: response.displayMessage,
            loginData: response.payload
        )
    }

    func fetchNavUser() async throws -> NavUserInfo {
        if let task = await activeNavUserTask() {
            return try await task.value
        }
        let task = Task<NavUserInfo, Error>(priority: .utility) { [self] in
            let response: BiliResponse<NavUserInfo> = try await get(
                base: baseURL,
                path: "/x/web-interface/nav",
                query: [:]
            )
            guard response.code == 0 else {
                throw BiliAPIError.api(code: response.code, message: response.displayMessage)
            }
            guard let info = response.payload else { throw BiliAPIError.missingPayload }
            return info
        }
        await storeNavUserTask(task)
        do {
            let info = try await task.value
            await clearStoredNavUserTask()
            return info
        } catch {
            await clearStoredNavUserTask()
            throw error
        }
    }

    func fetchNavUser(cookieHeader: String) async throws -> NavUserInfo {
        let response: BiliResponse<NavUserInfo> = try await get(
            base: baseURL,
            path: "/x/web-interface/nav",
            query: [:],
            cookieHeader: cookieHeader,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        guard let info = response.payload, info.isLogin == true else {
            throw BiliAPIError.missingSESSDATA
        }
        return info
    }

    private func fetchAppLoginWebKey() async throws -> AppLoginWebKeyData {
        let response: BiliResponse<AppLoginWebKeyData> = try await get(
            base: accountPassportURL,
            path: "/x/passport-login/web/key",
            query: [:],
            referer: "https://passport.bilibili.com/login",
            userAgent: Self.mobileUserAgent,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        guard response.code == 0 else {
            throw BiliAPIError.api(code: response.code, message: response.displayMessage)
        }
        guard let data = response.payload else { throw BiliAPIError.missingPayload }
        return data
    }

    private func postSignedAppForm<T: Decodable & Sendable>(
        path: String,
        fields: [String: String],
        profile: BiliAppSigner.Profile,
        cookieHeader: String,
        additionalHeaders: [String: String]
    ) async throws -> T {
        var request = try await makeRequest(
            base: accountPassportURL,
            path: path,
            query: [:],
            referer: "https://www.bilibili.com",
            userAgent: profile.userAgent,
            cookieHeader: cookieHeader,
            additionalHeaders: additionalHeaders,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(from: fields)
        let (data, _) = try await data(for: request, priority: URLSessionTask.highPriority)
        guard !data.isEmpty else { throw BiliAPIError.emptyData }
        return try await Self.decode(data, priority: URLSessionTask.highPriority)
    }

    private static func appQRCodeLoginBaseFields(
        profile: BiliAppSigner.Profile,
        localID: String
    ) -> [String: String] {
        if profile == .androidTV {
            return [
                "local_id": "0"
            ]
        }

        if profile == .androidHD {
            return [
                "local_id": "0",
                "mobi_app": profile.mobiApp,
                "platform": profile.platform,
            ]
        }

        return [
            "build": profile.build,
            "c_locale": "zh_CN",
            "channel": profile.channel,
            "local_id": localID,
            "mobi_app": profile.mobiApp,
            "platform": profile.platform,
            "s_locale": "zh_CN",
            "statistics": profile.statistics,
        ]
    }

    private static func appQRCodeLoginStatus(for code: Int) -> QRCodeLoginPollStatus {
        switch code {
        case 0:
            return .confirmed
        case 86038:
            return .expired
        case 86090:
            return .waitingForConfirm
        case 86039:
            return .waitingForScan
        case 86101:
            return .waitingForScan
        default:
            return .unknown(code)
        }
    }

    private static func md5(_ value: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func appLoginDeviceID() -> String {
        let key = "BiliAppLoginDeviceID"
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }

        var bytes = [UInt8](repeating: 0, count: 25)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            bytes = Array(UUID().uuidString.utf8).map { UInt8($0) }.prefix(25).map { $0 }
            while bytes.count < 25 {
                bytes.append(UInt8.random(in: 0...255))
            }
        }
        let checksum = bytes.reduce(0) { ($0 + Int($1)) & 0xff }
        let digest = Insecure.MD5.hash(data: Data(bytes))
            .map { String(format: "%02x", $0) }
            .joined()
        let value = digest + String(format: "%02x", checksum)
        UserDefaults.standard.set(value, forKey: key)
        return value
    }

    private static func rsaEncryptedComponent(_ value: String, publicKeyPEM: String) throws -> String {
        let publicKey = try rsaPublicKey(from: publicKeyPEM)
        let algorithm = SecKeyAlgorithm.rsaEncryptionPKCS1
        guard SecKeyIsAlgorithmSupported(publicKey, .encrypt, algorithm) else {
            throw BiliAPIError.api(code: -1, message: "当前设备不支持短信登录加密")
        }
        var error: Unmanaged<CFError>?
        guard
            let encrypted = SecKeyCreateEncryptedData(publicKey, algorithm, Data(value.utf8) as CFData, &error) as Data?
        else {
            let message = error?.takeRetainedValue().localizedDescription
            throw BiliAPIError.api(code: -1, message: message ?? "短信登录加密失败")
        }
        return appPercentEncodedComponent(encrypted.base64EncodedString())
    }

    private static func rsaPublicKey(from pem: String) throws -> SecKey {
        let base64 =
            pem
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        guard let keyData = Data(base64Encoded: base64) else {
            throw BiliAPIError.api(code: -1, message: "登录公钥格式无效")
        }
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits: 1024,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error) else {
            let message = error?.takeRetainedValue().localizedDescription
            throw BiliAPIError.api(code: -1, message: message ?? "登录公钥解析失败")
        }
        return key
    }

    private static func appPercentEncodedComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .biliAppComponentAllowed) ?? value
    }

    private static func biliCookies(from response: URLResponse, requestURL: URL?) -> [HTTPCookie] {
        var cookies = [HTTPCookie]()

        if let httpResponse = response as? HTTPURLResponse,
            let requestURL
        {
            let headers = httpResponse.allHeaderFields.reduce(into: [String: String]()) { result, field in
                let key = (field.key.base as? String) ?? String(describing: field.key)
                result[key] = String(describing: field.value)
            }
            cookies.append(contentsOf: HTTPCookie.cookies(withResponseHeaderFields: headers, for: requestURL))
        }

        if cookies.isEmpty {
            let storageURLs = [
                requestURL,
                URL(string: "https://passport.bilibili.com"),
                URL(string: "https://www.bilibili.com"),
                URL(string: "https://api.bilibili.com"),
            ].compactMap { $0 }
            cookies.append(contentsOf: storageURLs.flatMap { HTTPCookieStorage.shared.cookies(for: $0) ?? [] })
        }

        var seen = Set<String>()
        return cookies.filter { cookie in
            guard cookie.domain.localizedCaseInsensitiveContains("bilibili.com") else { return false }
            let key = "\(cookie.name)|\(cookie.domain)|\(cookie.path)"
            return seen.insert(key).inserted
        }
    }
}

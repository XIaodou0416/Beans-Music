import Foundation

nonisolated struct QRCodeLoginInfo: Decodable, Hashable {
    let url: String
    let qrcodeKey: String

    enum CodingKeys: String, CodingKey {
        case url
        case qrcodeKey = "qrcode_key"
    }

    init(url: String, qrcodeKey: String) {
        self.url = url
        self.qrcodeKey = qrcodeKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(String.self, forKey: .url)
        qrcodeKey = try container.decode(String.self, forKey: .qrcodeKey)
    }
}

nonisolated struct QRCodeLoginPollData: Decodable, Hashable {
    let url: String?
    let refreshToken: String?
    let timestamp: Int?
    let code: Int
    let message: String?

    enum CodingKeys: String, CodingKey {
        case url, timestamp, code, message
        case refreshToken = "refresh_token"
    }

    var status: QRCodeLoginPollStatus {
        switch code {
        case 0:
            return .confirmed
        case 86038:
            return .expired
        case 86090:
            return .waitingForConfirm
        case 86101:
            return .waitingForScan
        default:
            return .unknown(code)
        }
    }

    var cookieValuesFromURL: [String: String] {
        guard let url,
            let components = URLComponents(string: url),
            let queryItems = components.queryItems
        else {
            return [:]
        }

        return queryItems.reduce(into: [String: String]()) { result, item in
            guard let value = item.value, !value.isEmpty else { return }
            result[item.name] = value
        }
    }
}

struct QRCodeLoginPollResult {
    let data: QRCodeLoginPollData
    let cookies: [HTTPCookie]
}

nonisolated struct AppQRCodeLoginAuthInfo: Decodable, Hashable, Sendable {
    let authCode: String
    let url: String

    enum CodingKeys: String, CodingKey {
        case authCode = "auth_code"
        case url
    }

    var qrCodeInfo: QRCodeLoginInfo {
        QRCodeLoginInfo(url: url, qrcodeKey: authCode)
    }
}

nonisolated struct AppQRCodeLoginPollData: Decodable, Hashable, Sendable {
    let accessToken: String?
    let refreshToken: String?
    let tokenInfo: AppLoginTokenInfo?
    let cookieInfo: AppLoginCookieInfo?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenInfo = "token_info"
        case cookieInfo = "cookie_info"
    }

    var resolvedAccessKey: String? {
        let candidates = [
            accessToken,
            tokenInfo?.accessToken,
        ]
        return
            candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    var loginCookieValues: [String: String] {
        var values = cookieInfo?.cookieValues ?? [:]
        if let accessKey = resolvedAccessKey {
            values["access_key"] = accessKey
        }
        return values
    }
}

nonisolated struct AppLoginTokenInfo: Decodable, Hashable, Sendable {
    let accessToken: String?
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

nonisolated struct AppLoginCookieInfo: Decodable, Hashable, Sendable {
    let cookies: [AppLoginCookie]?

    var cookieValues: [String: String] {
        (cookies ?? []).reduce(into: [String: String]()) { result, cookie in
            guard !cookie.name.isEmpty, !cookie.value.isEmpty else { return }
            result[cookie.name] = cookie.value
        }
    }
}

nonisolated struct AppLoginCookie: Decodable, Hashable, Sendable {
    let name: String
    let value: String
}

nonisolated struct AppQRCodeLoginPollResult: Sendable {
    let status: QRCodeLoginPollStatus
    let message: String?
    let loginData: AppQRCodeLoginPollData?
}

nonisolated struct AppSMSCodeInfo: Decodable, Hashable, Sendable {
    let captchaKey: String?
    let recaptchaURL: String?

    enum CodingKeys: String, CodingKey {
        case captchaKey = "captcha_key"
        case recaptchaURL = "recaptcha_url"
    }
}

nonisolated struct AppLoginWebKeyData: Decodable, Hashable, Sendable {
    let hash: String?
    let key: String
}

enum QRCodeLoginPollStatus: Equatable {
    case waitingForScan
    case waitingForConfirm
    case confirmed
    case expired
    case unknown(Int)
}

nonisolated struct NavUserInfo: Decodable {
    let isLogin: Bool?
    let face: String?
    let uname: String?
    let mid: Int?
    let wbiImg: WBIImage?

    enum CodingKeys: String, CodingKey {
        case face, uname, mid
        case isLogin = "isLogin"
        case wbiImg = "wbi_img"
    }
}

nonisolated struct WBIImage: Decodable {
    let imgURL: String
    let subURL: String

    enum CodingKeys: String, CodingKey {
        case imgURL = "img_url"
        case subURL = "sub_url"
    }
}

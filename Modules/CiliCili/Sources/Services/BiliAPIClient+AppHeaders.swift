import Foundation

extension BiliAPIClient {
    struct AppRecommendHeaderContext {
        let headers: [String: String]
        let fingerprintSource: String
        let sessionSource: String
        let appKeyHeader: String
    }

    static func piliPodStyleAppRecommendHeaders(
        cookieHeader: String,
        profile: BiliAppSigner.Profile
    ) -> AppRecommendHeaderContext {
        let buvid =
            cookieValue(named: "buvid3", in: cookieHeader)
            ?? cookieValue(named: "buvid4", in: cookieHeader)
            ?? "11111111111111111111111111111111"
        let cookieFingerprint =
            cookieValue(named: "buvid_fp", in: cookieHeader)
            ?? cookieValue(named: "buvid_fp_plain", in: cookieHeader)
        let fingerprint = cookieFingerprint ?? stableHexToken(seed: buvid, length: 64)
        let cookieSession = cookieValue(named: "b_lsid", in: cookieHeader)
            .map { stableHexToken(seed: $0, length: 8) }
        let sessionID = cookieSession ?? stableHexToken(seed: buvid, length: 8)
        let headers = [
            "buvid": buvid,
            "fp_local": fingerprint,
            "fp_remote": fingerprint,
            "session_id": sessionID,
            "env": "prod",
            "app-key": profile.appKeyHeader,
            "x-bili-trace-id": piliPlusTraceID(),
            "x-bili-aurora-eid": "",
            "x-bili-aurora-zone": "",
            "bili-http-engine": "cronet",
        ]
        return AppRecommendHeaderContext(
            headers: headers,
            fingerprintSource: cookieFingerprint == nil ? "generated" : "cookie",
            sessionSource: cookieSession == nil ? "generated" : "cookie",
            appKeyHeader: profile.appKeyHeader
        )
    }

    static func uploaderAppHeaders(
        cookieHeader: String,
        profile: BiliAppSigner.Profile
    ) -> [String: String] {
        piliPodStyleAppRecommendHeaders(cookieHeader: cookieHeader, profile: profile).headers
    }

    static func interactionAppHeaders(
        cookieHeader: String,
        profile: BiliAppSigner.Profile
    ) -> [String: String] {
        piliPodStyleAppRecommendHeaders(cookieHeader: cookieHeader, profile: profile).headers
    }

    static func piliPlusTraceID() -> String {
        "\(stableHexToken(seed: UUID().uuidString, length: 32)):\(stableHexToken(seed: UUID().uuidString, length: 16)):0:0"
    }

    static func stableHexToken(seed: String, length: Int) -> String {
        let hex = seed.unicodeScalars.map { scalar in
            String(format: "%02x", scalar.value & 0xff)
        }.joined()
        var value = hex.isEmpty ? "0123456789abcdef" : hex
        while value.count < length {
            value += value
        }
        return String(value.prefix(length))
    }
}

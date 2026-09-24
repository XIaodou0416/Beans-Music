import Foundation

nonisolated enum BiliAPIError: LocalizedError, Sendable {
    case invalidURL
    case emptyData
    case api(code: Int, message: String?)
    case missingPayload
    case missingSESSDATA
    case missingCSRF
    case emptyPlayURL
    case unsupportedHardwarePlayback(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .emptyData:
            return "Empty response"
        case .api(let code, let message):
            return "API \(code): \(message ?? "Unknown error")"
        case .missingPayload:
            return "Missing response data"
        case .missingSESSDATA:
            return "Login cookie not found"
        case .missingCSRF:
            return "登录 Cookie 中缺少 bili_jct，无法提交互动操作"
        case .emptyPlayURL:
            return "播放接口没有返回清晰度或播放地址"
        case .unsupportedHardwarePlayback(let detail):
            return detail.isEmpty ? "播放接口没有返回可硬解的 HEVC/AAC 播放地址" : detail
        }
    }
}

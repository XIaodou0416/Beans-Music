import Foundation

nonisolated enum BiliAccountPurpose: String, Codable, CaseIterable, Sendable {
    case main
    case playback
    case dynamicFeed
    case interaction
    case historyRead
    case historyWrite
}

nonisolated enum WatchHistoryAccountPolicy: String, Codable, CaseIterable, Identifiable, Sendable {
    case main
    case playback
    case disabled

    var id: Self { self }

    var title: String {
        switch self {
        case .main:
            return "主账号"
        case .playback:
            return "视频取流账号"
        case .disabled:
            return "不上传记录"
        }
    }

    var detail: String {
        switch self {
        case .main:
            return "续播和观看记录使用主账号"
        case .playback:
            return "续播和观看记录使用视频取流账号"
        case .disabled:
            return "不上传新进度，历史列表仍显示主账号已有记录"
        }
    }
}

nonisolated struct BiliAccountSummary: Codable, Hashable, Identifiable, Sendable {
    let mid: Int
    var name: String?
    var face: String?
    var credentialKind: LoginCredentialKind

    var id: Int { mid }

    var displayName: String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "UID \(mid)" : trimmed
    }
}

nonisolated struct BiliAccountCredentialSnapshot: Equatable, Sendable {
    let accountMID: Int?
    let cookieHeader: String
    let anonymousCookieHeader: String
    let accessKey: String?
    let credentialKind: LoginCredentialKind
    let isLoggedIn: Bool
    let csrfToken: String?
    let version: Int
    let isPurposeEnabled: Bool
}

nonisolated enum MultiAccountSessionError: LocalizedError {
    case missingSession
    case missingUserID
    case accountNotFound
    case cannotRemoveMainAccount

    var errorDescription: String? {
        switch self {
        case .missingSession:
            return "登录信息中缺少 SESSDATA"
        case .missingUserID:
            return "登录信息中缺少用户 UID"
        case .accountNotFound:
            return "没有找到这个账号"
        case .cannotRemoveMainAccount:
            return "请先选择其他主账号，再删除当前主账号"
        }
    }
}

nonisolated struct StoredBiliAccountRegistry: Codable, Sendable {
    var accounts: [BiliAccountSummary]
    var mainAccountMID: Int?
    var playbackAccountMID: Int?
    var dynamicFeedAccountMID: Int?
    var interactionAccountMID: Int?
    var historyPolicy: WatchHistoryAccountPolicy
}

nonisolated struct StoredBiliAccountCredentials: Equatable, Sendable {
    var cookieHeader: String
    var accessKey: String?
    var credentialKind: LoginCredentialKind
}

import SwiftUI
import Security
import CiliCiliKit

extension Notification.Name {
    static let beansBilibiliLoginDidUpdate = Notification.Name("beansBilibiliLoginDidUpdate")
}

@MainActor
final class BilibiliAuth: ObservableObject {
    static let shared = BilibiliAuth()

    @Published private(set) var isLoggedIn = false
    @Published private(set) var nickname = ""
    @Published private(set) var accountID = ""
    @Published private(set) var avatarURL: URL?

    private static let service = "com.beans.music.bilibili"
    private static let cookieAccount = "account-cookie-v1"
    private let defaults = UserDefaults.standard

    private init() {
        nickname = defaults.string(forKey: "beans.bilibili.nickname.v1") ?? ""
        accountID = defaults.string(forKey: "beans.bilibili.mid.v1") ?? ""
        avatarURL = defaults.string(forKey: "beans.bilibili.avatar.v1").flatMap { URL(string: $0) }
        if let cookie = Self.readCookie(), !cookie.isEmpty {
            isLoggedIn = true
        }
    }

    var cookieHeader: String { BilibiliProtocol.normalizeCookie(Self.readCookie() ?? "") }

    /// Upstream has already authenticated this session. Store it without a
    /// second network login that could race a later logout/account switch.
    func acceptCiliCiliSession(cookie: String, name: String, id: String, avatar: String?) throws {
        let normalized = BilibiliProtocol.normalizeCookie(cookie)
        if normalized.isEmpty {
            if isLoggedIn { logout() }
            return
        }
        guard BilibiliProtocol.hasSession(normalized) else {
            throw BilibiliError(message: "CiliCili 登录凭据不完整")
        }
        if cookieHeader != normalized { try Self.saveCookie(normalized) }
        nickname = name
        accountID = id
        avatarURL = avatar.flatMap(URL.init(string:))
        isLoggedIn = true
        defaults.set(name, forKey: "beans.bilibili.nickname.v1")
        defaults.set(id, forKey: "beans.bilibili.mid.v1")
        defaults.set(avatar, forKey: "beans.bilibili.avatar.v1")
        Task { await BilibiliAPI.shared.setCookie(BilibiliAuth.shared.cookieHeader) }
        NotificationCenter.default.post(name: .beansBilibiliLoginDidUpdate, object: nil)
    }

    /// Restore the visible account header after a cold launch. The cookie is
    /// persisted securely, but the profile image is only a cache and may be
    /// missing after reinstall or an older login.
    func refreshProfileIfNeeded() async {
        guard isLoggedIn, !cookieHeader.isEmpty else { return }
        do {
            let info = try await BilibiliAPI.shared.accountInfo(cookie: cookieHeader)
            nickname = info.nickname
            accountID = info.mid
            avatarURL = info.avatar
            defaults.set(info.nickname, forKey: "beans.bilibili.nickname.v1")
            defaults.set(info.mid, forKey: "beans.bilibili.mid.v1")
            if let avatar = info.avatar?.absoluteString {
                defaults.set(avatar, forKey: "beans.bilibili.avatar.v1")
            }
            objectWillChange.send()
        } catch {
            BilibiliDetailDiagnostics.record("account refresh failed: \(error.localizedDescription)")
        }
    }

    func login(cookie: String) async throws {
        let normalized = BilibiliProtocol.normalizeCookie(cookie)
        guard BilibiliProtocol.hasSession(normalized) else {
            throw BilibiliError(message: "登录凭据不完整，请重新扫码")
        }
        let info = try await BilibiliAPI.shared.accountInfo(cookie: normalized)
        try Self.saveCookie(normalized)
        await BilibiliAPI.shared.setCookie(normalized)
        nickname = info.nickname
        accountID = info.mid
        isLoggedIn = true
        avatarURL = info.avatar
        defaults.set(info.nickname, forKey: "beans.bilibili.nickname.v1")
        defaults.set(info.mid, forKey: "beans.bilibili.mid.v1")
        defaults.set(info.avatar?.absoluteString, forKey: "beans.bilibili.avatar.v1")
        NotificationCenter.default.post(name: .beansBilibiliLoginDidUpdate, object: nil)
    }

    func logout() {
        Self.deleteCookie()
        nickname = ""
        accountID = ""
        avatarURL = nil
        isLoggedIn = false
        defaults.removeObject(forKey: "beans.bilibili.nickname.v1")
        defaults.removeObject(forKey: "beans.bilibili.mid.v1")
        defaults.removeObject(forKey: "beans.bilibili.avatar.v1")
        Task { await BilibiliAPI.shared.setCookie("") }
        NotificationCenter.default.post(name: .beansBilibiliLoginDidUpdate, object: nil)
    }

    private static func readCookie() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: cookieAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func saveCookie(_ cookie: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: cookieAccount
        ]
        let data = Data(cookie.utf8)
        let updateAttributes: [String: Any] = [kSecValueData as String: data]
        let update = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        guard update == errSecItemNotFound else {
            guard update == errSecSuccess else {
                throw BilibiliError(message: "无法安全保存哔哩哔哩登录凭据（\(update)）")
            }
            return
        }
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let add = SecItemAdd(attributes as CFDictionary, nil)
        guard add == errSecSuccess else {
            throw BilibiliError(message: "无法安全保存哔哩哔哩登录凭据（\(add)）")
        }
    }

    private static func deleteCookie() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: cookieAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Existing Beans account buttons now open CiliCili's actual login/account page.
struct BilibiliLoginSheet: View {
    var body: some View { CiliCiliRouteHost(route: .account) }
}


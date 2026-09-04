import Foundation
import UIKit

final class KugouMusicAuth: ObservableObject {
    static let shared = KugouMusicAuth()

    @Published private(set) var isLoggedIn = false
    @Published private(set) var userId = ""
    @Published private(set) var nickname = ""
    @Published private(set) var avatarURL: URL?
    @Published private(set) var vipBadge: String?

    private let defaults = UserDefaults.standard
    private let key = "beans.kugou.auth.v2"
    /// 网络请求会在非主线程读取登录快照，和登录回调写入状态并发时需要串行化。
    private let stateLock = NSLock()
    private var auth: [String: String] = [:]

    private init() {
        if let saved = defaults.dictionary(forKey: key) as? [String: String] {
            auth = saved
            apply(saved)
        }
    }

    var token: String { authSnapshot["token"] ?? "" }
    var mid: String { authSnapshot["KUGOU_API_MID"] ?? authSnapshot["mid"] ?? Self.defaultMid }
    var dfid: String { authSnapshot["dfid"] ?? authSnapshot["DFID"] ?? "-" }
    var guid: String { authSnapshot["KUGOU_API_GUID"] ?? "" }
    var vipType: Int { Int(authSnapshot["vipType"] ?? authSnapshot["vip_type"] ?? "0") ?? 0 }
    var hasMembership: Bool { vipType > 0 }

    var cookieHeader: String {
        let snapshot = authSnapshot
        var items = [
            ("userid", snapshot["userid"] ?? snapshot["user_id"] ?? ""),
            ("token", snapshot["token"] ?? ""),
            ("KUGOU_API_MID", snapshot["KUGOU_API_MID"] ?? snapshot["mid"] ?? Self.defaultMid),
            ("dfid", snapshot["dfid"] ?? snapshot["DFID"] ?? "-"),
        ]
        let savedVIPType = Int(snapshot["vipType"] ?? snapshot["vip_type"] ?? "0") ?? 0
        if savedVIPType > 0 {
            items.append(("vipType", "\(savedVIPType)"))
            items.append(("viptype", "\(savedVIPType)"))
        }
        return items
            .filter { !$0.1.isEmpty }
            .map { "\($0.0)=\($0.1)" }
            .joined(separator: "; ")
    }

    func prepareDevice() {
        let current = authSnapshot
        var next = current
        _ = Self.ensureDevice(&next)
        guard next != current else { return }
        save(next)
    }

    func saveLogin(userId: String, token: String, nickname: String, avatar: String, vipType: Int) {
        var next = authSnapshot
        _ = Self.ensureDevice(&next)
        next["userid"] = userId
        next["token"] = token
        next["nickname"] = nickname
        next["avatar"] = avatar
        next["vipType"] = "\(vipType)"
        save(next)
    }

    func saveDeviceDFID(_ dfid: String) {
        guard !dfid.isEmpty else { return }
        let current = authSnapshot
        guard current["dfid"] != dfid else { return }
        var next = current
        next["dfid"] = dfid
        save(next)
    }

    func updateVIPType(_ vipType: Int) {
        guard vipType > self.vipType else { return }
        var next = authSnapshot
        next["vipType"] = "\(vipType)"
        save(next)
    }

    func logout() {
        replaceAuth([:])
        defaults.removeObject(forKey: key)
        updatePublishedState {
            self.isLoggedIn = false
            self.userId = ""
            self.nickname = ""
            self.avatarURL = nil
            self.vipBadge = nil
            NotificationCenter.default.post(name: .beansKugouLoginDidUpdate, object: nil)
        }
    }

    private func save(_ value: [String: String]) {
        replaceAuth(value)
        defaults.set(value, forKey: key)
        apply(value)
        updatePublishedState {
            NotificationCenter.default.post(name: .beansKugouLoginDidUpdate, object: nil)
        }
    }

    private func apply(_ value: [String: String]) {
        let nextUserId = (value["userid"] ?? value["user_id"] ?? "").filter(\.isNumber)
        let token = value["token"] ?? ""
        let nextIsLoggedIn = !nextUserId.isEmpty && !token.isEmpty
        let nextNickname = value["nickname"]?.removingPercentEncoding ?? value["nickname"] ?? ""
        let nextAvatarURL = URL(string: value["avatar"] ?? "")
        let vip = Int(value["vipType"] ?? value["vip_type"] ?? "0") ?? 0

        // URLSession completion handlers may resume on a non-main executor. SwiftUI
        // observes these properties, so publish the complete auth snapshot on the
        // main thread as one transaction instead of mutating @Published directly.
        updatePublishedState {
            if self.userId != nextUserId { self.userId = nextUserId }
            if self.isLoggedIn != nextIsLoggedIn { self.isLoggedIn = nextIsLoggedIn }
            if self.nickname != nextNickname { self.nickname = nextNickname }
            if self.avatarURL != nextAvatarURL { self.avatarURL = nextAvatarURL }
            let nextBadge = vip > 0 ? "VIP" : nil
            if self.vipBadge != nextBadge { self.vipBadge = nextBadge }
        }
    }

    /// Keep authentication/network code synchronous while making every observable
    /// state change main-thread-only. `sync` is intentional here: callers such as
    /// `pollQR` must see the new login state before they build the next request.
    private func updatePublishedState(_ update: @escaping () -> Void) {
        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.sync(execute: update)
        }
    }

    private var authSnapshot: [String: String] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return auth
    }

    private func replaceAuth(_ value: [String: String]) {
        stateLock.lock()
        auth = value
        stateLock.unlock()
    }

    @discardableResult
    static func ensureDevice(_ obj: inout [String: String]) -> [String: String] {
        let guid = obj["KUGOU_API_GUID"] ?? UUID().uuidString
        obj["KUGOU_API_GUID"] = guid
        obj["KUGOU_API_MID"] = obj["KUGOU_API_MID"] ?? calculateMid(seed: guid)
        obj["KUGOU_API_MAC"] = obj["KUGOU_API_MAC"] ?? randomString(12)
        obj["KUGOU_API_DEV"] = obj["KUGOU_API_DEV"] ?? randomString(16)
        return obj
    }

    private static var defaultMid: String {
        calculateMid(seed: UIDevice.current.identifierForVendor?.uuidString ?? "beans-kugou")
    }

    private static func calculateMid(seed: String) -> String {
        let hex = Data(seed.utf8).md5Hex()
        let prefix = String(hex.prefix(15))
        if let value = UInt64(prefix, radix: 16) { return "\(value)" }
        return hex
    }

    private static func randomString(_ length: Int) -> String {
        let chars = Array("1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        return String((0..<length).map { _ in chars[Int.random(in: 0..<chars.count)] })
    }
}

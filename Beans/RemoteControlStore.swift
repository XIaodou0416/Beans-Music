import Foundation

/// Beans 服务器远程配置。只应用明确接入的安全配置项，不执行云端代码。
@MainActor
final class RemoteControlStore: ObservableObject {
    static let shared = RemoteControlStore()

    private let configURL = URL(string: "http://189.24.78.193/beans/config.json")!
    private let appliedKeysKey = "beans.remoteControl.appliedKeys"
    private let originalPrefix = "beans.remoteControl.original."
    private var isLoading = false
    private var lastRefresh = Date.distantPast

    private init() {}

    func refreshIfNeeded(force: Bool = false) async {
        guard force || Date().timeIntervalSince(lastRefresh) > 120 else { return }
        guard !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
            lastRefresh = Date()
        }

        do {
            var request = URLRequest(url: configURL)
            request.timeoutInterval = 8
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("Beans-Music/\(UpdateChecker.currentVersion)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            let payload = try JSONDecoder.beansSnakeCase.decode(RemoteConfig.self, from: data)
            apply(payload)
        } catch {
            BeansLogger.shared.log("远程配置同步失败：\(error.localizedDescription)", level: .debug)
        }
    }

    private func apply(_ config: RemoteConfig) {
        // 旧版本曾支持 App 云控；服务端移除后启动时清理历史覆盖值。
        clearRemoteOverrides()
        guard config.enabled else {
            clearRemoteOverrides()
            return
        }
        let defaults = UserDefaults.standard

        defaults.set(config.announcementEnabled && !config.announcement.isEmpty, forKey: "beans.remoteAnnouncement.enabled")
        defaults.set(config.announcement, forKey: "beans.remoteAnnouncement.text")
        defaults.set(config.announcementImageURL ?? "", forKey: "beans.remoteAnnouncement.imageURL")
        defaults.set(config.announcementTextColor ?? "", forKey: "beans.remoteAnnouncement.textColor")
        defaults.set(config.updatedAt ?? "", forKey: "beans.remoteAnnouncement.updatedAt")

        defaults.synchronize()
    }

    private func set(_ value: Bool?, key: String, defaults: UserDefaults) {
        guard let value else {
            restore(key: key, defaults: defaults)
            return
        }
        rememberOriginal(key: key, defaults: defaults)
        defaults.set(value, forKey: key)
    }

    private func setHex(_ value: String?, key: String, defaults: UserDefaults) {
        guard let value, value.hasPrefix("#"), value.count == 7 else {
            restore(key: key, defaults: defaults)
            return
        }
        rememberOriginal(key: key, defaults: defaults)
        defaults.set(value, forKey: key)
    }

    private func setString(_ value: String?, key: String, defaults: UserDefaults) {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            restore(key: key, defaults: defaults)
            return
        }
        rememberOriginal(key: key, defaults: defaults)
        defaults.set(value, forKey: key)
    }

    private func rememberOriginal(key: String, defaults: UserDefaults) {
        var keys = defaults.stringArray(forKey: appliedKeysKey) ?? []
        guard !keys.contains(key) else { return }
        if let current = defaults.object(forKey: key) {
            defaults.set(current, forKey: originalPrefix + key)
        } else {
            defaults.removeObject(forKey: originalPrefix + key)
        }
        keys.append(key)
        defaults.set(keys, forKey: appliedKeysKey)
    }

    private func restore(key: String, defaults: UserDefaults) {
        guard let keys = defaults.stringArray(forKey: appliedKeysKey), keys.contains(key) else { return }
        if let original = defaults.object(forKey: originalPrefix + key) {
            defaults.set(original, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
        defaults.removeObject(forKey: originalPrefix + key)
        defaults.set(keys.filter { $0 != key }, forKey: appliedKeysKey)
    }

    private func clearRemoteOverrides() {
        let defaults = UserDefaults.standard
        for key in defaults.stringArray(forKey: appliedKeysKey) ?? [] {
            if let original = defaults.object(forKey: originalPrefix + key) {
                defaults.set(original, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
            defaults.removeObject(forKey: originalPrefix + key)
        }
        defaults.removeObject(forKey: appliedKeysKey)
        defaults.synchronize()
    }
}

private struct RemoteConfig: Decodable {
    let enabled: Bool
    let announcement: String
    let announcementEnabled: Bool
    let announcementImageURL: String?
    let announcementTextColor: String?
    let updatedAt: String?
    let platforms: RemotePlatforms?
}

private struct RemotePlatforms: Decodable {
    let netease: Bool?
    let qq: Bool?
    let kugou: Bool?
}

private extension JSONDecoder {
    static var beansSnakeCase: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

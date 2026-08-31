import Foundation

/// Beans 服务器远程配置。只应用明确接入的安全配置项，不执行云端代码。
@MainActor
final class RemoteControlStore: ObservableObject {
    static let shared = RemoteControlStore()

    private let configURL = URL(string: "http://189.24.78.193/beans/config.json")!
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
        guard config.enabled, let control = config.appControl, control.enabled else { return }
        let defaults = UserDefaults.standard

        if let platforms = config.platforms {
            var enabled: [SearchProvider] = []
            if platforms.netease == true { enabled.append(.netease) }
            if platforms.qq == true { enabled.append(.qq) }
            if platforms.kugou == true { enabled.append(.kugou) }
            PlatformPreferenceStore.shared.applyRemoteEnabledProviders(enabled)
        }

        if let text = control.homeGreetingText, !text.isEmpty {
            defaults.set(text, forKey: "beans.homeGreetingText")
        }
        set(control.homeHideUsername, key: "beans.homeHideUsername", defaults: defaults)
        set(control.homeHideSort, key: "beans.homeHeaderHideSort", defaults: defaults)
        set(control.homeHideRefresh, key: "beans.homeHeaderHideRefresh", defaults: defaults)
        set(control.tabLabelsVisible, key: "beans.tabLabelsVisible", defaults: defaults)
        set(control.enableHighRefresh, key: "beans.enableHighRefresh", defaults: defaults)
        set(control.enableThirdPartySources, key: "beans.enableUnblock", defaults: defaults)
        set(control.showThirdPartyVipNotice, key: "beans.showThirdPartyVIPNotice", defaults: defaults)

        setHex(control.playerMainIconColor, key: "beans.playerMainIconColorHex", defaults: defaults)
        setHex(control.playerSecondaryIconColor, key: "beans.playerSecondaryIconColorHex", defaults: defaults)
        setHex(control.playerPrimaryButtonColor, key: "beans.playerPrimaryButtonColorHex", defaults: defaults)
        setHex(control.progressAccentColor, key: "beans.progressAccentHex", defaults: defaults)
        setHex(control.albumTitleColor, key: "beans.albumTitleColorHex", defaults: defaults)
        setHex(control.albumArtistColor, key: "beans.albumArtistColorHex", defaults: defaults)
        setHex(control.albumPreviewLyricColor, key: "beans.albumPreviewLyricColorHex", defaults: defaults)

        HighRefreshKeeper.shared.configure(enabled: defaults.bool(forKey: "beans.enableHighRefresh"))
        defaults.synchronize()
    }

    private func set(_ value: Bool?, key: String, defaults: UserDefaults) {
        guard let value else { return }
        defaults.set(value, forKey: key)
    }

    private func setHex(_ value: String?, key: String, defaults: UserDefaults) {
        guard let value, value.hasPrefix("#"), value.count == 7 else { return }
        defaults.set(value, forKey: key)
    }
}

private struct RemoteConfig: Decodable {
    let enabled: Bool
    let platforms: RemotePlatforms?
    let appControl: RemoteAppControl?
}

private struct RemotePlatforms: Decodable {
    let netease: Bool?
    let qq: Bool?
    let kugou: Bool?
}

private struct RemoteAppControl: Decodable {
    let enabled: Bool
    let homeGreetingText: String?
    let homeHideUsername: Bool?
    let homeHideSort: Bool?
    let homeHideRefresh: Bool?
    let tabLabelsVisible: Bool?
    let enableHighRefresh: Bool?
    let enableThirdPartySources: Bool?
    let showThirdPartyVipNotice: Bool?
    let playerMainIconColor: String?
    let playerSecondaryIconColor: String?
    let playerPrimaryButtonColor: String?
    let progressAccentColor: String?
    let albumTitleColor: String?
    let albumArtistColor: String?
    let albumPreviewLyricColor: String?
}

private extension JSONDecoder {
    static var beansSnakeCase: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

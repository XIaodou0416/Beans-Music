import Foundation

nonisolated enum CellularBiliTrafficCompatibilityExperiment {
    static let storageKey = "cc.bili.playback.cellularBiliTrafficCompatibilityExperimentEnabled.v1"
    static let defaultIsEnabled = false

    enum HostClassification: String, Equatable, Sendable {
        case bili
        case external
        case unknown

        var diagnosticTitle: String {
            switch self {
            case .bili:
                "B站域名"
            case .external:
                "外部域名"
            case .unknown:
                "未知"
            }
        }
    }

    struct RuntimeState: Equatable, Sendable {
        let isEnabled: Bool
        let isCellularNetwork: Bool

        static let inactive = RuntimeState(isEnabled: false, isCellularNetwork: false)

        var isActive: Bool {
            isEnabled && isCellularNetwork
        }

        var diagnosticSummary: String {
            if !isEnabled {
                return "off"
            }
            if !isCellularNetwork {
                return "on waitingForCellular"
            }
            return "on biliDomainFirst"
        }

        var userFacingStatus: String {
            if !isEnabled {
                return "未开启"
            }
            if !isCellularNetwork {
                return "已开启，等待使用蜂窝网络"
            }
            return "已启用 B站域名优先"
        }
    }

    static var currentState: RuntimeState {
        RuntimeState(
            isEnabled: stored(),
            isCellularNetwork: NetworkPathSnapshot.shared.usesCellular
        )
    }

    static func stored(in userDefaults: UserDefaults = .standard) -> Bool {
        userDefaults.object(forKey: storageKey) as? Bool ?? defaultIsEnabled
    }

    static func classify(host: String?) -> HostClassification {
        guard let host = normalizedHost(host) else { return .unknown }
        if approvedBiliDomains.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) {
            return .bili
        }
        return .external
    }

    static func prioritizedURLs(
        _ urls: [URL],
        isEnabled: Bool,
        isCellularNetwork: Bool
    ) -> [URL] {
        guard isEnabled, isCellularNetwork else { return urls }

        var biliURLs = [URL]()
        var fallbackURLs = [URL]()
        for url in urls {
            if classify(host: url.host) == .bili {
                biliURLs.append(url)
            } else {
                fallbackURLs.append(url)
            }
        }
        return biliURLs.isEmpty ? urls : biliURLs + fallbackURLs
    }

    static func prioritizedURLsForCurrentEnvironment(_ urls: [URL]) -> [URL] {
        let state = currentState
        return prioritizedURLs(
            urls,
            isEnabled: state.isEnabled,
            isCellularNetwork: state.isCellularNetwork
        )
    }

    static func sourceHostSummary(videoHost: String?, audioHost: String?) -> String {
        let video = classify(host: videoHost).diagnosticTitle
        let audio = classify(host: audioHost).diagnosticTitle
        return "video=\(video) audio=\(audio)"
    }

    static func hasExternalMediaHost(videoHost: String?, audioHost: String?) -> Bool {
        [videoHost, audioHost].contains { classify(host: $0) == .external }
    }

    private static let approvedBiliDomains = [
        "bilibili.com",
        "bilivideo.com",
        "bilivideo.cn",
        "bilivideo.net",
        "acgvideo.com",
        "acgvideo.cn"
    ]

    private static func normalizedHost(_ host: String?) -> String? {
        guard let host = host?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased(),
              !host.isEmpty
        else { return nil }
        return host
    }
}

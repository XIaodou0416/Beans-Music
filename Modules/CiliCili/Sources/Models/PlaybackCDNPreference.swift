import Foundation

enum PlaybackAutoOptimizationMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case automatic
    case off

    nonisolated var id: String { rawValue }

    nonisolated var title: String {
        switch self {
        case .automatic:
            return "自动优化"
        case .off:
            return "关闭"
        }
    }

    nonisolated var detail: String {
        switch self {
        case .automatic:
            return "根据首帧、缓冲、取流耗时和设备状态自动调整开播画质、预加载强度与 CDN 复测。"
        case .off:
            return "始终按你的默认画质和手动 CDN 设置播放，不根据历史表现自动降载。"
        }
    }

    nonisolated var isEnabled: Bool {
        self == .automatic
    }
}

enum PlaybackCDNProbeRefreshPolicy: String, CaseIterable, Identifiable, Codable, Sendable {
    case interval
    case appLaunch

    nonisolated var id: String { rawValue }

    nonisolated var title: String {
        switch self {
        case .interval:
            return "按间隔自动测速"
        case .appLaunch:
            return "每次打开 App 自动测速"
        }
    }

    nonisolated var detail: String {
        switch self {
        case .interval:
            return "测速结果过期后自动刷新，可自定义间隔。"
        case .appLaunch:
            return "App 启动或回到前台时自动刷新 CDN 参考；没有真实播放地址时不会更新推荐。"
        }
    }
}

enum PlaybackStreamSourcePreference: String, CaseIterable, Identifiable, Codable, Sendable {
    case web
    case app

    nonisolated var id: String { rawValue }

    nonisolated var title: String {
        switch self {
        case .web:
            return "网页端"
        case .app:
            return "App 端"
        }
    }

    nonisolated var detail: String {
        switch self {
        case .web:
            return "使用网页播放接口参数，兼容性最好。"
        case .app:
            return "使用移动端播放参数和移动端 User-Agent 请求播放源。"
        }
    }

    nonisolated var playURLPlatform: String {
        switch self {
        case .web:
            return "pc"
        case .app:
            return "iphone"
        }
    }

    nonisolated var cachePlatform: String {
        switch self {
        case .web:
            return "web-pc"
        case .app:
            return "app-iphone"
        }
    }
}

enum HomeRecommendFeedSourcePreference: String, CaseIterable, Identifiable, Codable, Sendable {
    case web
    case app

    nonisolated var id: String { rawValue }

    nonisolated var title: String {
        switch self {
        case .web:
            return "网页端"
        case .app:
            return "App 端"
        }
    }

    nonisolated var detail: String {
        switch self {
        case .web:
            return "使用网页推荐接口，稳定且兼容性最好。"
        case .app:
            return "使用移动端推荐接口，更接近官方 App 推荐流。"
        }
    }
}

enum PlaybackNetworkAddressFamily: String, Codable, CaseIterable, Identifiable, Sendable, Hashable {
    case ipv4
    case ipv6

    nonisolated var id: String { rawValue }

    nonisolated var title: String {
        switch self {
        case .ipv4:
            return "IPv4"
        case .ipv6:
            return "IPv6"
        }
    }
}

enum PlaybackNetworkAddressFamilyPreference: String, CaseIterable, Identifiable, Codable, Sendable {
    case automatic
    case ipv4Only
    case ipv6Only

    nonisolated var id: String { rawValue }

    nonisolated var title: String {
        switch self {
        case .automatic:
            return "自动"
        case .ipv4Only:
            return "仅 IPv4"
        case .ipv6Only:
            return "仅 IPv6"
        }
    }

    nonisolated var detail: String {
        switch self {
        case .automatic:
            return "由系统网络栈自动选择可用协议族。"
        case .ipv4Only:
            return "CDN 测速只选择支持 IPv4 的线路，适合 IPv4-only 设备。"
        case .ipv6Only:
            return "CDN 测速只选择支持 IPv6 的线路，适合 IPv6 网络环境。"
        }
    }

    nonisolated var requiredFamily: PlaybackNetworkAddressFamily? {
        switch self {
        case .automatic:
            return nil
        case .ipv4Only:
            return .ipv4
        case .ipv6Only:
            return .ipv6
        }
    }
}

struct PlaybackURLPreferenceSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let host: String
    let networkKey: String
    let networkTitle: String
    let averageMilliseconds: Int
    let averageKilobytesPerSecond: Int
    let successCount: Int
    let failureCount: Int
    let lastUpdatedAt: Date
    let rankScore: Double

    nonisolated var attemptCount: Int {
        successCount + failureCount
    }

    nonisolated var failureRatePercent: Int {
        guard attemptCount > 0 else { return 0 }
        return Int((Double(failureCount) / Double(attemptCount) * 100).rounded())
    }
}

enum PlaybackCDNPreference: String, CaseIterable, Identifiable, Codable, Sendable {
    case automatic
    case baseURL
    case backupURL
    case custom
    case ali
    case alib
    case alio1
    case cos
    case cosb
    case coso1
    case hw
    case hwb
    case hwo1
    case hw08c
    case hw08h
    case hw08ct
    case tfHW
    case tfTX
    case akamai
    case aliov
    case cosov
    case hwov
    case hkBCache

    nonisolated static let customHostStorageKey = "cc.bili.playback.customCDNHost.v1"

    nonisolated var id: String { rawValue }

    nonisolated var title: String {
        switch self {
        case .automatic:
            return "自动选择"
        case .baseURL:
            return "基础 URL"
        case .backupURL:
            return "备用 URL"
        case .custom:
            if let host = Self.customHost {
                return "自定义 \(host)"
            }
            return "自定义 CDN"
        case .ali:
            return "阿里云 ali"
        case .alib:
            return "阿里云 alib"
        case .alio1:
            return "阿里云 alio1"
        case .cos:
            return "腾讯云 cos"
        case .cosb:
            return "腾讯云 cosb"
        case .coso1:
            return "腾讯云 coso1"
        case .hw:
            return "华为云 hw"
        case .hwb:
            return "华为云 hwb"
        case .hwo1:
            return "华为云 hwo1"
        case .hw08c:
            return "华为云 08c"
        case .hw08h:
            return "华为云 08h"
        case .hw08ct:
            return "华为云 08ct"
        case .tfHW:
            return "华为云 tf_hw"
        case .tfTX:
            return "腾讯云 tf_tx"
        case .akamai:
            return "Akamai 海外"
        case .aliov:
            return "阿里云海外 aliov"
        case .cosov:
            return "腾讯云海外 cosov"
        case .hwov:
            return "华为云海外 hwov"
        case .hkBCache:
            return "Bilibili 香港"
        }
    }

    nonisolated var detail: String {
        switch self {
        case .automatic:
            return "保留接口下发的播放地址候选，并根据真实播放记录与启动探测微调排序"
        case .baseURL:
            return "优先使用接口返回的原始地址"
        case .backupURL:
            return "优先使用接口返回的备用地址"
        case .custom:
            return "将可安全改写的媒体播放地址切换到自定义 CDN Host，接口地址不会被替换"
        case .ali, .alib, .alio1:
            return "阿里云 CDN"
        case .cos, .cosb, .coso1, .tfTX:
            return "腾讯云 CDN"
        case .hw, .hwb, .hwo1, .hw08c, .hw08h, .hw08ct, .tfHW:
            return "华为云 CDN"
        case .akamai, .aliov, .cosov, .hwov, .hkBCache:
            return "海外或跨境 CDN"
        }
    }

    nonisolated var host: String? {
        switch self {
        case .automatic, .baseURL, .backupURL:
            return nil
        case .custom:
            return Self.customHost
        case .ali:
            return "upos-sz-mirrorali.bilivideo.com"
        case .alib:
            return "upos-sz-mirroralib.bilivideo.com"
        case .alio1:
            return "upos-sz-mirroralio1.bilivideo.com"
        case .cos:
            return "upos-sz-mirrorcos.bilivideo.com"
        case .cosb:
            return "upos-sz-mirrorcosb.bilivideo.com"
        case .coso1:
            return "upos-sz-mirrorcoso1.bilivideo.com"
        case .hw:
            return "upos-sz-mirrorhw.bilivideo.com"
        case .hwb:
            return "upos-sz-mirrorhwb.bilivideo.com"
        case .hwo1:
            return "upos-sz-mirrorhwo1.bilivideo.com"
        case .hw08c:
            return "upos-sz-mirror08c.bilivideo.com"
        case .hw08h:
            return "upos-sz-mirror08h.bilivideo.com"
        case .hw08ct:
            return "upos-sz-mirror08ct.bilivideo.com"
        case .tfHW:
            return "upos-tf-all-hw.bilivideo.com"
        case .tfTX:
            return "upos-tf-all-tx.bilivideo.com"
        case .akamai:
            return "upos-hz-mirrorakam.akamaized.net"
        case .aliov:
            return "upos-sz-mirroraliov.bilivideo.com"
        case .cosov:
            return "upos-sz-mirrorcosov.bilivideo.com"
        case .hwov:
            return "upos-sz-mirrorhwov.bilivideo.com"
        case .hkBCache:
            return "cn-hk-eq-bcache-01.bilivideo.com"
        }
    }

    nonisolated var isManualHost: Bool {
        host != nil
    }

    nonisolated var cacheKey: String {
        guard self == .custom else { return rawValue }
        return [rawValue, host ?? "-"].joined(separator: ":")
    }

    nonisolated static var customHost: String? {
        normalizedCustomHost(UserDefaults.standard.string(forKey: customHostStorageKey))
    }

    nonisolated static var manualProbeCandidates: [PlaybackCDNPreference] {
        allCases.filter(\.isManualHost)
    }

    nonisolated static func normalizedCustomHost(_ rawHost: String?) -> String? {
        guard var host = rawHost?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty
        else { return nil }
        if let url = URL(string: host), let parsedHost = url.host {
            host = parsedHost
        } else if let url = URL(string: "https://\(host)"), let parsedHost = url.host {
            host = parsedHost
        }
        host = host
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        guard !host.isEmpty,
              host.count <= 253,
              host.contains(".")
        else { return nil }
        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-.")
        guard host.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }) else { return nil }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return nil }
        for label in labels {
            guard !label.isEmpty,
                  label.count <= 63,
                  label.first != "-",
                  label.last != "-"
            else { return nil }
        }
        return host
    }

    nonisolated func preferredURLs(primary: URL?, backups: [URL]) -> (primary: URL?, backups: [URL]) {
        let candidates = ([primary].compactMap { $0 } + backups).removingDuplicateURLs()
        guard !candidates.isEmpty else { return (primary, backups) }

        let ordered: [URL]
        switch self {
        case .automatic:
            ordered = PlaybackURLPreferenceStore.shared.orderedURLs(candidates)
        case .baseURL:
            ordered = candidates
        case .backupURL:
            let backupFirst = backups.removingDuplicateURLs() + [primary].compactMap { $0 }
            ordered = backupFirst.removingDuplicateURLs()
        default:
            if let host {
                ordered = Self.manualHostURLs(host: host, candidates: candidates)
            } else {
                ordered = candidates
            }
        }

        let compatibleOrder = CellularBiliTrafficCompatibilityExperiment
            .prioritizedURLsForCurrentEnvironment(ordered)
        return (compatibleOrder.first, Array(compatibleOrder.dropFirst()))
    }

    nonisolated private static func manualHostURLs(host: String, candidates: [URL]) -> [URL] {
        var mcdnResourceURL: URL?
        var upgcxcodeFallbackURL: URL?

        for url in candidates {
            if url.isRewritableBiliMirrorURL {
                if url.hasMCDNQuery {
                    upgcxcodeFallbackURL = upgcxcodeFallbackURL ?? url
                    continue
                }
                if let rewritten = url.rewritingHost(host) {
                    return ([rewritten] + candidates).removingDuplicateURLs()
                }
            }

            if url.isMCDNResourceURL {
                mcdnResourceURL = mcdnResourceURL ?? url
                continue
            }

            if url.isUPGCXCodeURL {
                upgcxcodeFallbackURL = upgcxcodeFallbackURL ?? url
                continue
            }

            if url.isSZBDYDURL,
               let rewritten = url.rewritingSZBDYDURL(fallbackHost: host) {
                return ([rewritten] + candidates).removingDuplicateURLs()
            }
        }

        if let upgcxcodeFallbackURL,
           let rewritten = upgcxcodeFallbackURL.rewritingHost(host) {
            return ([rewritten] + candidates).removingDuplicateURLs()
        }

        if let mcdnResourceURL,
           let proxied = mcdnResourceURL.proxiedTFURL {
            return ([proxied] + candidates).removingDuplicateURLs()
        }

        return candidates
    }
}

private extension URL {
    nonisolated var isUPGCXCodeURL: Bool {
        path.contains("/upgcxcode/")
    }

    nonisolated var isRewritableBiliMirrorURL: Bool {
        guard isUPGCXCodeURL,
              let host = host?.lowercased()
        else { return false }
        if host.hasPrefix("upos-"), !host.contains("-302.") {
            return host.isKnownBiliMediaCDNHost
        }
        if host.hasPrefix("upos-tf-") || host.hasPrefix("proxy-tf-") {
            return host.isKnownBiliMediaCDNHost
        }
        return false
    }

    nonisolated var isMCDNResourceURL: Bool {
        guard let host = host?.lowercased() else { return false }
        let isMCDNHost = host.contains(".mcdn.bilivideo.")
            || host.range(of: #"^\d{1,3}(\.\d{1,3}){3}$"#, options: .regularExpression) != nil
        guard isMCDNHost else { return false }
        return path.range(of: #"^/v\d+/resource"#, options: .regularExpression) != nil
    }

    nonisolated var isSZBDYDURL: Bool {
        host?.localizedCaseInsensitiveContains("szbdyd.com") == true
    }

    nonisolated var hasMCDNQuery: Bool {
        guard let components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return false }
        return components.queryItems?.contains {
            $0.name.localizedCaseInsensitiveCompare("os") == .orderedSame
                && $0.value?.localizedCaseInsensitiveCompare("mcdn") == .orderedSame
        } == true
    }

    nonisolated var proxiedTFURL: URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "proxy-tf-all-ws.bilivideo.com"
        components.queryItems = [URLQueryItem(name: "url", value: absoluteString)]
        return components.url
    }

    nonisolated func rewritingHost(_ host: String) -> URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.host = host
        return components.url
    }

    nonisolated func rewritingSZBDYDURL(fallbackHost: String) -> URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let sourceHost = components.queryItems?.first {
            $0.name.localizedCaseInsensitiveCompare("xy_usource") == .orderedSame
        }?.value
        components.scheme = "https"
        components.host = sourceHost?.isEmpty == false ? sourceHost : fallbackHost
        components.port = 443
        return components.url
    }
}

private extension String {
    nonisolated var isKnownBiliMediaCDNHost: Bool {
        contains(".bilivideo.")
            || contains(".acgvideo.")
            || contains(".akamaized.")
            || hasSuffix(".edge.mountaintoys.cn")
    }
}

private extension Array where Element == URL {
    nonisolated func removingDuplicateURLs() -> [URL] {
        var seen = Set<String>()
        return filter { url in
            seen.insert(url.absoluteString).inserted
        }
    }
}

nonisolated final class PlaybackURLPreferenceStore: @unchecked Sendable {
    static let shared = PlaybackURLPreferenceStore()

    private let lock = NSLock()
    private let ttl: TimeInterval = 24 * 60 * 60
    private let maxScoreCount = 256
    private let storeURL: URL
    private var scores: [String: HostScore] = [:]
    private var hasLoadedStore = false
    private var persistTask: Task<Void, Never>?
    private var persistDirty = false

    private init() {
        storeURL = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PlaybackURLPreferenceScores.json")
    }

    func orderedURLs(_ urls: [URL]) -> [URL] {
        let urls = urls.removingDuplicateURLs()
        guard urls.count > 1 else { return urls }
        loadStoreIfNeeded()
        let scoredURLs = lock.withLock {
            urls.enumerated().map { index, url -> (index: Int, url: URL, score: Double?) in
                guard let host = url.host,
                      let score = scores[scoreKey(for: host)],
                      score.isUsefulForAutomaticOrdering
                else {
                    return (index, url, nil)
                }
                return (index, url, score.rankScore)
            }
        }
        let scoredCount = scoredURLs.filter { $0.score != nil }.count
        let shouldDemotePrimary = lock.withLock { () -> Bool in
            guard let primaryHost = urls.first?.host,
                  let score = scores[scoreKey(for: primaryHost)]
            else { return false }
            return score.shouldDemoteInAutomaticOrdering
        }
        guard scoredCount >= 2 || shouldDemotePrimary else { return urls }
        return scoredURLs
            .sorted { lhs, rhs in
                switch (lhs.score, rhs.score) {
                case let (left?, right?):
                    if abs(left - right) > 60 {
                        return left < right
                    }
                    return lhs.index < rhs.index
                case (.some, .none):
                    guard lhs.index == 0, shouldDemotePrimary else {
                        return lhs.index < rhs.index
                    }
                    return false
                case (.none, .some):
                    guard rhs.index == 0, shouldDemotePrimary else {
                        return lhs.index < rhs.index
                    }
                    return true
                case (.none, .none):
                    return lhs.index < rhs.index
                }
            }
            .map(\.url)
    }

    func record(url: URL, elapsedMilliseconds: Double, bytes: Int64, succeeded: Bool) {
        guard let host = url.host else { return }
        loadStoreIfNeeded()
        lock.withLock {
            let key = scoreKey(for: host)
            var score = scores[key] ?? HostScore()
            score.record(
                elapsedMilliseconds: elapsedMilliseconds,
                bytes: bytes,
                succeeded: succeeded,
                date: Date()
            )
            scores[key] = score
            trimExpiredLocked()
            trimIfNeededLocked()
            persistDirty = true
        }
        schedulePersist()
    }

    func recordPlaybackFeedback(
        url: URL,
        observedKilobitsPerSecond: Int,
        transferMilliseconds: Int,
        bytes: Int64,
        stallCount: Int
    ) {
        guard let host = url.host else { return }
        let boundedTransferMilliseconds = min(max(Double(transferMilliseconds), 10), 8_000)
        let syntheticBytes: Int64
        if bytes > 0 {
            syntheticBytes = bytes
        } else if observedKilobitsPerSecond > 0, transferMilliseconds > 0 {
            syntheticBytes = Int64(
                (Double(observedKilobitsPerSecond) * 1_000 / 8)
                    * max(Double(transferMilliseconds) / 1_000, 0.001)
            )
        } else {
            syntheticBytes = 0
        }

        guard syntheticBytes > 0 || stallCount > 0 else { return }
        loadStoreIfNeeded()
        lock.withLock {
            let key = scoreKey(for: host)
            var score = scores[key] ?? HostScore()
            let now = Date()
            if syntheticBytes > 0 {
                score.record(
                    elapsedMilliseconds: boundedTransferMilliseconds,
                    bytes: syntheticBytes,
                    succeeded: true,
                    date: now
                )
            }
            if stallCount > 0 {
                let stallPenaltyMilliseconds = min(max(boundedTransferMilliseconds + Double(stallCount) * 900, 900), 8_000)
                for _ in 0..<min(stallCount, 4) {
                    score.record(
                        elapsedMilliseconds: stallPenaltyMilliseconds,
                        bytes: 0,
                        succeeded: false,
                        date: now
                    )
                }
            }
            scores[key] = score
            trimExpiredLocked()
            trimIfNeededLocked()
            persistDirty = true
        }
        schedulePersist()
    }

    func rankedSnapshots(limit: Int = 8, currentNetworkOnly: Bool = true) -> [PlaybackURLPreferenceSnapshot] {
        loadStoreIfNeeded()
        let currentNetworkKey = PlaybackEnvironment.current.networkClass.cacheKey
        let snapshots = lock.withLock { () -> [PlaybackURLPreferenceSnapshot] in
            trimExpiredLocked()
            return scores.compactMap { key, score in
                guard let snapshot = snapshot(for: key, score: score) else { return nil }
                guard !currentNetworkOnly || snapshot.networkKey == currentNetworkKey else { return nil }
                return snapshot
            }
        }
        return Array(
            snapshots
                .sorted { lhs, rhs in
                    if abs(lhs.rankScore - rhs.rankScore) > 0.01 {
                        return lhs.rankScore < rhs.rankScore
                    }
                    if lhs.failureRatePercent != rhs.failureRatePercent {
                        return lhs.failureRatePercent < rhs.failureRatePercent
                    }
                    return lhs.lastUpdatedAt > rhs.lastUpdatedAt
                }
                .prefix(max(limit, 0))
        )
    }

    func snapshot(forHost host: String) -> PlaybackURLPreferenceSnapshot? {
        loadStoreIfNeeded()
        let key = scoreKey(for: host)
        return lock.withLock {
            guard let score = scores[key] else { return nil }
            return snapshot(for: key, score: score)
        }
    }

    private func scoreKey(for host: String) -> String {
        "\(PlaybackEnvironment.current.networkClass.cacheKey)|\(host.lowercased())"
    }

    private func snapshot(for key: String, score: HostScore) -> PlaybackURLPreferenceSnapshot? {
        let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let networkKey = parts[0]
        let host = parts[1]
        return PlaybackURLPreferenceSnapshot(
            id: key,
            host: host,
            networkKey: networkKey,
            networkTitle: Self.networkTitle(for: networkKey),
            averageMilliseconds: Int(score.averageMilliseconds.rounded()),
            averageKilobytesPerSecond: Int(score.averageKilobytesPerSecond.rounded()),
            successCount: score.successCount,
            failureCount: score.failureCount,
            lastUpdatedAt: score.date,
            rankScore: score.rankScore
        )
    }

    private static func networkTitle(for key: String) -> String {
        switch key {
        case "wifi":
            return "Wi-Fi"
        case "cellular":
            return "蜂窝网络"
        case "constrained":
            return "受限网络"
        case "unknown":
            return "未知网络"
        default:
            return key
        }
    }

    private func loadStoreIfNeeded() {
        var shouldLoad = false
        lock.withLock {
            if !hasLoadedStore {
                hasLoadedStore = true
                shouldLoad = true
            }
        }
        guard shouldLoad else { return }
        let persistedScores: [String: HostScore]
        if let data = try? Data(contentsOf: storeURL),
           let decodedScores = try? JSONDecoder().decode([String: HostScore].self, from: data) {
            persistedScores = decodedScores
        } else {
            persistedScores = [:]
        }
        lock.withLock {
            scores = persistedScores
            trimExpiredLocked()
            trimIfNeededLocked()
        }
    }

    private func schedulePersist() {
        let shouldSchedule = lock.withLock { () -> Bool in
            guard persistTask == nil else { return false }
            return true
        }
        guard shouldSchedule else { return }
        let store = self
        let storeURL = storeURL
        let task = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 700_000_000)
            let snapshot = store.persistenceSnapshot()
            do {
                try FileManager.default.createDirectory(
                    at: storeURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: storeURL, options: .atomic)
            } catch {}
            store.completePersist()
        }
        lock.withLock {
            persistTask = task
        }
    }

    private func persistenceSnapshot() -> [String: HostScore] {
        lock.withLock {
            persistDirty = false
            return scores
        }
    }

    private func completePersist() {
        let needsReschedule = lock.withLock { () -> Bool in
            persistTask = nil
            return persistDirty
        }
        if needsReschedule {
            schedulePersist()
        }
    }

    private func trimExpiredLocked() {
        let expiry = Date().addingTimeInterval(-ttl)
        scores = scores.filter { $0.value.date >= expiry }
    }

    private func trimIfNeededLocked() {
        guard scores.count > maxScoreCount else { return }
        let keptKeys = Set(
            scores
                .sorted { $0.value.date > $1.value.date }
                .prefix(maxScoreCount)
                .map(\.key)
        )
        scores = scores.filter { keptKeys.contains($0.key) }
    }

    private struct HostScore: Codable, Sendable {
        var averageMilliseconds: Double
        var averageKilobytesPerSecond: Double
        var successCount: Int
        var failureCount: Int
        var date: Date

        init(
            averageMilliseconds: Double = 900,
            averageKilobytesPerSecond: Double = 0,
            successCount: Int = 0,
            failureCount: Int = 0,
            date: Date = .distantPast
        ) {
            self.averageMilliseconds = averageMilliseconds
            self.averageKilobytesPerSecond = averageKilobytesPerSecond
            self.successCount = successCount
            self.failureCount = failureCount
            self.date = date
        }

        var rankScore: Double {
            let attempts = max(successCount + failureCount, 1)
            let failureRate = Double(failureCount) / Double(attempts)
            let throughputBonus = min(averageKilobytesPerSecond / 256.0, 300)
            let repeatedFailurePenalty = Double(min(failureCount, 8)) * 85
            return averageMilliseconds + failureRate * 1_200 + repeatedFailurePenalty - throughputBonus
        }

        var attemptCount: Int {
            successCount + failureCount
        }

        var failureRate: Double {
            guard attemptCount > 0 else { return 0 }
            return Double(failureCount) / Double(attemptCount)
        }

        var isUsefulForAutomaticOrdering: Bool {
            attemptCount >= 2 || failureCount > 0
        }

        var shouldDemoteInAutomaticOrdering: Bool {
            guard attemptCount >= 2 else { return false }
            return failureRate >= 0.45 || (failureCount >= 2 && successCount == 0)
        }

        mutating func record(
            elapsedMilliseconds: Double,
            bytes: Int64,
            succeeded: Bool,
            date: Date
        ) {
            let boundedElapsed = min(max(elapsedMilliseconds, 10), 8_000)
            let alpha = successCount + failureCount == 0 ? 1.0 : 0.28
            averageMilliseconds = averageMilliseconds * (1 - alpha) + boundedElapsed * alpha
            if succeeded {
                successCount += 1
                if bytes > 0, boundedElapsed > 0 {
                    let kbps = (Double(bytes) / 1024.0) / max(boundedElapsed / 1000.0, 0.001)
                    let throughputAlpha = averageKilobytesPerSecond <= 0 ? 1.0 : 0.24
                    averageKilobytesPerSecond = averageKilobytesPerSecond * (1 - throughputAlpha) + kbps * throughputAlpha
                }
            } else {
                failureCount += 1
            }
            if successCount + failureCount > 80 {
                successCount = max(successCount / 2, succeeded ? 1 : 0)
                failureCount = failureCount / 2
            }
            self.date = date
        }
    }
}

private extension PlaybackEnvironment.NetworkClass {
    nonisolated var cacheKey: String {
        switch self {
        case .wifi:
            return "wifi"
        case .cellular:
            return "cellular"
        case .constrained:
            return "constrained"
        case .unknown:
            return "unknown"
        }
    }
}

private extension NSLock {
    nonisolated func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}

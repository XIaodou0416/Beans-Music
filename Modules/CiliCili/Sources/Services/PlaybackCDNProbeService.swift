import Foundation
import Darwin

enum PlaybackCDNProbeMode: String, Codable, Equatable, Sendable {
    case realPlaybackURL
    case bareHostFallback

    var title: String {
        switch self {
        case .realPlaybackURL:
            return "真实播放 URL"
        case .bareHostFallback:
            return "Host 裸探测"
        }
    }
}

struct PlaybackCDNProbeResult: Identifiable, Codable, Equatable, Sendable {
    let preference: PlaybackCDNPreference
    let elapsedMilliseconds: Int?
    let didSucceed: Bool
    let errorDescription: String?
    let addressFamily: PlaybackNetworkAddressFamily?
    let probeMode: PlaybackCDNProbeMode
    let httpStatusCode: Int?
    let hostWasRewritten: Bool
    let isWeakReference: Bool
    let isCandidateCompatible: Bool
    let probedHost: String?
    let probePathDescription: String?

    private enum CodingKeys: String, CodingKey {
        case preference
        case elapsedMilliseconds
        case didSucceed
        case errorDescription
        case addressFamily
        case probeMode
        case httpStatusCode
        case hostWasRewritten
        case isWeakReference
        case isCandidateCompatible
        case probedHost
        case probePathDescription
    }

    init(
        preference: PlaybackCDNPreference,
        elapsedMilliseconds: Int?,
        didSucceed: Bool,
        errorDescription: String?,
        addressFamily: PlaybackNetworkAddressFamily? = nil,
        probeMode: PlaybackCDNProbeMode = .bareHostFallback,
        httpStatusCode: Int? = nil,
        hostWasRewritten: Bool = false,
        isWeakReference: Bool = false,
        isCandidateCompatible: Bool = true,
        probedHost: String? = nil,
        probePathDescription: String? = nil
    ) {
        self.preference = preference
        self.elapsedMilliseconds = elapsedMilliseconds
        self.didSucceed = didSucceed
        self.errorDescription = errorDescription
        self.addressFamily = addressFamily
        self.probeMode = probeMode
        self.httpStatusCode = httpStatusCode
        self.hostWasRewritten = hostWasRewritten
        self.isWeakReference = isWeakReference
        self.isCandidateCompatible = isCandidateCompatible
        self.probedHost = probedHost
        self.probePathDescription = probePathDescription
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.preference = try container.decode(PlaybackCDNPreference.self, forKey: .preference)
        self.elapsedMilliseconds = try container.decodeIfPresent(Int.self, forKey: .elapsedMilliseconds)
        self.didSucceed = try container.decode(Bool.self, forKey: .didSucceed)
        self.errorDescription = try container.decodeIfPresent(String.self, forKey: .errorDescription)
        self.addressFamily = try container.decodeIfPresent(PlaybackNetworkAddressFamily.self, forKey: .addressFamily)
        self.probeMode = try container.decodeIfPresent(PlaybackCDNProbeMode.self, forKey: .probeMode) ?? .bareHostFallback
        self.httpStatusCode = try container.decodeIfPresent(Int.self, forKey: .httpStatusCode)
        self.hostWasRewritten = try container.decodeIfPresent(Bool.self, forKey: .hostWasRewritten) ?? false
        self.isWeakReference = try container.decodeIfPresent(Bool.self, forKey: .isWeakReference) ?? false
        self.isCandidateCompatible = try container.decodeIfPresent(Bool.self, forKey: .isCandidateCompatible) ?? true
        self.probedHost = try container.decodeIfPresent(String.self, forKey: .probedHost)
        self.probePathDescription = try container.decodeIfPresent(String.self, forKey: .probePathDescription)
    }

    var id: PlaybackCDNPreference { preference }

    var isActionableForPlaybackRecommendation: Bool {
        didSucceed && !isWeakReference && elapsedMilliseconds != nil
    }

    var failureReason: String? {
        guard !didSucceed else { return nil }
        return errorDescription?.isEmpty == false ? errorDescription : "连接失败"
    }

    var userFacingStatus: String {
        if didSucceed {
            switch probeMode {
            case .realPlaybackURL:
                return "真实播放 URL 探测成功"
            case .bareHostFallback:
                return "Host 可达（弱参考）"
            }
        }
        if probeMode == .bareHostFallback,
           let httpStatusCode,
           Self.isBareHostRejectionStatus(httpStatusCode) {
            return "CDN 拒绝裸探测（弱参考）"
        }
        return failureReason ?? "连接失败"
    }

    var httpStatusTitle: String? {
        httpStatusCode.map { "HTTP \($0)" }
    }

    private static func isBareHostRejectionStatus(_ statusCode: Int) -> Bool {
        statusCode == 403 || statusCode == 959
    }
}

struct PlaybackCDNProbeSnapshot: Codable, Equatable, Sendable {
    static let defaultFreshnessInterval: TimeInterval = 24 * 60 * 60
    private static let minimumSwitchAdvantageMilliseconds = 80
    private static let minimumSwitchAdvantageRatio = 0.25

    let probedAt: Date
    let recommendedPreference: PlaybackCDNPreference?
    let results: [PlaybackCDNProbeResult]

    var successfulResults: [PlaybackCDNProbeResult] {
        results.filter { $0.didSucceed && $0.elapsedMilliseconds != nil }
    }

    var actionableResults: [PlaybackCDNProbeResult] {
        results.filter(\.isActionableForPlaybackRecommendation)
    }

    var isWeakReferenceOnly: Bool {
        !results.isEmpty && results.allSatisfy(\.isWeakReference)
    }

    func result(for preference: PlaybackCDNPreference) -> PlaybackCDNProbeResult? {
        results.first { $0.preference == preference }
    }

    func isExpired(now: Date = Date(), freshnessInterval: TimeInterval = Self.defaultFreshnessInterval) -> Bool {
        now.timeIntervalSince(probedAt) >= freshnessInterval
    }

    func stabilizedRecommendation(
        previous: PlaybackCDNProbeSnapshot?,
        keepsCurrentRecommendation: Bool = true
    ) -> PlaybackCDNProbeSnapshot {
        guard let previous,
              let currentPreference = previous.recommendedPreference
                ?? previous.actionableResults.first?.preference,
              previous.result(for: currentPreference)?.isActionableForPlaybackRecommendation == true
        else { return self }

        if !keepsCurrentRecommendation {
            return actionableResults.isEmpty
                ? preservingActionableResults(from: previous)
                : self
        }

        if actionableResults.isEmpty {
            return preservingActionableResults(from: previous)
        }

        guard let challengerPreference = recommendedPreference,
              let challengerResult = result(for: challengerPreference),
              challengerResult.isActionableForPlaybackRecommendation,
              let challengerElapsed = challengerResult.elapsedMilliseconds
        else {
            return preservingActionableResults(from: previous)
        }
        guard challengerPreference != currentPreference else { return self }
        guard let currentResult = result(for: currentPreference) else {
            return preservingActionableResults(from: previous)
        }
        guard currentResult.isActionableForPlaybackRecommendation,
              let currentElapsed = currentResult.elapsedMilliseconds
        else {
            return !currentResult.isCandidateCompatible
                ? preservingActionableResults(from: previous)
                : self
        }

        let requiredAdvantage = max(
            Self.minimumSwitchAdvantageMilliseconds,
            Int((Double(currentElapsed) * Self.minimumSwitchAdvantageRatio).rounded(.up))
        )
        guard currentElapsed - challengerElapsed >= requiredAdvantage else {
            return PlaybackCDNProbeSnapshot(
                probedAt: probedAt,
                recommendedPreference: currentPreference,
                results: results
            )
        }
        return self
    }

    private func preservingActionableResults(
        from previous: PlaybackCDNProbeSnapshot
    ) -> PlaybackCDNProbeSnapshot {
        var mergedResults = results
        for previousResult in previous.actionableResults {
            if let index = mergedResults.firstIndex(where: { $0.preference == previousResult.preference }) {
                if !mergedResults[index].isActionableForPlaybackRecommendation {
                    mergedResults[index] = previousResult
                }
            } else {
                mergedResults.append(previousResult)
            }
        }
        let recommendation = previous.recommendedPreference
            ?? previous.actionableResults.first?.preference
        return PlaybackCDNProbeSnapshot(
            probedAt: probedAt,
            recommendedPreference: recommendation,
            results: mergedResults
        )
    }
}

@MainActor
final class PlaybackCDNProbeCoordinator {
    static let shared = PlaybackCDNProbeCoordinator()

    private var refreshTask: Task<PlaybackCDNProbeSnapshot?, Never>?
    private var refreshToken: UUID?
    private var refreshUsesPlaybackURLs = false
    private var lastAdaptiveRefreshAt: Date?
    private var lastPressureRefreshAt: Date?
    private let pressureRefreshInterval: TimeInterval = 10 * 60
    private let failedProbeRetryInterval: TimeInterval = 15 * 60

    private init() {}

    func refreshIfNeeded(libraryStore: LibraryStore) {
        guard refreshTask == nil else { return }
        guard shouldRefresh(libraryStore: libraryStore) else { return }
        PlayerMetricsLog.signpostEvent(
            "PlaybackCDNRefresh",
            message: "trigger=adaptive preference=\(libraryStore.playbackCDNPreference.rawValue)"
        )
        startRefresh(libraryStore: libraryStore)
    }

    func refreshOnAppActivationIfNeeded(libraryStore: LibraryStore) {
        guard libraryStore.playbackCDNProbeRefreshPolicy == .appLaunch else {
            refreshIfNeeded(libraryStore: libraryStore)
            return
        }
        refreshNow(libraryStore: libraryStore, trigger: "appActivation")
    }

    func refreshNow(libraryStore: LibraryStore, trigger: String = "manual") {
        guard refreshTask == nil else { return }
        guard libraryStore.playbackCDNPreference == .automatic else { return }
        PlayerMetricsLog.signpostEvent(
            "PlaybackCDNRefresh",
            message: "trigger=\(trigger) preference=\(libraryStore.playbackCDNPreference.rawValue)"
        )
        startRefresh(libraryStore: libraryStore)
    }

    func refreshForPlaybackPressure(libraryStore: LibraryStore) {
        guard refreshTask == nil else { return }
        guard libraryStore.playbackCDNPreference == .automatic else { return }
        let now = Date()
        if let lastPressureRefreshAt,
           now.timeIntervalSince(lastPressureRefreshAt) < pressureRefreshInterval {
            return
        }
        lastPressureRefreshAt = now
        PlayerMetricsLog.signpostEvent(
            "PlaybackCDNRefresh",
            message: "trigger=pressure preference=\(libraryStore.playbackCDNPreference.rawValue)"
        )
        startRefresh(libraryStore: libraryStore)
    }

    func refreshAfterSuccessfulPlaybackIfNeeded(
        libraryStore: LibraryStore,
        playbackURLs: [URL]
    ) {
        let playbackURLs = playbackURLs.removingDuplicateURLs()
        guard libraryStore.playbackCDNPreference == .automatic,
              !playbackURLs.isEmpty
        else { return }
        let hasVerifiedRecommendation = libraryStore.playbackCDNProbeSnapshotForCurrentContext?
            .actionableResults.isEmpty == false
        let stickyPreference = libraryStore.playbackCDNProbeSnapshotForCurrentContext?.recommendedPreference
        let activePreference = libraryStore.automaticPlaybackCDNRecommendation
        let isStickyPreferenceBeingAvoided = stickyPreference != nil && stickyPreference != activePreference
        guard !hasVerifiedRecommendation
                || isStickyPreferenceBeingAvoided
                || shouldRefresh(libraryStore: libraryStore)
        else { return }

        if refreshTask != nil {
            guard !refreshUsesPlaybackURLs else { return }
            refreshTask?.cancel()
            refreshTask = nil
            refreshToken = nil
        }
        PlayerMetricsLog.signpostEvent(
            "PlaybackCDNRefresh",
            message: "trigger=postFirstFrame mode=realURL urls=\(playbackURLs.count)"
        )
        startRefresh(libraryStore: libraryStore, playbackURLs: playbackURLs)
    }

    func prepareRecommendationForImmediatePlaybackIfNeeded(
        libraryStore: LibraryStore,
        timeout: TimeInterval = 0.75
    ) async {
        let signpostState = PlayerMetricsLog.beginSignpostedInterval(
            "PlaybackCDNImmediate",
            message: "timeout=\(String(format: "%.2f", timeout))"
        )
        var signpostMessage = "waiting"
        defer {
            PlayerMetricsLog.endSignpostedInterval(
                "PlaybackCDNImmediate",
                signpostState,
                message: signpostMessage
            )
        }
        guard libraryStore.playbackCDNPreference == .automatic else {
            signpostMessage = "skipped preference=\(libraryStore.playbackCDNPreference.rawValue)"
            return
        }
        refreshIfNeeded(libraryStore: libraryStore)
        guard libraryStore.automaticPlaybackCDNRecommendation == nil else {
            signpostMessage = "ready existing=\(libraryStore.automaticPlaybackCDNRecommendation?.rawValue ?? "-")"
            return
        }

        let deadline = Date().addingTimeInterval(max(0, timeout))
        let initialWait = min(max(timeout * 0.28, 0.08), 0.22)
        if await waitForAutomaticRecommendation(
            libraryStore: libraryStore,
            until: Date().addingTimeInterval(initialWait)
        ) {
            signpostMessage = "ready waited"
            return
        }

        guard libraryStore.automaticPlaybackCDNRecommendation == nil,
              !Task.isCancelled
        else {
            signpostMessage = "ready after wait"
            return
        }

        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0.12 else {
            signpostMessage = "timeout budget exhausted"
            return
        }

        let addressFamilyPreference = libraryStore.playbackNetworkAddressFamilyPreference
        let quickSnapshot = await PlaybackCDNProbeService.quickRecommendedSnapshot(
            addressFamilyPreference: addressFamilyPreference,
            timeout: remaining
        )

        guard !Task.isCancelled,
              libraryStore.playbackCDNPreference == .automatic,
              libraryStore.automaticPlaybackCDNRecommendation == nil,
              quickSnapshot.recommendedPreference != nil
        else {
            signpostMessage = "quick no recommendation"
            return
        }
        libraryStore.setPlaybackCDNProbeSnapshot(quickSnapshot)
        signpostMessage = "quick \(quickSnapshot.recommendedPreference?.rawValue ?? "-")"
    }

    private func waitForAutomaticRecommendation(
        libraryStore: LibraryStore,
        until deadline: Date
    ) async -> Bool {
        while libraryStore.automaticPlaybackCDNRecommendation == nil,
              Date() < deadline,
              !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 60_000_000)
        }
        return libraryStore.automaticPlaybackCDNRecommendation != nil
    }

    private func shouldRefresh(libraryStore: LibraryStore) -> Bool {
        guard libraryStore.playbackCDNPreference == .automatic else { return false }
        guard let snapshot = libraryStore.playbackCDNProbeSnapshotForCurrentContext else { return true }
        if snapshot.isExpired(freshnessInterval: libraryStore.playbackCDNProbeRefreshInterval) {
            return true
        }
        if snapshot.recommendedPreference == nil,
           snapshot.isExpired(freshnessInterval: failedProbeRetryInterval) {
            return true
        }
        guard PlayerPerformanceStore.shared.shouldRefreshPlaybackCDNProbe(
            isEnabled: libraryStore.isPlaybackAutoOptimizationEnabled
        ) else {
            return false
        }
        if snapshot.isExpired(freshnessInterval: libraryStore.playbackCDNProbeRefreshInterval) {
            return true
        }
        guard let lastAdaptiveRefreshAt else {
            return true
        }
        return Date().timeIntervalSince(lastAdaptiveRefreshAt) >= libraryStore.playbackCDNProbeRefreshInterval
    }

    private func startRefresh(libraryStore: LibraryStore, playbackURLs: [URL] = []) {
        let token = UUID()
        refreshToken = token
        refreshUsesPlaybackURLs = !playbackURLs.isEmpty
        refreshTask = Task(priority: .utility) { [weak self, weak libraryStore] in
            guard let libraryStore else { return nil }
            let signpostState = PlayerMetricsLog.beginSignpostedInterval(
                "PlaybackCDNRefresh",
                message: "mode=\(playbackURLs.isEmpty ? "host" : "realURL") preference=\(libraryStore.playbackCDNPreference.rawValue)"
            )
            var signpostMessage = "mode=\(playbackURLs.isEmpty ? "host" : "realURL") loading"
            defer {
                PlayerMetricsLog.endSignpostedInterval(
                    "PlaybackCDNRefresh",
                    signpostState,
                    message: signpostMessage
                )
            }
            let addressFamilyPreference = await MainActor.run {
                libraryStore.playbackNetworkAddressFamilyPreference
            }
            let snapshot = await PlaybackCDNProbeService.recommendedSnapshot(
                addressFamilyPreference: addressFamilyPreference,
                playbackURLs: playbackURLs
            )
            await MainActor.run {
                guard let self, self.refreshToken == token, !Task.isCancelled else { return }
                libraryStore.setPlaybackCDNProbeSnapshot(snapshot)
                if !libraryStore.needsPlaybackCDNProbeRefresh {
                    self.lastAdaptiveRefreshAt = Date()
                }
                self.refreshTask = nil
                self.refreshToken = nil
                self.refreshUsesPlaybackURLs = false
            }
            signpostMessage = "mode=\(playbackURLs.isEmpty ? "host" : "realURL") result=\(snapshot.recommendedPreference?.rawValue ?? "-")"
            return snapshot
        }
    }
}

enum PlaybackCDNProbeService {
    private static let probePath = "/upgcxcode/00/00/1/1.m4s"
    private static let timeout: TimeInterval = 2.2
    private static let acceptedSmallBodyLimit = 16 * 1024

    static func probeAll(
        addressFamilyPreference: PlaybackNetworkAddressFamilyPreference = .automatic,
        playbackURLs: [URL] = []
    ) async -> [PlaybackCDNProbeResult] {
        let candidates = PlaybackCDNPreference.manualProbeCandidates
        return await withTaskGroup(of: PlaybackCDNProbeResult.self) { group in
            for candidate in candidates {
                group.addTask(priority: .utility) {
                    await probe(
                        candidate,
                        addressFamilyPreference: addressFamilyPreference,
                        playbackURLs: playbackURLs
                    )
                }
            }

            var results = [PlaybackCDNProbeResult]()
            for await result in group {
                results.append(result)
            }
            return sortedResults(results)
        }
    }

    static func quickRecommendedSnapshot(
        addressFamilyPreference: PlaybackNetworkAddressFamilyPreference = .automatic,
        playbackURLs: [URL] = [],
        timeout: TimeInterval = 0.55
    ) async -> PlaybackCDNProbeSnapshot {
        let results = await quickProbeResults(
            addressFamilyPreference: addressFamilyPreference,
            playbackURLs: playbackURLs,
            timeout: timeout
        )
        let recommendation = results.first {
            $0.isActionableForPlaybackRecommendation
        }?.preference
        return PlaybackCDNProbeSnapshot(
            probedAt: Date(),
            recommendedPreference: recommendation,
            results: results
        )
    }

    static func recommendedPreference(
        addressFamilyPreference: PlaybackNetworkAddressFamilyPreference = .automatic,
        playbackURLs: [URL] = []
    ) async -> (preference: PlaybackCDNPreference?, results: [PlaybackCDNProbeResult]) {
        let results = await probeAll(
            addressFamilyPreference: addressFamilyPreference,
            playbackURLs: playbackURLs
        )
        let recommendation = results.first {
            $0.isActionableForPlaybackRecommendation
        }?.preference
        return (recommendation, results)
    }

    static func recommendedSnapshot(
        addressFamilyPreference: PlaybackNetworkAddressFamilyPreference = .automatic,
        playbackURLs: [URL] = []
    ) async -> PlaybackCDNProbeSnapshot {
        let recommendation = await recommendedPreference(
            addressFamilyPreference: addressFamilyPreference,
            playbackURLs: playbackURLs
        )
        return PlaybackCDNProbeSnapshot(
            probedAt: Date(),
            recommendedPreference: recommendation.preference,
            results: recommendation.results
        )
    }

    private static func probe(
        _ preference: PlaybackCDNPreference,
        addressFamilyPreference: PlaybackNetworkAddressFamilyPreference,
        playbackURLs: [URL],
        timeout: TimeInterval = 2.2
    ) async -> PlaybackCDNProbeResult {
        guard let host = preference.host else {
            return PlaybackCDNProbeResult(
                preference: preference,
                elapsedMilliseconds: nil,
                didSucceed: false,
                errorDescription: "没有可测速 Host",
                probeMode: .bareHostFallback
            )
        }

        if let requiredFamily = addressFamilyPreference.requiredFamily {
            do {
                let resolvedFamilies = try resolvedAddressFamilies(for: host)
                guard resolvedFamilies.contains(requiredFamily) else {
                    return PlaybackCDNProbeResult(
                        preference: preference,
                        elapsedMilliseconds: nil,
                        didSucceed: false,
                        errorDescription: "未解析到 \(requiredFamily.title) 地址",
                        addressFamily: nil,
                        probeMode: playbackURLs.isEmpty ? .bareHostFallback : .realPlaybackURL,
                        probedHost: host
                    )
                }
            } catch {
                return PlaybackCDNProbeResult(
                    preference: preference,
                    elapsedMilliseconds: nil,
                    didSucceed: false,
                    errorDescription: dnsFailureDescription(error),
                    addressFamily: nil,
                    probeMode: playbackURLs.isEmpty ? .bareHostFallback : .realPlaybackURL,
                    probedHost: host
                )
            }
        }

        let target = probeTarget(
            preference: preference,
            host: host,
            playbackURLs: playbackURLs
        )
        guard let target else {
            return PlaybackCDNProbeResult(
                preference: preference,
                elapsedMilliseconds: nil,
                didSucceed: false,
                errorDescription: playbackURLs.isEmpty ? "没有可测速 Host" : "当前播放 URL 不能安全改写到该 CDN",
                addressFamily: addressFamilyPreference.requiredFamily,
                probeMode: playbackURLs.isEmpty ? .bareHostFallback : .realPlaybackURL,
                isCandidateCompatible: playbackURLs.isEmpty,
                probedHost: host
            )
        }

        let url = target.url
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = timeout
        request.networkServiceType = .responsiveData
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")

        let start = Date()
        do {
            let (data, response) = try await BiliNetworkRetry.data(
                sessionProvider: { BiliPlaybackNetworkSessionPool.shared.playbackProbeSession() },
                request: request,
                policy: .playbackProbe
            )
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let didSucceed = didProbeSucceed(
                statusCode: statusCode,
                responseByteCount: data.count,
                mode: target.mode
            )
            return PlaybackCDNProbeResult(
                preference: preference,
                elapsedMilliseconds: elapsed,
                didSucceed: didSucceed,
                errorDescription: didSucceed ? nil : httpFailureDescription(statusCode: statusCode, mode: target.mode),
                addressFamily: addressFamilyPreference.requiredFamily,
                probeMode: target.mode,
                httpStatusCode: statusCode,
                hostWasRewritten: target.hostWasRewritten,
                isWeakReference: target.isWeakReference,
                probedHost: url.host,
                probePathDescription: pathDescription(for: url)
            )
        } catch {
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            return PlaybackCDNProbeResult(
                preference: preference,
                elapsedMilliseconds: elapsed,
                didSucceed: false,
                errorDescription: networkFailureDescription(error),
                addressFamily: addressFamilyPreference.requiredFamily,
                probeMode: target.mode,
                hostWasRewritten: target.hostWasRewritten,
                isWeakReference: target.isWeakReference,
                probedHost: url.host,
                probePathDescription: pathDescription(for: url)
            )
        }
    }

    private struct ProbeTarget: Sendable {
        let url: URL
        let mode: PlaybackCDNProbeMode
        let hostWasRewritten: Bool
        let isWeakReference: Bool
    }

    private static func probeTarget(
        preference: PlaybackCDNPreference,
        host: String,
        playbackURLs: [URL]
    ) -> ProbeTarget? {
        let playbackURLs = playbackURLs.removingDuplicateURLs()
        if !playbackURLs.isEmpty {
            if let url = playbackURLs.first(where: {
                $0.host?.localizedCaseInsensitiveCompare(host) == .orderedSame
            }) {
                return ProbeTarget(
                    url: url,
                    mode: .realPlaybackURL,
                    hostWasRewritten: false,
                    isWeakReference: false
                )
            }
            let rewritten = preference.preferredURLs(
                primary: playbackURLs.first,
                backups: Array(playbackURLs.dropFirst())
            )
            let candidates = ([rewritten.primary].compactMap { $0 } + rewritten.backups)
                .removingDuplicateURLs()
            if let url = candidates.first(where: {
                $0.host?.localizedCaseInsensitiveCompare(host) == .orderedSame
                    && !playbackURLs.contains($0)
            }) {
                return ProbeTarget(
                    url: url,
                    mode: .realPlaybackURL,
                    hostWasRewritten: true,
                    isWeakReference: false
                )
            }
            return nil
        }

        guard let fallbackURL = URL(string: "https://\(host)\(probePath)") else { return nil }
        return ProbeTarget(
            url: fallbackURL,
            mode: .bareHostFallback,
            hostWasRewritten: false,
            isWeakReference: true
        )
    }

    private static func didProbeSucceed(
        statusCode: Int,
        responseByteCount: Int,
        mode: PlaybackCDNProbeMode
    ) -> Bool {
        if statusCode == 206 { return true }
        if statusCode == 200 {
            return responseByteCount <= acceptedSmallBodyLimit
        }
        if mode == .realPlaybackURL,
           (300..<400).contains(statusCode) {
            return true
        }
        return false
    }

    private static func httpFailureDescription(statusCode: Int, mode: PlaybackCDNProbeMode) -> String {
        switch statusCode {
        case 0:
            return "未收到 HTTP 响应"
        case 400:
            return "请求参数异常（HTTP 400）"
        case 401:
            return "需要鉴权（HTTP 401）"
        case 403:
            if mode == .bareHostFallback {
                return "CDN 拒绝裸探测，仅代表 Host 可达性弱参考（HTTP 403）"
            }
            return "播放地址被拒绝（HTTP 403）"
        case 404:
            return "探测资源不存在（HTTP 404）"
        case 408:
            return "CDN 响应超时（HTTP 408）"
        case 429:
            return "请求过于频繁（HTTP 429）"
        case 500...599:
            return "CDN 服务异常（HTTP \(statusCode)）"
        case 959:
            if mode == .bareHostFallback {
                return "CDN 拒绝裸探测，仅代表 Host 可达性弱参考（HTTP 959）"
            }
            return "CDN 拒绝当前播放请求（HTTP 959）"
        default:
            return "HTTP 状态异常（\(statusCode)）"
        }
    }

    private static func dnsFailureDescription(_ error: Error) -> String {
        if let error = error as? DNSResolutionError {
            return error.reasonDescription
        }
        return "DNS 解析失败：\(error.localizedDescription)"
    }

    private static func networkFailureDescription(_ error: Error) -> String {
        if error is CancellationError {
            return "测速已取消"
        }
        guard let urlError = error as? URLError else {
            return "连接失败：\(error.localizedDescription)"
        }

        switch urlError.code {
        case .timedOut:
            return "连接超时"
        case .cannotFindHost, .dnsLookupFailed:
            return "DNS 解析失败"
        case .cannotConnectToHost:
            return "无法连接到 CDN Host"
        case .networkConnectionLost:
            return "连接中断"
        case .notConnectedToInternet:
            return "当前网络不可用"
        case .cannotLoadFromNetwork:
            return "系统禁止从网络加载"
        case .secureConnectionFailed:
            return "TLS 握手失败"
        case .serverCertificateUntrusted,
             .serverCertificateHasBadDate,
             .serverCertificateNotYetValid,
             .serverCertificateHasUnknownRoot:
            return "证书校验失败"
        case .appTransportSecurityRequiresSecureConnection:
            return "ATS 安全策略拦截"
        case .badServerResponse:
            return "服务器响应异常"
        case .resourceUnavailable:
            return "资源不可用"
        case .cancelled:
            return "测速被取消"
        default:
            return "连接失败（\(urlError.code.rawValue)）"
        }
    }

    private static func quickProbeResults(
        addressFamilyPreference: PlaybackNetworkAddressFamilyPreference,
        playbackURLs: [URL],
        timeout: TimeInterval
    ) async -> [PlaybackCDNProbeResult] {
        let clampedTimeout = min(max(timeout, 0.12), Self.timeout)
        return await withTaskGroup(of: PlaybackCDNProbeResult?.self) { group in
            for candidate in PlaybackCDNPreference.manualProbeCandidates {
                group.addTask(priority: .userInitiated) {
                    await probe(
                        candidate,
                        addressFamilyPreference: addressFamilyPreference,
                        playbackURLs: playbackURLs,
                        timeout: clampedTimeout
                    )
                }
            }

            group.addTask(priority: .userInitiated) {
                try? await Task.sleep(nanoseconds: UInt64(clampedTimeout * 1_000_000_000))
                return nil
            }

            var results = [PlaybackCDNProbeResult]()
            while let result = await group.next() {
                guard let result else {
                    group.cancelAll()
                    break
                }
                results.append(result)
                if result.isActionableForPlaybackRecommendation {
                    group.cancelAll()
                    break
                }
            }
            return sortedResults(results)
        }
    }

    private static func sortedResults(_ results: [PlaybackCDNProbeResult]) -> [PlaybackCDNProbeResult] {
        results.sorted { lhs, rhs in
            if lhs.isActionableForPlaybackRecommendation != rhs.isActionableForPlaybackRecommendation {
                return lhs.isActionableForPlaybackRecommendation
            }
            if lhs.didSucceed != rhs.didSucceed {
                return lhs.didSucceed
            }
            switch (lhs.elapsedMilliseconds, rhs.elapsedMilliseconds) {
            case let (left?, right?):
                return left < right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return lhs.preference.title < rhs.preference.title
            }
        }
    }

    private static func pathDescription(for url: URL) -> String {
        let path = url.path.lowercased()
        if path.contains("/upgcxcode/") {
            return "upgcxcode 媒体片段"
        }
        if path.range(of: #"^/v\d+/resource"#, options: .regularExpression) != nil {
            return "MCDN resource"
        }
        let ext = url.pathExtension
        if !ext.isEmpty {
            return "\(ext.lowercased()) 媒体路径"
        }
        return "媒体路径"
    }

    private static func resolvedAddressFamilies(for host: String) throws -> Set<PlaybackNetworkAddressFamily> {
        var hints = addrinfo(
            ai_flags: 0,
            ai_family: AF_UNSPEC,
            ai_socktype: 0,
            ai_protocol: 0,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, nil, &hints, &result)
        guard status == 0 else {
            throw DNSResolutionError(code: status)
        }
        defer {
            if let result {
                freeaddrinfo(result)
            }
        }

        var families = Set<PlaybackNetworkAddressFamily>()
        var pointer = result
        while let current = pointer {
            switch current.pointee.ai_family {
            case AF_INET:
                families.insert(.ipv4)
            case AF_INET6:
                families.insert(.ipv6)
            default:
                break
            }
            pointer = current.pointee.ai_next
        }
        return families
    }
}

private extension Array where Element == URL {
    func removingDuplicateURLs() -> [URL] {
        var seen = Set<String>()
        return filter { url in
            seen.insert(url.absoluteString).inserted
        }
    }
}

private struct DNSResolutionError: LocalizedError {
    let code: Int32

    var errorDescription: String? {
        String(cString: gai_strerror(code))
    }

    var reasonDescription: String {
        switch code {
        case EAI_NONAME:
            return "DNS 未找到主机"
        case EAI_AGAIN:
            return "DNS 临时失败"
        case EAI_FAIL:
            return "DNS 查询失败"
        default:
            return "DNS 解析失败：\(errorDescription ?? "code \(code)")"
        }
    }
}

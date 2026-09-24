import Foundation

nonisolated enum RemoteImageDiagnosticsSettings {
    static let storageKey = "cc.bili.display.remoteImageDiagnosticsEnabled.v1"
    static let defaultIsEnabled = true

    static func isEnabled(in userDefaults: UserDefaults = .standard) -> Bool {
        userDefaults.object(forKey: storageKey) as? Bool ?? defaultIsEnabled
    }

    static var isRecordingEnabled: Bool {
        RemoteImageDiagnosticsRuntime.shared.isEnabled
    }

    static func setEnabled(_ isEnabled: Bool, in userDefaults: UserDefaults = .standard) {
        userDefaults.set(isEnabled, forKey: storageKey)
        guard userDefaults === UserDefaults.standard else { return }
        RemoteImageDiagnosticsRuntime.shared.setEnabled(isEnabled)
    }
}

nonisolated final class RemoteImageDiagnosticsRuntime: @unchecked Sendable {
    static let shared = RemoteImageDiagnosticsRuntime()

    private let lock = NSLock()
    private var enabled = RemoteImageDiagnosticsSettings.isEnabled()

    var isEnabled: Bool {
        lock.withLock { enabled }
    }

    func setEnabled(_ isEnabled: Bool) {
        lock.withLock {
            enabled = isEnabled
        }
    }
}

nonisolated enum RemoteImageCDNFailoverPolicy {
    static let failureTTL: TimeInterval = 90
    static let interchangeableHosts = [
        "i0.hdslb.com",
        "i1.hdslb.com",
        "i2.hdslb.com"
    ]

    static func isEligible(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return interchangeableHosts.contains(host)
    }

    static func candidateURLs(for url: URL) -> [URL] {
        guard let sourceHost = url.host?.lowercased(), interchangeableHosts.contains(sourceHost) else {
            return [url]
        }

        return ([sourceHost] + interchangeableHosts.filter { $0 != sourceHost }).compactMap { host in
            guard host != sourceHost else { return url }
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.host = host
            return components?.url
        }
    }

    static func shouldDemote(statusCode: Int) -> Bool {
        BiliNetworkRetryPolicy.image.shouldRetry(statusCode: statusCode)
    }

    static func shouldDemote(error: Error) -> Bool {
        if error is CancellationError {
            return false
        }
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .networkConnectionLost,
             .notConnectedToInternet,
             .cannotLoadFromNetwork,
             .badServerResponse,
             .resourceUnavailable:
            return true
        default:
            return false
        }
    }
}

nonisolated struct RemoteImageCDNHostDiagnostics: Sendable, Equatable, Identifiable {
    let host: String
    let requestCount: Int
    let successCount: Int
    let transientFailureCount: Int

    var id: String { host }
}

nonisolated struct RemoteImageCDNDegradedHost: Sendable, Equatable, Identifiable {
    let host: String
    let remainingTime: TimeInterval

    var id: String { host }
}

nonisolated struct RemoteImageCDNDiagnosticsSnapshot: Sendable, Equatable {
    let requestCount: Int
    let successCount: Int
    let transientFailureCount: Int
    let automaticSwitchCount: Int
    let hosts: [RemoteImageCDNHostDiagnostics]
    let degradedHosts: [RemoteImageCDNDegradedHost]
}

nonisolated final class RemoteImageCDNHealthMemory: @unchecked Sendable {
    static let shared = RemoteImageCDNHealthMemory()

    private struct HostCounters {
        var requestCount = 0
        var successCount = 0
        var transientFailureCount = 0
    }

    private let lock = NSLock()
    private let failureTTL: TimeInterval
    private var unhealthyUntilByHost: [String: Date] = [:]
    private var requestCount = 0
    private var successCount = 0
    private var transientFailureCount = 0
    private var automaticSwitchCount = 0
    private var countersByHost: [String: HostCounters] = [:]

    init(failureTTL: TimeInterval = RemoteImageCDNFailoverPolicy.failureTTL) {
        self.failureTTL = max(failureTTL, 1)
    }

    func orderedCandidates(
        for urls: [URL],
        now: Date = Date()
    ) -> [URL] {
        let uniqueURLs = Self.uniqueURLs(urls)
        let candidates = Self.uniqueURLs(uniqueURLs.flatMap(RemoteImageCDNFailoverPolicy.candidateURLs))
        let unhealthyHosts = lock.withLock { () -> Set<String> in
            unhealthyUntilByHost = unhealthyUntilByHost.filter { $0.value > now }
            return Set(unhealthyUntilByHost.keys)
        }
        guard !unhealthyHosts.isEmpty else { return candidates }

        let healthy = candidates.filter { url in
            guard let host = url.host?.lowercased() else { return true }
            return !unhealthyHosts.contains(host)
        }
        let unhealthy = candidates.filter { url in
            guard let host = url.host?.lowercased() else { return false }
            return unhealthyHosts.contains(host)
        }
        return healthy + unhealthy
    }

    func recordRequest(
        for url: URL,
        originalURL: URL
    ) {
        guard RemoteImageCDNFailoverPolicy.isEligible(url),
              let host = url.host?.lowercased()
        else { return }
        guard RemoteImageDiagnosticsSettings.isRecordingEnabled else { return }
        let originalHost = originalURL.host?.lowercased()
        lock.withLock {
            requestCount += 1
            countersByHost[host, default: HostCounters()].requestCount += 1
            if RemoteImageCDNFailoverPolicy.isEligible(originalURL),
               originalHost != host {
                automaticSwitchCount += 1
            }
        }
    }

    func recordTransientFailure(
        for url: URL,
        now: Date = Date()
    ) {
        guard RemoteImageCDNFailoverPolicy.isEligible(url),
              let host = url.host?.lowercased()
        else { return }
        lock.withLock {
            if RemoteImageDiagnosticsSettings.isRecordingEnabled {
                transientFailureCount += 1
                countersByHost[host, default: HostCounters()].transientFailureCount += 1
            }
            unhealthyUntilByHost[host] = now.addingTimeInterval(failureTTL)
        }
    }

    func recordSuccess(for url: URL) {
        guard RemoteImageCDNFailoverPolicy.isEligible(url),
              let host = url.host?.lowercased()
        else { return }
        lock.withLock {
            if RemoteImageDiagnosticsSettings.isRecordingEnabled {
                successCount += 1
                countersByHost[host, default: HostCounters()].successCount += 1
            }
            unhealthyUntilByHost[host] = nil
        }
    }

    func diagnostics(now: Date = Date()) -> RemoteImageCDNDiagnosticsSnapshot {
        lock.withLock {
            unhealthyUntilByHost = unhealthyUntilByHost.filter { $0.value > now }
            let hosts = RemoteImageCDNFailoverPolicy.interchangeableHosts.map { host in
                let counters = countersByHost[host, default: HostCounters()]
                return RemoteImageCDNHostDiagnostics(
                    host: host,
                    requestCount: counters.requestCount,
                    successCount: counters.successCount,
                    transientFailureCount: counters.transientFailureCount
                )
            }
            let degradedHosts: [RemoteImageCDNDegradedHost] = RemoteImageCDNFailoverPolicy.interchangeableHosts.compactMap { host in
                guard let unhealthyUntil = unhealthyUntilByHost[host] else { return nil }
                return RemoteImageCDNDegradedHost(
                    host: host,
                    remainingTime: max(0, unhealthyUntil.timeIntervalSince(now))
                )
            }
            return RemoteImageCDNDiagnosticsSnapshot(
                requestCount: requestCount,
                successCount: successCount,
                transientFailureCount: transientFailureCount,
                automaticSwitchCount: automaticSwitchCount,
                hosts: hosts,
                degradedHosts: degradedHosts
            )
        }
    }

    func resetDiagnostics() {
        lock.withLock {
            requestCount = 0
            successCount = 0
            transientFailureCount = 0
            automaticSwitchCount = 0
            countersByHost.removeAll()
        }
    }

    func reset() {
        lock.withLock {
            unhealthyUntilByHost.removeAll()
        }
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.absoluteString).inserted }
    }
}
